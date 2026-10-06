import 'dart:async';

import 'package:cinder/src/size.dart';

/// Optional flow control for backends with asynchronous output.
///
/// The binding waits for this future before producing another frame, coalescing
/// intervening state changes. Completion means the underlying consumer accepted
/// the bytes; it does not guarantee pixels have appeared on a physical display.
/// Existing synchronous or embedded backends need not implement this capability.
abstract interface class TerminalOutputDrain {
  Future<void> drainOutput();
}

/// Optional capability for backends that receive mandatory termination
/// requests, such as `SIGTERM` on POSIX.
///
/// Unlike [TerminalBackend.shutdownStream], these requests are never routed
/// through the widget tree and cannot be cancelled: the binding restores the
/// terminal and exits. A backend should retain a request that arrives before
/// the binding listens and deliver it to the first listener.
abstract interface class TerminalTerminationSource {
  Stream<void> get terminationStream;
}

/// Abstract interface for terminal I/O backends.
///
/// Backends handle platform-specific I/O operations:
/// - StdioBackend: Native terminal via stdin/stdout
/// - SocketBackend: Shell mode via Unix socket
/// - WebBackend: Browser via static bridge for WASM/JS apps
abstract class TerminalBackend {
  /// Write a string directly to the output (immediate, unbuffered).
  void writeRaw(String data);

  /// Get the current terminal size.
  Size getSize();

  /// Whether this backend supports querying terminal size.
  bool get supportsSize;

  /// Get the input stream for reading terminal input.
  /// Returns null if this backend doesn't provide input.
  Stream<List<int>>? get inputStream;

  /// Stream of terminal resize events.
  /// Returns null if this backend doesn't support resize detection.
  Stream<Size>? get resizeStream;

  /// Stream of interrupt requests that the application may cancel
  /// (e.g., SIGINT on native, a host shutdown request on web).
  ///
  /// The binding first delivers each request to the widget tree as `Ctrl+C`
  /// and then consults exit request handlers; see
  /// `TerminalBinding.addExitRequestHandler`. Requests that must not be
  /// cancelled belong on [TerminalTerminationSource.terminationStream].
  /// Returns null if not supported.
  Stream<void>? get shutdownStream;

  /// Enable raw input mode (disable echo, line buffering).
  void enableRawMode();

  /// Disable raw input mode (restore echo, line buffering).
  void disableRawMode();

  /// Whether this backend is currently available/connected.
  bool get isAvailable;

  /// Request process/app exit with the given exit code.
  /// On native: calls dart:io exit()
  /// On web: typically a no-op (can't exit browser tab)
  void requestExit([int exitCode = 0]);

  /// Update the size externally (for backends that receive size via protocol).
  /// Default implementation does nothing.
  void notifySizeChanged(Size newSize) {}

  /// Dispose of any resources held by this backend.
  void dispose();
}
