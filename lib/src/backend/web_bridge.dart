import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// JavaScript bridge object for cinder host-guest communication.
/// This is stored on `window.cinderBridge` and shared between
/// separately compiled Dart applications.
@JS()
@staticInterop
class CinderBridge {}

/// Create a new empty JS object that can be used as a CinderBridge.
CinderBridge createCinderBridge() {
  // Create a plain JS object: {}
  return _createEmptyObject() as CinderBridge;
}

/// Helper to create an empty JS object via JS interop.
@JS('Object')
external JSFunction get _objectConstructor;

JSObject _createEmptyObject() {
  return _objectConstructor.callAsConstructor<JSObject>();
}

/// Extension to add properties to CinderBridge.
extension CinderBridgeExtension on CinderBridge {
  // ─────────────────────────────────────────────────────────────────
  // Guest → Host: Output from the cinder app
  // ─────────────────────────────────────────────────────────────────

  /// Callback for output data from guest app.
  /// Host sets this, guest calls it via writeOutput().
  external JSFunction? get onOutput;
  external set onOutput(JSFunction? value);

  // ─────────────────────────────────────────────────────────────────
  // Host → Guest: Input, resize, shutdown
  // ─────────────────────────────────────────────────────────────────

  /// Callback for keyboard/mouse input.
  /// Guest sets this, host calls it via sendInput().
  external JSFunction? get onInput;
  external set onInput(JSFunction? value);

  /// Callback for terminal resize.
  /// Guest sets this, host calls it via setSize().
  external JSFunction? get onResize;
  external set onResize(JSFunction? value);

  /// Callback for shutdown signal.
  /// Guest sets this, host calls it via requestShutdown().
  external JSFunction? get onShutdown;
  external set onShutdown(JSFunction? value);

  // ─────────────────────────────────────────────────────────────────
  // Synchronous size data (host writes, guest reads)
  // ─────────────────────────────────────────────────────────────────

  /// Current terminal width in columns.
  external JSNumber? get width;
  external set width(JSNumber? value);

  /// Current terminal height in rows.
  external JSNumber? get height;
  external set height(JSNumber? value);
}

/// Global accessor for the bridge object.
@JS('cinderBridge')
external CinderBridge? get cinderBridge;

/// Global setter for the bridge object.
@JS('cinderBridge')
external set cinderBridge(CinderBridge? value);

/// Check if the bridge has been initialized (by host).
bool get isBridgeInitialized => cinderBridge != null;
