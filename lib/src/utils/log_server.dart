import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'cinder_paths.dart';
import 'log_output_queue.dart';

/// A WebSocket-based log server that streams log messages to connected clients.
///
/// This server maintains a bounded buffer of recent log entries and streams
/// them to WebSocket clients. When a client connects, it receives all buffered
/// logs first, then receives new logs as they arrive.
///
/// Features:
/// - **Bounded history**: Defaults to 10,000 entries and 1 MiB of message storage
/// - **WebSocket streaming**: Multiple clients can connect simultaneously
/// - **Port discovery**: Writes port to `~/.cinder/<hash>/log_port.<pid>` for CLI discovery
/// - **Snapshots**: `/logs?mode=get` sends buffered entries and closes the connection
/// - **Graceful shutdown**: Cleans up connections and port file on close
///
/// Example:
/// ```dart
/// final server = LogServer(maxBufferSize: 10000);
/// await server.start();
///
/// server.log('Application started');
/// server.log('Processing data...');
///
/// await server.close();
/// ```
class LogServer {
  LogServer({
    this.maxBufferSize = 10000,
    this.maxBufferBytes = 1024 * 1024,
    this.maxClients = 16,
    this.maxPendingClientBytes = 2 * 1024 * 1024,
    this.maxPendingClientMessages = 1024,
  }) {
    if (maxBufferSize < 0) {
      throw ArgumentError.value(
        maxBufferSize,
        'maxBufferSize',
        'must be non-negative',
      );
    }
    if (maxBufferBytes < 0) {
      throw ArgumentError.value(
        maxBufferBytes,
        'maxBufferBytes',
        'must be non-negative',
      );
    }
    if (maxClients <= 0 ||
        maxPendingClientBytes <= 0 ||
        maxPendingClientMessages <= 0) {
      throw ArgumentError('Client and pending output limits must be positive');
    }
  }

  /// Maximum simultaneous log connections, including snapshot clients.
  final int maxClients;

  /// Per-client live backlog plus in-flight JSON, counting two bytes per UTF-16
  /// code unit. A slow client is disconnected when this or the entry cap is
  /// exceeded. Replay retains a separate bounded history snapshot and encodes
  /// one entry at a time. Socket/kernel buffers are outside this application cap.
  final int maxPendingClientBytes;
  final int maxPendingClientMessages;

  /// Maximum number of log entries to keep in buffer
  final int maxBufferSize;

  /// Upper bound on retained message storage, counting two bytes per UTF-16
  /// code unit. Entry and queue overhead are separately bounded by
  /// [maxBufferSize]. This excludes JSON encoding, client output queues, and
  /// snapshots held by callers. Oversized messages still reach connected
  /// clients but are omitted from history. Zero disables history without
  /// disabling streaming.
  final int maxBufferBytes;

  /// Circular buffer of log entries
  final Queue<LogEntry> _buffer = Queue<LogEntry>();
  int _bufferBytes = 0;

  /// Set of connected WebSocket clients
  final Set<_LogConnection> _clients = <_LogConnection>{};
  int _openingClients = 0;
  Future<void>? _startFuture;
  Future<void>? _closeFuture;
  int? _publishedPort;

  /// HTTP server for WebSocket connections
  HttpServer? _server;

  /// Port the server is listening on (null if not started)
  int? get port => _server?.port;

  /// Whether the server has been closed
  bool _closed = false;

  /// Start the WebSocket server
  Future<void> start() {
    if (_closed) {
      return Future.error(StateError('LogServer has been closed'));
    }

    if (_startFuture != null) {
      return Future.error(StateError('LogServer is already started'));
    }
    return _startFuture = _start();
  }

