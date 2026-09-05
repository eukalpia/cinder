import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_pty_process.dart';

/// The system script utility owns the PTY session and child reaping. Native
/// ioctl updates its real window size; no resize command enters application I/O.
class UnixNativePty implements NativePtyProcess {
  static final _libc = DynamicLibrary.process();
  static final _open = _libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>),
        int Function(Pointer<Utf8>, int, int)
      >('open');
  static final _close = _libc
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final _fcntl = _libc
      .lookupFunction<
        Int32 Function(Int32, Int32, VarArgs<(Int32,)>),
        int Function(int, int, int)
      >('fcntl');
  static final _ioctl = _libc
      .lookupFunction<
        Int32 Function(Int32, UnsignedLong, VarArgs<(Pointer<Void>,)>),
        int Function(int, int, Pointer<Void>)
      >('ioctl');
  static final _session = _libc
      .lookupFunction<Int32 Function(Int32), int Function(int)>('getsid');
  static final _errno = _libc
      .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
        Platform.isMacOS ? '__error' : '__errno_location',
      );

  final Process _process;
  final Directory _directory;
  final _chunks = ListQueue<Uint8List>();
  late final StreamSubscription<List<int>> _stdout;
  late final StreamSubscription<List<int>> _stderr;
  final _streamsDone = Completer<void>();
  final _startupDone = Completer<void>();
  final _members = <int>{};
  int _streamsClosed = 0;
  int _queuedBytes = 0;
  bool _paused = false;
  int _terminalFd = -1;
  int? _sessionId;
  String? _tty;
  int? _rawExitCode;
  int? _exitCode;
  Object? _error;
  bool _closed = false;
  bool _acceptWrites = true;
  Future<void> _signals = Future.value();
  bool _signaling = false;
  ProcessSignal? _escalation;
  Future<void>? _finishing;

  UnixNativePty._(this._process, this._directory) {
    void receive(List<int> bytes) {
      _chunks.add(Uint8List.fromList(bytes));
      _queuedBytes += bytes.length;
      if (!_paused && _queuedBytes >= 256 * 1024) {
        _paused = true;
        _stdout.pause();
        _stderr.pause();
      }
    }

    void done() {
      if (++_streamsClosed == 2) _streamsDone.complete();
    }

    void error(Object error) {
      _error = error;
    }

    _stdout = _process.stdout.listen(receive, onError: error, onDone: done);
    _stderr = _process.stderr.listen(receive, onError: error, onDone: done);
    unawaited(
      _process.exitCode.then((code) async {
        _rawExitCode = code;
        // Clean up promptly while the private terminal/session still belongs to
        // this launch, rather than retaining numeric IDs until a later dispose.
        await finish();
        _exitCode = code;
      }),
    );
  }

  static Future<UnixNativePty> start(
    String command,
    List<String> arguments,
    String? directory,
    Map<String, String> environment,
    int rows,
    int columns,
  ) async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError('Native PTYs require macOS, Linux or Windows');
    }
    final temporary = await Directory.systemTemp.createTemp('cinder-pty-');
    UnixNativePty? result;
    try {
      final metadata = File('${temporary.path}/terminal');
      // The child bootstrap sets dimensions before exec, then records only
      // transport metadata in its private directory. All user arguments remain
      // positional parameters through both shells; none become shell source.
      const bootstrap =
          r'/bin/stty rows "$2" cols "$3" || exit; { printf "%s\n" "$$"; /usr/bin/tty; } > "$1"; while [ ! -e "$1.ready" ]; do /bin/sleep 0.01; done; if [ "$4" = 1 ]; then SHELL="$5"; export SHELL; else unset SHELL; fi; shift 5; exec "$@"';
      final child = [
        '/bin/sh',
        '-c',
        bootstrap,
        'cinder-pty',
        metadata.path,
        '$rows',
        '$columns',
        environment.containsKey('SHELL') ? '1' : '0',
        environment['SHELL'] ?? '',
        command,
        ...arguments,
      ];
      String quote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
      final process = await Process.start(
        '/usr/bin/script',
        Platform.isMacOS
            ? ['-q', '/dev/null', ...child]
            : ['-q', '-e', '-c', child.map(quote).join(' '), '/dev/null'],
        workingDirectory: directory,
        environment: {...environment, 'SHELL': '/bin/sh'},
        includeParentEnvironment: false,
      );
      result = UnixNativePty._(process, temporary);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (true) {
        if (await metadata.exists()) {
          final records = (await metadata.readAsString()).split('\n');
          if (records.length >= 3 && records[1].startsWith('/dev/')) {
            result._tty = records[1];
            final childPid = int.parse(records[0]);
            final session = _session(childPid);
            if (session <= 0 || session == _session(0)) {
              throw ProcessException(
                command,
                arguments,
                'Child has no private PTY session',
              );
            }
            result._sessionId = session;
            final fd = using(
              (arena) => _open(
                records[1].toNativeUtf8(allocator: arena),
                2 | (Platform.isMacOS ? 0x20000 : 0x100),
                0,
              ),
            );
            if (fd >= 0) {
              result._terminalFd = fd;
              if (_fcntl(fd, 2, 1) < 0) {
                throw ProcessException(
                  'fcntl(pty)',
                  const [],
                  'Cannot mark terminal descriptor close-on-exec',
                  _errno().value,
                );
              }
            } else {
              throw ProcessException(
                'open(pty)',
                const [],
                'Cannot open child terminal',
                _errno().value,
              );
            }
            await File('${metadata.path}.ready').writeAsString('');
            result._startupDone.complete();
            return result;
          }
        }
        if (result._rawExitCode != null) {
          // A very short command may exit before we open its slave; metadata
          // still establishes that the initial dimensions were applied.
          throw ProcessException(
            command,
            arguments,
            'PTY bootstrap exited before publishing its terminal',
            result._rawExitCode!,
          );
        }
        if (DateTime.now().isAfter(deadline)) {
          throw ProcessException(
            command,
            arguments,
            'Timed out waiting for PTY startup',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    } catch (_) {
      if (result != null) {
        if (!result._startupDone.isCompleted) result._startupDone.complete();
        result._process.kill(ProcessSignal.sigkill);
        await result._process.exitCode;
        await result.close();
      } else {
        await temporary.delete(recursive: true);
      }
      rethrow;
    }
  }

  @override
  int get pid => _process.pid;

  @override
  Uint8List? read() {
    final error = _error;
    _error = null;
    if (error != null) throw error;
    if (_chunks.isNotEmpty) {
      final chunk = _chunks.removeFirst();
      _queuedBytes -= chunk.length;
      if (_paused && _queuedBytes < 128 * 1024) {
        _paused = false;
        _stdout.resume();
        _stderr.resume();
      }
      return chunk;
    }
    return _streamsDone.isCompleted || _closed ? Uint8List(0) : null;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    if (_closed || !_acceptWrites) return;
    _process.stdin.add(bytes);
    await _process.stdin.flush();
  }

  @override
  void stopWriting() {
    _acceptWrites = false;
  }

  @override
  int? pollExit() => _exitCode;

  @override
  void resize(int rows, int columns) {
    if (_terminalFd < 0 || _rawExitCode != null) return;
    using((arena) {
      final size = arena<Uint16>(4);
      size[0] = rows;
      size[1] = columns;
      size[2] = 0;
      size[3] = 0;
      if (_ioctl(
            _terminalFd,
            Platform.isMacOS ? 0x80087467 : 0x5414,
            size.cast(),
          ) <
          0) {
        throw ProcessException(
          'ioctl(TIOCSWINSZ)',
          const [],
          'Cannot resize child terminal',
          _errno().value,
        );
      }
    });
  }

  /// Enumerate the private terminal's members before signaling its owner. This
  /// includes foreground/background job groups created by interactive shells.
  /// The ps query is asynchronous, so cleanup never blocks the UI isolate.
  Future<void> _signalMembers(
    ProcessSignal signal, {
    bool wholeSession = false,
  }) async {
    final tty = _tty;
    final session = _sessionId;
    if (tty == null || session == null) return;
    final name = tty.substring('/dev/'.length);
    final listing = await Process.run('/bin/ps', [
      if (wholeSession) '-e' else ...['-t', name],
      '-o',
      'pid=',
    ]);
    _members.removeWhere((member) => _session(member) != session);
    if (listing.exitCode == 0) {
      for (final member
          in (listing.stdout as String)
              .split(RegExp(r'\s+'))
              .map(int.tryParse)
              .whereType<int>()) {
        if (_session(member) == session) _members.add(member);
      }
    }
    // Members can lose their controlling-terminal association when script
    // exits. Retain the pre-signal snapshot until immediate shutdown completes,
    // checking session membership before each signal to avoid reused PIDs.
    for (final member in _members.toList().reversed) {
      if (_session(member) == session) Process.killPid(member, signal);
    }
  }

  @override
  bool kill(ProcessSignal signal) {
    if (_closed || _rawExitCode != null) return false;
    if (_signaling) {
      if (signal != ProcessSignal.sigkill) return false;
      _escalation = signal;
      return true;
    }
    _signaling = true;
    _signals = _sendSignal(signal);
    return true;
  }

  Future<void> _sendSignal(ProcessSignal signal) async {
    try {
      while (_rawExitCode == null) {
        await _signalMembers(signal);
        if (_rawExitCode == null) _process.kill(signal);
        final next = _escalation;
        _escalation = null;
        if (next == null) break;
        signal = next;
      }
    } catch (error) {
      _error = error;
      if (_rawExitCode == null) _process.kill(signal);
    } finally {
      _signaling = false;
      _escalation = null;
    }
  }

  @override
  Future<void> finish() => _finishing ??= _finish();

  Future<void> _finish() async {
    await _startupDone.future;
    try {
      await _signals;
      // Natural exit can remove controlling-terminal associations before this
      // callback. Session identity still identifies the remaining jobs.
      await _signalMembers(ProcessSignal.sigkill, wholeSession: true);
    } catch (error) {
      _error = error;
    } finally {
      if (_terminalFd >= 0) {
        _close(_terminalFd);
        _terminalFd = -1;
      }
      _sessionId = null;
      _members.clear();
      try {
        if (await _directory.exists()) await _directory.delete(recursive: true);
      } catch (error) {
        _error = error;
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await finish();
    _closed = true;
    await _stdout.cancel();
    await _stderr.cancel();
    _chunks.clear();
    // Ignore broken-pipe completion when disposal interrupts pending input.
    unawaited(_process.stdin.close().catchError((Object _) {}));
  }
}
