import 'package:cinder/cinder.dart';

import 'run_app_stub.dart'
    if (dart.library.io) 'run_app_io.dart'
    if (dart.library.html) 'run_app_web.dart';

/// Run a TUI application.
///
/// Automatically detects the platform:
/// - Native (Linux, macOS): Uses StdioBackend, checks for shell mode
/// - Web: Uses WebBackend with static bridge for WASM/JS apps
///
/// On native platforms, also checks for cinder shell mode for IDE debugging.
///
/// If [backend] is provided, it will be used instead of the default backend.
/// This is useful for custom I/O scenarios, such as:
/// - Writing to `/dev/tty` directly while redirecting stdout to `/dev/null`
/// - Custom terminal emulation
/// - Testing with mock backends
///
/// ## Development tools
///
/// Two development tools are off by default in release builds, so end users
/// cannot reach them:
///
/// - [enableDebugOverlay] wraps [app] in a [DebugOverlay] and makes `Ctrl+G`
///   toggle [debugMode]. While it is enabled, `Ctrl+G` never reaches the
///   application.
/// - [enableLogServer] starts the loopback log server that `cinder logs`
///   reads (native platforms only). Captured `print` output is otherwise
///   discarded. Connections require a random per-run token, published in a
///   file that only the current user can read.
///
/// When an argument is null, the `CINDER_DEBUG_OVERLAY` or
/// `CINDER_LOG_SERVER` environment variable decides (`1` enables, `0`
/// disables). Otherwise a tool is enabled only when Dart assertions are
/// enabled, as with `dart run --enable-asserts`, IDE debug sessions, and
/// `cinder run`.
Future<void> runApp(
  Widget app, {
  bool enableHotReload = true,
  TerminalBackend? backend,
  bool? enableDebugOverlay,
  bool? enableLogServer,
}) {
  return runAppImpl(
    app,
    enableHotReload: enableHotReload,
    backend: backend,
    enableDebugOverlay: enableDebugOverlay,
    enableLogServer: enableLogServer,
  );
}
