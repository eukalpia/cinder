import '../keyboard/keyboard_event.dart';
import '../keyboard/logical_key.dart';

/// Environment variable that enables (`1`) or disables (`0`) the local log
/// server read by `cinder logs`.
const String logServerEnvironmentVariable = 'CINDER_LOG_SERVER';

/// Environment variable that enables (`1`) or disables (`0`) the debug overlay
/// and its `Ctrl+G` shortcut.
const String debugOverlayEnvironmentVariable = 'CINDER_DEBUG_OVERLAY';

/// Whether Dart assertions are enabled in this isolate.
///
/// Assertions are enabled by `dart run --enable-asserts`, `dart test`, and IDE
/// debug sessions. They are disabled in `dart compile exe` executables and in
/// plain `dart run`, so development tools default to off for end users.
bool get assertionsEnabled {
  var enabled = false;
  assert(enabled = true);
  return enabled;
}

/// Resolves whether an opt-in development feature is active.
///
/// An [explicit] application choice wins. Otherwise a recognized
/// [environmentValue] (`1`/`true`/`yes`/`on` or `0`/`false`/`no`/`off`/empty)
/// decides, and unrecognized or absent values fall back to [debugDefault].
bool resolveDevelopmentFeature({
  bool? explicit,
  String? environmentValue,
  required bool debugDefault,
}) {
  if (explicit != null) return explicit;
  final value = environmentValue?.trim().toLowerCase();
  if (value != null) {
    if (const {'1', 'true', 'yes', 'on'}.contains(value)) return true;
    if (const {'', '0', 'false', 'no', 'off'}.contains(value)) return false;
  }
  return debugDefault;
}

/// Whether [event] is the debug overlay shortcut, `Ctrl+G`.
bool isDebugOverlayShortcut(KeyboardEvent event) =>
    event.logicalKey == LogicalKey.keyG && event.isControlPressed;
