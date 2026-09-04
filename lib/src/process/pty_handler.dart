import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Internal subprocess transport used by [PtyController].
///
/// Windows uses redirected process streams; Unix allocates a terminal through
/// the system `script` utility. The display dimensions are provided at startup
/// through environment variables. This transport cannot set a live PTY's
/// window size, so resizing must never be sent as application input.
@internal
class PtyHandler {
  final String command;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;

  Process? _process;
  final _outputController = StreamController<String>.broadcast(sync: true);
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final _stdoutDone = Completer<void>();
  final _stderrDone = Completer<void>();
  Future<void>? _startFuture;
  Future<void>? _disposeFuture;
  bool _disposed = false;

  int? get pid => _process?.pid;

  PtyHandler({
    required this.command,
    this.arguments = const [],
    this.workingDirectory,
    this.environment,
  });

  String get _executable => command;
  List<String> get _arguments => arguments;

  Future<void> start({required int columns, required int rows}) {
    if (_disposed || _startFuture != null || _process != null) {
      return Future.error(
        StateError('Process has already been started or disposed'),
      );
    }
    return _startFuture = _start(columns: columns, rows: rows);
  }

  Future<void> _start({required int columns, required int rows}) async {
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
      ...?environment,
    });

    final process = await Process.start(
      _executable,
      _arguments,
      workingDirectory: workingDirectory,
      environment: effectiveEnv,
      includeParentEnvironment: false,
    );
    _process = process;
    _stdoutSubscription = _listen(process.stdout, _stdoutDone);
    _stderrSubscription = _listen(process.stderr, _stderrDone);
  }

  StreamSubscription<String> _listen(
    Stream<List<int>> stream,
    Completer<void> done,
  ) {
    return stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (data) {
            if (!_outputController.isClosed) _outputController.add(data);
          },
          onError: (Object error, StackTrace stack) {
            if (!_outputController.isClosed) {
              _outputController.addError(error, stack);
            }
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
  }

  /// Subscribe before [start] to receive even the first output chunk.
  Stream<String> get output => _outputController.stream;

  /// Completes after both output streams drain, so exit callbacks see all output.
  Future<int> get exitCode async {
    final process = _process;
    if (process == null) throw StateError('Process not started');
    final code = await process.exitCode;
    await Future.wait([_stdoutDone.future, _stderrDone.future]);
    return code;
  }

  void write(String data) {
    final process = _process;
    if (_disposed || process == null) throw StateError('Process not running');
    process.stdin.write(data);
  }

  void writeBytes(List<int> bytes) {
    final process = _process;
    if (_disposed || process == null) throw StateError('Process not running');
    process.stdin.add(bytes);
  }

  /// The pipe fallback has no operating-system terminal to resize.
  void resize(int rows, int columns) {}

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    return _process?.kill(signal) ?? false;
  }

  Future<void> dispose() {
    _disposed = true;
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    try {
      await _startFuture;
    } catch (_) {
      // A failed launch still owns its output controller.
    }
    final process = _process;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return process.exitCode;
        },
      );
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    if (!_stdoutDone.isCompleted) _stdoutDone.complete();
    if (!_stderrDone.isCompleted) _stderrDone.complete();
    await _outputController.close();
    _process = null;
  }
}

/// Allocates a Unix PTY with the platform's `script` utility.
@internal
class UnixPtyHandler extends PtyHandler {
  UnixPtyHandler({
    required super.command,
    super.arguments,
    super.workingDirectory,
    super.environment,
  });

  @override
  String get _executable => 'script';

  @override
  List<String> get _arguments {
    if (Platform.isMacOS) return ['-q', '/dev/null', command, ...arguments];
    // util-linux script passes -c through a shell. Quote each argument and use
    // -e to propagate the child's status instead of script's own success code.
    String quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
    final commandLine = [command, ...arguments].map(quote).join(' ');
    return ['-q', '-e', '-c', commandLine, '/dev/null'];
  }

  @override
  void resize(int rows, int columns) {
    // Notify the wrapper without injecting an escape sequence into stdin.
    // Actual PTY window-size changes require a native ioctl backend.
    _process?.kill(ProcessSignal.sigwinch);
  }
}

@internal
class PtyHandlerFactory {
  static PtyHandler create({
    required String command,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return Platform.isWindows
        ? PtyHandler(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
          )
        : UnixPtyHandler(
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
          );
  }
}
