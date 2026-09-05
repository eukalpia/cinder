import 'dart:async';
import 'dart:io';

import 'package:cinder/src/size.dart';

import 'terminal_backend.dart';
import 'sink_output.dart';
import 'win32_ansi_stdin.dart';

/// Backend for native terminal I/O via stdin/stdout.
/// Handles Unix signals (SIGWINCH, SIGINT, SIGTERM) for resize and shutdown.
/// On Windows, uses polling for resize detection, SIGINT for Ctrl+C,
/// and Win32AnsiStdin for proper keyboard input (arrow keys, etc.).
class StdioBackend implements TerminalBackend, TerminalOutputDrain {
  final SinkOutput _output = SinkOutput(stdout.nonBlocking);
  StreamController<Size>? _resizeController;
  StreamController<void>? _shutdownController;
  StreamSubscription? _sigwinchSubscription;
  StreamSubscription? _sigintSubscription;
  StreamSubscription? _sigtermSubscription;
  Timer? _windowsResizeTimer;
  Size? _lastKnownSize;
  bool _disposed = false;
  Win32AnsiStdin? _win32Stdin;
  bool? _originalEchoMode;
  bool? _originalLineMode;

  StdioBackend() {
    _initializeSignalHandling();
  }

  void _initializeSignalHandling() {
    _resizeController = StreamController<Size>.broadcast();
    _shutdownController = StreamController<void>.broadcast();

    if (Platform.isWindows) {
      // Windows: Use Win32AnsiStdin for proper keyboard input
      _win32Stdin = Win32AnsiStdin();

      // Windows: Use polling for resize detection since SIGWINCH is not available
      _lastKnownSize = getSize();
      _windowsResizeTimer = Timer.periodic(const Duration(milliseconds: 250), (
        _,
      ) {
        if (!_disposed && stdout.hasTerminal) {
          final currentSize = getSize();
          if (_lastKnownSize != currentSize) {
            _lastKnownSize = currentSize;
            _resizeController?.add(currentSize);
          }
        }
      });

      // Windows: SIGINT works for Ctrl+C
      try {
        _sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
          if (!_disposed) {
            _shutdownController?.add(null);
          }
        });
      } catch (e) {
        // SIGINT may not be available in all Windows environments
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      // Unix: Use signals
      _sigwinchSubscription = ProcessSignal.sigwinch.watch().listen((_) {
        if (!_disposed && stdout.hasTerminal) {
          final size = Size(
            stdout.terminalColumns.toDouble(),
            stdout.terminalLines.toDouble(),
          );
          _resizeController?.add(size);
        }
      });

      _sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
        if (!_disposed) {
          _shutdownController?.add(null);
        }
      });
      _sigtermSubscription = ProcessSignal.sigterm.watch().listen((_) {
        if (!_disposed) {
          _shutdownController?.add(null);
        }
      });
    }
  }

  @override
  void writeRaw(String data) {
    if (!_disposed) _output.write(data);
  }

  @override
  Future<void> drainOutput() => _output.drain();

  @override
  Size getSize() {
    if (stdout.hasTerminal) {
      return Size(
        stdout.terminalColumns.toDouble(),
        stdout.terminalLines.toDouble(),
      );
    }
    return const Size(80, 24);
  }

  @override
  bool get supportsSize => stdout.hasTerminal;

  @override
  Stream<List<int>>? get inputStream {
    // On Windows, use Win32AnsiStdin for proper keyboard input
    if (Platform.isWindows && _win32Stdin != null) {
      return _win32Stdin;
    }
    return stdin;
  }

  @override
  Stream<Size>? get resizeStream => _resizeController?.stream;

  @override
  Stream<void>? get shutdownStream => _shutdownController?.stream;

  @override
  void enableRawMode() {
    try {
      if (_originalEchoMode == null && stdin.hasTerminal) {
        _originalEchoMode = stdin.echoMode;
        _originalLineMode = stdin.lineMode;
        stdin.echoMode = false;
        stdin.lineMode = false;
      }
    } catch (e) {
      // Ignore errors in CI/CD or when piping
    }
  }

  @override
  void disableRawMode() {
    // Restore the caller's original modes, including terminals that already
    // had echo or line buffering disabled before Cinder started.
    final echoMode = _originalEchoMode;
    final lineMode = _originalLineMode;
    _originalEchoMode = null;
    _originalLineMode = null;
    try {
      if (echoMode != null) stdin.echoMode = echoMode;
    } catch (e) {
      // Continue restoring line mode if echo restoration fails.
    }
    try {
      if (lineMode != null) stdin.lineMode = lineMode;
    } catch (e) {
      // The terminal may have been disconnected during shutdown.
    }
  }

  @override
  bool get isAvailable => !_disposed;

  @override
  void notifySizeChanged(Size newSize) {
    // StdioBackend doesn't track size via protocol, so this is a no-op.
    // Size changes are detected via SIGWINCH signal (Unix) or polling (Windows).
  }

  @override
  void requestExit([int exitCode = 0]) {
    // Flush stdout before exiting to ensure all terminal cleanup escape
    // sequences (disable mouse tracking, leave alternate screen, show cursor,
    // etc.) are actually written to the terminal. Without this, macOS terminals
    // can be left in a bad state (e.g., echo mode off, stuck in alt screen).
    Future.wait<void>([_output.drain(), stdout.flush(), stderr.flush()])
        .timeout(const Duration(seconds: 1))
        .then((_) => exit(exitCode))
        .catchError((_) => exit(exitCode));
  }

  @override
  void dispose() {
    _disposed = true;
    _windowsResizeTimer?.cancel();
    _sigwinchSubscription?.cancel();
    _sigintSubscription?.cancel();
    _sigtermSubscription?.cancel();
    _resizeController?.close();
    _shutdownController?.close();
    _win32Stdin?.close();
  }
}
