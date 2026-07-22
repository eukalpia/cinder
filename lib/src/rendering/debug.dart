/// Debug flags for the Cinder rendering system.
library;

import '../style.dart';

const HSVColor _kDebugDefaultRepaintColor = HSVColor.fromAHSV(
  0.3,
  60.0,
  0.5,
  1.0,
);

/// Overlays a rotating set of colors when render objects repaint.
bool debugRepaintRainbowEnabled = false;

/// Enables additional diagnostics for repeated layout invalidation in a frame.
///
/// The flag is deliberately separate from repaint visualization so applications
/// can collect layout diagnostics without changing the rendered output.
bool debugDetectLayoutThrashing = false;

/// The current color overlaid on repainting render objects.
HSVColor debugCurrentRepaintColor = _kDebugDefaultRepaintColor;

/// Resets rendering diagnostics to their default state.
void debugResetRenderingDiagnostics() {
  debugRepaintRainbowEnabled = false;
  debugDetectLayoutThrashing = false;
  debugCurrentRepaintColor = _kDebugDefaultRepaintColor;
}

/// Backwards-compatible alias for older tests and integrations.
void debugResetRepaintRainbow() => debugResetRenderingDiagnostics();
