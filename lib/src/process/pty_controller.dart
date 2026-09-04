import 'dart:async';
import 'dart:io';
import 'package:cinder/cinder.dart';

import 'pty_handler.dart';

/// A controller for managing a PTY (pseudo-terminal) process.
///
/// This controller follows the same pattern as Flutter's [TextEditingController],
/// providing a clean separation between the terminal's state management and UI.
/// Unix uses the system `script` utility; Windows uses redirected process
/// streams without native ConPTY support.
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

  // Internal state
  PtyHandler? _ptyHandler;
  StreamSubscription<String>? _outputSubscription;
  StreamSubscription<int>? _exitSubscription;
  final List<String> _outputBuffer = [];
  String _partialLine = '';
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
  }) : command = command ?? _getDefaultShell() {
    if (maxBufferLines < 0) {
      throw ArgumentError.value(
        maxBufferLines,
        'maxBufferLines',
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
  List<String> get outputBuffer => List.unmodifiable([
    ..._outputBuffer,
    if (_partialLine.isNotEmpty) _partialLine,
  ]);

  /// Starts the PTY process with the specified dimensions.
  Future<void> start({required int columns, required int rows}) async {
    if (_disposed) throw StateError('Terminal controller has been disposed');
    if (_status == PtyStatus.starting || _status == PtyStatus.running) {
      throw StateError('Terminal is already starting or running');
    }
    if (columns <= 0 || rows <= 0) {
      throw ArgumentError('Terminal dimensions must be positive');
    }

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
  void write(String data) {
    if (!isRunning) {
      throw StateError('Terminal is not running');
    }
    _ptyHandler?.write(data);
  }

  /// Writes raw bytes to the terminal.
  void writeBytes(List<int> bytes) {
    if (!isRunning) {
      throw StateError('Terminal is not running');
    }
    _ptyHandler?.writeBytes(bytes);
  }

  /// Updates the display dimensions and notifies the terminal transport.
  ///
  /// The current script/pipe transport cannot set a live PTY's window size.
  void resize(int columns, int rows) {
    if (!isRunning) return;

    _columns = columns;
    _rows = rows;
    _ptyHandler?.resize(rows, columns);
    _notifyListeners();
  }

  /// Kills the terminal process.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!isRunning) return false;

    return _ptyHandler?.kill(signal) ?? false;
  }

  /// Clears the output buffer.
  void clearBuffer() {
    _outputBuffer.clear();
    _partialLine = '';
    _notifyListeners();
  }

  /// Adds output to the buffer, maintaining max size.
  void _addToBuffer(String data) {
    final lines = (_partialLine + data).split('\n');
    _partialLine = lines.removeLast();
    for (final line in lines) {
      _outputBuffer.add(
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
      );
    }
    while (_outputBuffer.length + (_partialLine.isEmpty ? 0 : 1) >
        maxBufferLines) {
      if (_outputBuffer.isNotEmpty) {
        _outputBuffer.removeAt(0);
      } else {
        _partialLine = '';
      }
    }
    _notifyListeners();
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
