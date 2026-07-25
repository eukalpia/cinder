import 'package:cinder/cinder.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';

/// Isolates a subtree into a reusable terminal-cell layer.
///
/// Descendant paint invalidations stop at this render object. When the subtree
/// is unchanged, its cached cells are composited without repainting descendants.
class RepaintBoundary extends SingleChildRenderObjectWidget {
  const RepaintBoundary({super.key, super.child});

  @override
  RenderRepaintBoundary createRenderObject(BuildContext context) {
    return RenderRepaintBoundary();
  }
}

class RenderRepaintBoundary extends RenderObject
    with RenderObjectWithChildMixin<RenderObject> {
  Buffer? _layer;
  Offset? _lastPaintOffset;
  int _paintCount = 0;
  int _cacheHits = 0;

  @override
  bool get isRepaintBoundary => true;

  int get paintCount => _paintCount;
  int get cacheHits => _cacheHits;
  Offset? get lastPaintOffset => _lastPaintOffset;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) child.parentData = BoxParentData();
  }

  @override
  void performLayout() {
    final currentChild = child;
    if (currentChild == null) {
      size = constraints.constrain(Size.zero);
      return;
    }
    currentChild.layout(constraints, parentUsesSize: true);
    (currentChild.parentData as BoxParentData).offset = Offset.zero;
    size = constraints.constrain(currentChild.size);
  }

  Buffer _ensureLayer() {
    final width = size.width.ceil().clamp(0, 1 << 20);
    final height = size.height.ceil().clamp(0, 1 << 20);
    final existing = _layer;
    if (existing != null &&
        existing.width == width &&
        existing.height == height) {
      return existing;
    }
    return _layer = Buffer(width, height);
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    final currentChild = child;
    if (currentChild == null || size.width <= 0 || size.height <= 0) {
      super.paint(canvas, offset);
      return;
    }

    final layer = _ensureLayer();
    final repaintLayer =
        needsPaint || currentChild.needsPaint || _paintCount == 0;
    if (repaintLayer) {
      layer.clearAll();
      final layerCanvas = TerminalCanvas(
        layer,
        Rect.fromLTWH(0, 0, layer.width.toDouble(), layer.height.toDouble()),
      );
      currentChild.paintWithContext(layerCanvas, Offset.zero);
      _paintCount++;
    } else {
      _cacheHits++;
    }

    _lastPaintOffset = offset;
    canvas.drawBuffer(layer, offset);
    super.paint(canvas, offset);
  }

  @override
  bool hitTestChildren(HitTestResult result, {required Offset position}) {
    return child?.hitTest(result, position: position) ?? false;
  }

  @override
  void dispose() {
    _layer = null;
    super.dispose();
  }
}
