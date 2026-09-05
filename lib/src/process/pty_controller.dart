import 'dart:async';
import 'dart:io';
import 'package:cinder/cinder.dart';

import 'pty_handler.dart';
import 'pty_output_buffer.dart';

/// A controller for managing a PTY (pseudo-terminal) process.
///
/// This controller follows the same pattern as Flutter's [TextEditingController],
/// providing a clean separation between the terminal's state management and UI.
/// Uses native PTYs on macOS/Linux and ConPTY on Windows 10 version 1809 or later.
///
/// Example usage:
/// ```dart
/// final controller = PtyController(
///   command: '/bin/bash',
///   onOutput: (data) => print('Terminal output: $data'),
/// );
///
/// // Start the terminal
/// await controller.start(columns: 80, rows: 24);
///
/// // Send input
/// controller.write('ls -la\n');
///
/// // Dispose when done
/// controller.dispose();
/// ```
class PtyController {
  /// The command to execute in the terminal.
  final String command;

  /// Command arguments.
  final List<String> arguments;

  /// Working directory for the process.
  final String? workingDirectory;

  /// Environment variables for the process.
  final Map<String, String>? environment;

  // Callbacks
  final List<void Function(String)> _outputCallbacks = [];
  final List<void Function(int)> _exitCallbacks = [];
  final List<void Function(Object)> _errorCallbacks = [];

  /// Maximum number of lines to buffer.
  final int maxBufferLines;

  /// Maximum UTF-8 bytes to retain, including one byte per completed newline.
  /// Oversized lines retain their newest complete characters. Output callbacks
  /// continue receiving all output even when history retention is disabled.
  final int maxBufferBytes;

  // Internal state
  PtyHandler? _ptyHandler;
  StreamSubscription<String>? _outputSubscription;
  StreamSubscription<int>? _exitSubscription;
  late final _outputBuffer = PtyOutputBuffer(
    maxLines: maxBufferLines,
    maxBytes: maxBufferBytes,
  );
  bool _disposed = false;
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  PtyStatus _status = PtyStatus.notStarted;
  int _rows = 24;
  int _columns = 80;
  int? _exitCode;

  // Change notification
  final List<VoidCallback> _listeners = [];

  /// Creates a new PTY controller.
  PtyController({
    String? command,
    this.arguments = const [],
    this.workingDirectory,
    this.environment,
    void Function(String)? onOutput,
    void Function(int)? onExit,
    void Function(Object)? onError,
    this.maxBufferLines = 10000,
    this.maxBufferBytes = 8 * 1024 * 1024,
  }) : command = command ?? _getDefaultShell() {
    if (maxBufferLines < 0) {
      throw ArgumentError.value(
        maxBufferLines,
        'maxBufferLines',
        'Must not be negative',
      );
    }
    if (maxBufferBytes < 0) {
      throw ArgumentError.value(
        maxBufferBytes,
        'maxBufferBytes',
        'Must not be negative',
      );
    }
    if (onOutput != null) _outputCallbacks.add(onOutput);
    if (onExit != null) _exitCallbacks.add(onExit);
    if (onError != null) _errorCallbacks.add(onError);
  }

  /// Gets the default shell for the current platform.
  static String _getDefaultShell() {
    if (Platform.isWindows) {
      return Platform.environment['COMSPEC'] ?? 'cmd.exe';
    } else {
      return Platform.environment['SHELL'] ?? '/bin/bash';
    }
  }

  /// Current status of the PTY process.
  PtyStatus get status => _status;

  /// Whether the terminal is running.
  bool get isRunning => _status == PtyStatus.running;

  /// Process ID of the terminal transport, null before startup or after disposal.
  int? get pid => _ptyHandler?.pid;

  /// Exit code of the process, or null if still running.
  int? get exitCode => _exitCode;

  /// Current number of terminal rows.
  int get rows => _rows;

  /// Current number of terminal columns.
  int get columns => _columns;

  /// Output buffer containing recent terminal output.
  List<String> get outputBuffer => _outputBuffer.lines;

