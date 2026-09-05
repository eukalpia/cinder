import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'native_pty_process.dart';
import 'native_pty_unix.dart';
import 'native_pty_windows.dart';

/// Asynchronous lifecycle and UTF-8 decoding around the native PTY handles.
@internal
class PtyHandler {
  final String command;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final _output = StreamController<String>.broadcast(sync: true);
  final _bytes = StreamController<List<int>>(sync: true);
  final _outputDone = Completer<void>();
  final _processExit = Completer<int>();
  NativePtyProcess? _process;
  Timer? _timer;
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  Future<void> _writes = Future.value();
  Future<void>? _finishing;
  bool _disposed = false;
  bool _readClosed = false;
  int _pendingWriteBytes = 0;
  int _pendingWriteCount = 0;

  PtyHandler({
    required this.command,
    this.arguments = const [],
    this.workingDirectory,
    this.environment,
  }) {
    _bytes.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (data) {
            if (!_output.isClosed) _output.add(data);
          },
          onError: (Object error, StackTrace stack) {
            if (!_output.isClosed) _output.addError(error, stack);
          },
          onDone: _outputDone.complete,
        );
  }

  int? get pid => _process?.pid;
  Stream<String> get output => _output.stream;

  Future<void> start({required int columns, required int rows}) {
    if (_disposed || _startFuture != null) {
      return Future.error(
        StateError('Process has already been started or disposed'),
      );
    }
    return _startFuture = _start(columns, rows);
  }

  Future<void> _start(int columns, int rows) async {
    if (command.isEmpty ||
        [
          command,
          ...arguments,
          if (workingDirectory != null) workingDirectory!,
        ].any((value) => value.contains('\x00')) ||
        (environment?.entries.any(
              (entry) =>
                  entry.key.isEmpty ||
                  entry.key.contains('=') ||
                  entry.key.contains('\x00') ||
                  entry.value.contains('\x00'),
            ) ??
            false)) {
      throw ArgumentError(
        'PTY command, arguments and environment must be valid native strings',
      );
    }
    final effectiveEnv = Map<String, String>.of(Platform.environment);
    for (final name in const [
      'WARP_TERMINAL',
      'WARP_BOOTSTRAPPED',
      'WARP_IS_LOCAL_SHELL_SESSION',
      'WARP_USE_SSH_WRAPPER',
      'FIG_TERM',
      'FIG_ENV_VAR',
      'ITERM_SHELL_INTEGRATION_INSTALLED',
      'VSCODE_SHELL_INTEGRATION',
      'INSIDE_EMACS',
      'STARSHIP_SHELL',
    ]) {
      effectiveEnv.remove(name);
    }
    effectiveEnv.addAll({
      'TERM': 'xterm-256color',
      'LINES': '$rows',
      'COLUMNS': '$columns',
      'TERM_PROGRAM': 'Cinder',
      ...?(Platform.isWindows && environment != null
          ? normalizeWindowsEnvironment(environment!)
          : environment),
    });
    _process = Platform.isWindows
        ? WindowsNativePty.start(
            command,
            arguments,
            workingDirectory,
            effectiveEnv,
            rows,
            columns,
          )
        : await UnixNativePty.start(
            command,
            arguments,
            workingDirectory,
            effectiveEnv,
            rows,
            columns,
          );
    // Read only ready data, with a per-turn cap so heavy output yields to UI and
    // input. Idle terminals never hold a blocking FFI call on the UI isolate.
    _timer = Timer.periodic(const Duration(milliseconds: 4), (_) => _pump());
    _pump();
  }

  void _pump() {
    final process = _process;
    if (process == null) return;
    try {
      if (!_readClosed) {
        for (var i = 0; i < 8; i++) {
          final chunk = process.read();
          if (chunk == null) break;
          if (chunk.isEmpty) {
            _closeOutput();
            break;
          }
          _bytes.add(chunk);
        }
      }
      final code = process.pollExit();
      if (code != null && !_processExit.isCompleted) {
        _processExit.complete(code);
        _finishing = process.finish();
        unawaited(
          _finishing!.catchError((Object error, StackTrace stack) {
            if (!_output.isClosed && !_disposed) _output.addError(error, stack);
            _closeOutput();
          }),
        );
      }
      if (_readClosed && _processExit.isCompleted) _timer?.cancel();
    } catch (error, stack) {
      if (!_output.isClosed && !_disposed) _output.addError(error, stack);
      process.kill(ProcessSignal.sigkill);
      _closeOutput();
    }
  }

  void _closeOutput() {
    if (_readClosed) return;
    _readClosed = true;
    unawaited(_bytes.close());
  }

  Future<int> get exitCode async {
    if (_process == null) throw StateError('Process not started');
    final code = await _processExit.future;
    await _outputDone.future;
    return code;
  }

  void write(String data) {
    _checkWriteCapacity(data.length);
    writeBytes(utf8.encode(data));
  }

  void _checkWriteCapacity(int bytes) {
    if (bytes > 1024 * 1024 - _pendingWriteBytes || _pendingWriteCount >= 256) {
      throw StateError('PTY input queue is full (1 MiB or 256 pending writes)');
    }
  }

  void writeBytes(List<int> bytes) {
    final process = _process;
    if (_disposed || process == null || _processExit.isCompleted) {
      throw StateError('Process not running');
    }
    if (bytes.isEmpty) return;
    _checkWriteCapacity(bytes.length);
    final owned = Uint8List.fromList(bytes);
    _pendingWriteBytes += owned.length;
    _pendingWriteCount++;
    _writes = _writes
        .then((_) async {
          try {
            if (!_disposed) await process.write(owned);
          } finally {
            _pendingWriteBytes -= owned.length;
            _pendingWriteCount--;
          }
        })
        .catchError((Object error, StackTrace stack) {
          if (!_disposed && !_output.isClosed) _output.addError(error, stack);
        });
  }

  void resize(int rows, int columns) => _process?.resize(rows, columns);
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      _process?.kill(signal) ?? false;

  Future<void> dispose() {
    _disposed = true;
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    try {
      await _startFuture;
    } catch (_) {
      /* Failed launches still own streams. */
    }
    final process = _process;
    if (process != null) {
      process.stopWriting();
      if (!_processExit.isCompleted) {
        process.kill(ProcessSignal.sigterm);
        await _processExit.future.timeout(
          const Duration(seconds: 1),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return _processExit.future;
          },
        );
      }
      await _finishing;
      if (Platform.isWindows) await _outputDone.future;
      await _writes;
      await process.close();
    }
    _timer?.cancel();
    _closeOutput();
    await _outputDone.future;
    await _output.close();
    _process = null;
  }
}

@internal
class PtyHandlerFactory {
  static PtyHandler create({
    required String command,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
  }) => PtyHandler(
    command: command,
    arguments: arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}
