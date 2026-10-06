import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'cinder_paths.dart';
import 'log_output_queue.dart';
import 'owner_only_permissions.dart';

/// A WebSocket-based log server that streams log messages to connected clients.
///
/// This server maintains a bounded buffer of recent log entries and streams
/// them to WebSocket clients. When a client connects, it receives all buffered
/// logs first, then receives new logs as they arrive.
///
/// Features:
/// - **Bounded history**: Defaults to 10,000 entries and 1 MiB of message storage
/// - **WebSocket streaming**: Multiple clients can connect simultaneously
/// - **Authentication**: Clients must present a random per-server bearer token
/// - **Browser isolation**: Requests carrying an `Origin` header are refused
/// - **Discovery**: Writes a [LogServerEndpoint] to
///   `~/.cinder/<hash>/log_port.<pid>`, readable only by the current user
/// - **Snapshots**: `/logs?mode=get` sends buffered entries and closes the connection
/// - **Graceful shutdown**: Cleans up connections and the endpoint file on close
///
/// `runApp` starts a log server only in debug builds or when asked to; see
/// its `enableLogServer` parameter.
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
  String? _publishedEndpoint;

  /// Secret that every client must present; never logged or sent to clients.
  final String _token = _generateToken();

  /// HTTP server for WebSocket connections
  HttpServer? _server;

  /// Port the server is listening on (null if not started)
  int? get port => _server?.port;

  /// Address and credential for connecting to this server, or null before it
  /// is listening.
  LogServerEndpoint? get endpoint {
    final port = this.port;
    return port == null ? null : LogServerEndpoint(port: port, token: _token);
  }

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

      _server!.listen(_handleRequest);

      // Publish the endpoint for CLI discovery
      await _writePortFile();
    } catch (e) {
      await _server?.close(force: true);
      stderr.writeln('Failed to start log server: $e');
      _server = null;
      rethrow;
    }
  }

  void _handleRequest(HttpRequest request) {
    // Browsers attach Origin to every WebSocket handshake, including
    // cross-site and DNS-rebound pages; `cinder logs` never sends one.
    if (request.headers['origin'] != null) {
      _reject(request, HttpStatus.forbidden);
    } else if (request.uri.path != '/logs') {
      _reject(request, HttpStatus.notFound);
    } else if (!_isAuthorized(request)) {
      _reject(request, HttpStatus.unauthorized);
    } else {
      unawaited(_handleWebSocketConnection(request));
    }
  }

  bool _isAuthorized(HttpRequest request) {
    final values = request.headers[HttpHeaders.authorizationHeader];
    if (values == null || values.length != 1) return false;
    final credentials = values.single;
    const scheme = 'bearer ';
    if (credentials.length <= scheme.length ||
        credentials.substring(0, scheme.length).toLowerCase() != scheme) {
      return false;
    }
    return _constantTimeEquals(
      credentials.substring(scheme.length).trim(),
      _token,
    );
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var index = 0; index < a.length; index++) {
      difference |= a.codeUnitAt(index) ^ b.codeUnitAt(index);
    }
    return difference == 0;
  }

  static void _reject(HttpRequest request, int statusCode) {
    final response = request.response..statusCode = statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
    }
    unawaited(response.close().then<void>((_) {}, onError: (Object _) {}));
  }

  static String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
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

  /// Publish the endpoint in the global log_port file.
  ///
  /// The file holds the bearer token, so it is written only into an
  /// owner-only directory and file, then renamed into place so a reader never
  /// observes partial contents. If permissions cannot be restricted the
  /// endpoint is not published; in-process clients can still use [endpoint].
  Future<void> _writePortFile() async {
    final contents = endpoint!.encode();
    final path = getLogPortPath();
    final temporary = File(
      p.join(p.dirname(path), '.${p.basename(path)}.${_generateToken()}.tmp'),
    );
    var created = false;
    try {
      await ensureCinderDirectoryExists();
      restrictToOwner(getCinderDirectory(), directory: true);

      await temporary.create(exclusive: true);
      created = true;
      restrictToOwner(temporary.path, directory: false);
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(path);
      created = false;
      _publishedEndpoint = contents;
    } catch (e) {
      stderr.writeln('Warning: Failed to publish log server endpoint: $e');
      if (created) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
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
      if (_publishedEndpoint != null &&
          await portFile.exists() &&
          await portFile.readAsString() == _publishedEndpoint) {
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

/// Address and credential that a [LogServer] publishes for `cinder logs`.
///
/// The endpoint file is readable only by the user who started the
/// application. Clients present [token] as a bearer credential and must not
/// send an `Origin` header; [connect] does both.
final class LogServerEndpoint {
  const LogServerEndpoint({required this.port, required this.token});

  /// Loopback TCP port of the server.
  final int port;

  /// Per-server secret required to connect.
  final String token;

  /// Parses the contents of an endpoint file.
  ///
  /// Returns null for malformed files, including the unauthenticated
  /// port-only format written by earlier releases.
  static LogServerEndpoint? tryParse(String contents) {
    final Object? json;
    try {
      json = jsonDecode(contents);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final port = json['port'];
    final token = json['token'];
    if (port is! int || port <= 0 || port > 65535) return null;
    if (token is! String || token.isEmpty) return null;
    return LogServerEndpoint(port: port, token: token);
  }

  /// Serializes this endpoint in the format read by [tryParse].
  String encode() => jsonEncode({'port': port, 'token': token});

  /// The WebSocket address for live streaming, or for a [snapshot] that
  /// closes after sending buffered entries.
  Uri uri({bool snapshot = false}) => Uri(
    scheme: 'ws',
    host: '127.0.0.1',
    port: port,
    path: '/logs',
    queryParameters: snapshot ? const {'mode': 'get'} : null,
  );

  /// Opens an authenticated connection to the server.
  Future<WebSocket> connect({bool snapshot = false}) => WebSocket.connect(
    uri(snapshot: snapshot).toString(),
    headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
  );

  // The token is deliberately omitted so diagnostics cannot leak it.
  @override
  String toString() => 'LogServerEndpoint(port: $port)';
}

/// A log entry with timestamp and message
class LogEntry {
  LogEntry({required this.timestamp, required this.message});

  final DateTime timestamp;
  final String message;
}