  /// Starts the PTY process with the specified dimensions.
  Future<void> start({required int columns, required int rows}) async {
    if (_disposed) throw StateError('Terminal controller has been disposed');
    if (_status == PtyStatus.starting || _status == PtyStatus.running) {
      throw StateError('Terminal is already starting or running');
    }
    _validateDimensions(columns, rows);

    final settled = Completer<void>();
    _startFuture = settled.future;
    _rows = rows;
    _columns = columns;
    _exitCode = null;
    _status = PtyStatus.starting;

    try {
      _notifyListeners();
      await _releaseProcess();
      if (_disposed) return;
      final handler = PtyHandlerFactory.create(
        command: command,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
      _ptyHandler = handler;
      _outputSubscription = handler.output.listen(
        (data) {
          if (_disposed) return;
          _addToBuffer(data);
          for (final callback in _outputCallbacks.toList()) {
            callback(data);
          }
        },
        onError: (Object error) {
          if (_disposed) return;
          for (final callback in _errorCallbacks.toList()) {
            callback(error);
          }
        },
      );
      await handler.start(columns: columns, rows: rows);
      if (_disposed) return;

      _exitSubscription = handler.exitCode.asStream().listen((code) {
        if (_disposed || !identical(_ptyHandler, handler)) return;
        _exitCode = code;
        _status = PtyStatus.exited;
        _notifyListeners();
        for (final callback in _exitCallbacks.toList()) {
          callback(code);
        }
      });
      _status = PtyStatus.running;
      _notifyListeners();
    } catch (error) {
      await _releaseProcess();
      if (!_disposed) {
        _status = PtyStatus.error;
        _exitCode = -1;
        _notifyListeners();
        for (final callback in _errorCallbacks.toList()) {
          callback(error);
        }
      }
      rethrow;
    } finally {
      settled.complete();
      _startFuture = null;
    }
  }

  /// Writes text data to the terminal.
  ///
  /// Throws [StateError] if pending input reaches 1 MiB or 256 writes. Retry
  /// after the child consumes input; queued input is cancelled on disposal.
  void write(String data) {
    if (!isRunning) {
      throw StateError('Terminal is not running');
    }
    _ptyHandler?.write(data);
  }

  /// Writes raw bytes to the terminal.
  ///
  /// Throws [StateError] if pending input reaches 1 MiB or 256 writes.
  void writeBytes(List<int> bytes) {
    if (!isRunning) {
      throw StateError('Terminal is not running');
    }
    _ptyHandler?.writeBytes(bytes);
  }

  /// Resizes the operating-system terminal and updates its display dimensions.
  void resize(int columns, int rows) {
    if (!isRunning) return;
    _validateDimensions(columns, rows);
    _ptyHandler?.resize(rows, columns);

    _columns = columns;
    _rows = rows;
    _notifyListeners();
  }

  /// Requests a signal for the terminal process.
  ///
  /// Unix signals run asynchronously across terminal job groups. Returns false
  /// when another signal is pending, except that SIGKILL can queue escalation.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!isRunning) return false;

    return _ptyHandler?.kill(signal) ?? false;
  }

  /// Clears the output buffer.
  void clearBuffer() {
    _outputBuffer.clear();
    _notifyListeners();
  }

  void _addToBuffer(String data) {
    _outputBuffer.add(data);
    _notifyListeners();
  }

  static void _validateDimensions(int columns, int rows) {
    if (columns <= 0 || rows <= 0 || columns > 32767 || rows > 32767) {
      throw ArgumentError('Terminal dimensions must be between 1 and 32767');
    }
  }

  /// Restarts the process while retaining callbacks, listeners, and dimensions.
  Future<void> restart() async {
    if (_disposed) throw StateError('Terminal controller has been disposed');
    await _startFuture;
    _status = PtyStatus.notStarted;
    await _releaseProcess();
    await start(columns: _columns, rows: _rows);
  }

  /// Adds an output callback.
  void addOutputCallback(void Function(String) callback) {
    _outputCallbacks.add(callback);
  }

  /// Removes an output callback.
  void removeOutputCallback(void Function(String) callback) {
    _outputCallbacks.remove(callback);
  }

  /// Adds an exit callback.
  void addExitCallback(void Function(int) callback) {
    _exitCallbacks.add(callback);
  }

  /// Removes an exit callback.
  void removeExitCallback(void Function(int) callback) {
    _exitCallbacks.remove(callback);
  }

  /// Adds an error callback.
  void addErrorCallback(void Function(Object) callback) {
    _errorCallbacks.add(callback);
  }

  /// Removes an error callback.
  void removeErrorCallback(void Function(Object) callback) {
    _errorCallbacks.remove(callback);
  }

  /// Adds a listener that will be called when the controller changes.
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Removes a listener.
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  /// Notifies all listeners of a change.
  void _notifyListeners() {
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  /// Disposes of the controller and releases all resources.
  Future<void> dispose() {
    _disposed = true;
    _status = PtyStatus.disposed;
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    await _startFuture;
    await _releaseProcess();
    _listeners.clear();
    _outputCallbacks.clear();
    _exitCallbacks.clear();
    _errorCallbacks.clear();
  }

  Future<void> _releaseProcess() async {
    final handler = _ptyHandler;
    _ptyHandler = null;
    await _outputSubscription?.cancel();
    await _exitSubscription?.cancel();
    _outputSubscription = null;
    _exitSubscription = null;
    await handler?.dispose();
  }
}

/// Status of the PTY process.
enum PtyStatus {
  /// Terminal has not been started yet.
  notStarted,

  /// Terminal is starting up.
  starting,

  /// Terminal is running.
  running,

  /// Terminal has exited.
  exited,

  /// Terminal encountered an error.
  error,

  /// Terminal has been disposed.
  disposed,
}