  Future<void> _start() async {
    try {
      // Start server on localhost with random port
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_closed) return;

      // Handle WebSocket upgrade requests
      _server!.listen((HttpRequest request) {
        if (request.uri.path == '/logs') {
          _handleWebSocketConnection(request);
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not found')
            ..close();
        }
      });

      // Write port to file for CLI discovery
      await _writePortFile();
    } catch (e) {
      await _server?.close(force: true);
      stderr.writeln('Failed to start log server: $e');
      _server = null;
      rethrow;
    }
  }

  /// Handle a new WebSocket connection
  Future<void> _handleWebSocketConnection(HttpRequest request) async {
    Socket? transport;
    var reserved = false;
    try {
      if (_closed || _clients.length + _openingClients >= maxClients) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      final key = request.headers.value('Sec-WebSocket-Key')!;
      if (base64.decode(key).length != 16) {
        throw const FormatException('Invalid WebSocket key');
      }
      _openingClients++;
      reserved = true;
      // Keep ownership of the socket so a stalled reader can be disconnected
      // immediately. WebSocket.close alone can wait for pending output forever.
      // RFC 6455 section 4.2.2; framing is still handled by dart:io.
      final accept = base64.encode(
        sha1
            .convert(
              ascii.encode(
                '$key'
                '258EAFA5-E914-47DA-95CA-C5AB0DC85B11',
              ),
            )
            .bytes,
      );
      request.response
        ..statusCode = HttpStatus.switchingProtocols
        ..headers.set(HttpHeaders.connectionHeader, 'Upgrade')
        ..headers.set(HttpHeaders.upgradeHeader, 'websocket')
        ..headers.set('Sec-WebSocket-Accept', accept);
      transport = await request.response.detachSocket();
      if (_closed) {
        transport.destroy();
        return;
      }
      final ws = WebSocket.fromUpgradedSocket(
        transport,
        serverSide: true,
        compression: CompressionOptions.compressionOff,
      );
      final snapshotOnly = request.uri.queryParameters['mode'] == 'get';
      final client = _LogConnection(
        ws,
        transport,
        snapshotOnly: snapshotOnly,
        replay: _buffer.toList().map(_encodeEntry),
        maxBytes: maxPendingClientBytes,
        maxMessages: maxPendingClientMessages,
        onClosed: _clients.remove,
      );
      _clients.add(client);
      client.start();
    } catch (e) {
      if (transport != null) {
        transport.destroy();
      } else {
        try {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
        } catch (_) {}
      }
    } finally {
      if (reserved) _openingClients--;
    }
  }

  static String _encodeEntry(LogEntry entry) => jsonEncode({
    'timestamp': entry.timestamp.toIso8601String(),
    'message': entry.message,
  });

  /// Add a log message to the buffer and broadcast to clients
  void log(String message) {
    if (_closed) return;

    final entry = LogEntry(timestamp: DateTime.now(), message: message);

    final entryBytes = message.length * 2;
    if (maxBufferSize > 0 &&
        maxBufferBytes > 0 &&
        entryBytes <= maxBufferBytes) {
      _buffer.add(entry);
      _bufferBytes += entryBytes;
      while (_buffer.length > maxBufferSize || _bufferBytes > maxBufferBytes) {
        _bufferBytes -= _buffer.removeFirst().message.length * 2;
      }
    }

    // Broadcast to all connected clients
    _broadcastEntry(entry);
  }

  /// Broadcast a log entry to all connected clients
  void _broadcastEntry(LogEntry entry) {
    String? json;
    for (final client in _clients) {
      if (client.snapshotOnly || client.output.isClosed) continue;
      client.output.add(json ??= _encodeEntry(entry));
    }
  }

  /// Write port number to global log_port file
  Future<void> _writePortFile() async {
    try {
      await ensureCinderDirectoryExists();

      final portFile = File(getLogPortPath());
      await portFile.writeAsString('$port');
      _publishedPort = port;
    } catch (e) {
      stderr.writeln('Warning: Failed to write log_port file: $e');
    }
  }

  /// Close the server and clean up resources
  Future<void> close() {
    _closed = true;
    return _closeFuture ??= _close();
  }

  Future<void> _close() async {
    try {
      await _startFuture;
    } catch (_) {}
    await Future.wait(_clients.toList().map((client) => client.close()));
    _clients.clear();

    // Close server
    if (_server != null) {
      try {
        await _server!.close(force: true);
      } catch (_) {
        // Ignore close errors
      }
      _server = null;
    }

    // Clean up port file
    try {
      final portFile = File(getLogPortPath());
      if (_publishedPort != null &&
          await portFile.exists() &&
          await portFile.readAsString() == '$_publishedPort') {
        await portFile.delete();
      }
    } catch (e) {
      stderr.writeln('Warning: Failed to delete log_port file: $e');
    }

    // Clear buffer
    _buffer.clear();
    _bufferBytes = 0;
  }

  /// Get a copy of the current buffer (for debugging/testing)
  List<LogEntry> get buffer => List.unmodifiable(_buffer);
}

class _LogConnection {
  _LogConnection(
    this.socket,
    this.transport, {
    required this.snapshotOnly,
    required Iterable<String> replay,
    required int maxBytes,
    required int maxMessages,
    required this.onClosed,
  }) {
    output = LogOutputQueue(
      maxBytes: maxBytes,
      maxMessages: maxMessages,
      replay: replay,
      closeWhenIdle: snapshotOnly,
      send: (message) async => socket.addStream(Stream.value(message)),
      onClose: () => unawaited(close()),
    );
  }

  final WebSocket socket;
  final Socket transport;
  final bool snapshotOnly;
  final void Function(_LogConnection) onClosed;
  late final LogOutputQueue output;
  StreamSubscription<dynamic>? _subscription;
  bool _closing = false;
  Future<void>? _closeFuture;

  void start() {
    _subscription = socket.listen(
      (_) {},
      onDone: () => unawaited(close()),
      onError: (Object _) => unawaited(close()),
    );
    output.start();
  }

  Future<void> close() {
    if (_closing) return _closeFuture ?? Future<void>.value();
    _closing = true;
    output.close();
    return _closeFuture = _close();
  }

  Future<void> _close() async {
    try {
      final closing = socket.close(WebSocketStatus.normalClosure);
      if (!snapshotOnly) transport.destroy();
      await closing.timeout(const Duration(seconds: 1));
    } catch (_) {
      // A vanished or stalled reader must not prevent framework shutdown.
    } finally {
      transport.destroy();
      await _subscription?.cancel();
      onClosed(this);
    }
  }
}

/// A log entry with timestamp and message
class LogEntry {
  LogEntry({required this.timestamp, required this.message});

  final DateTime timestamp;
  final String message;
}
