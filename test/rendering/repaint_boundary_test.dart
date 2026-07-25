import 'package:cinder/cinder.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';
import 'package:test/test.dart';

class _CountingRenderBox extends RenderObject {
  int paints = 0;

  @override
  void performLayout() => size = constraints.constrain(const Size(4, 1));

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    paints++;
    canvas.drawText(offset, 'test');
    super.paint(canvas, offset);
  }
}

void main() {
  test('RepaintBoundary reuses its cached layer', () {
    final owner = PipelineOwner();
    final child = _CountingRenderBox();
    final boundary = RenderRepaintBoundary()..child = child;
    boundary.attach(owner);
    boundary.layout(BoxConstraints.tight(Size(4, 1)));

    final target = Buffer(8, 2);
    final canvas = TerminalCanvas(target, const Rect.fromLTWH(0, 0, 8, 2));
    boundary.paintWithContext(canvas, Offset.zero);
    boundary.paintWithContext(canvas, const Offset(2, 1));

    expect(child.paints, 1);
    expect(boundary.paintCount, 1);
    expect(boundary.cacheHits, 1);
    expect(target.getCell(2, 1).char, 't');
  });

  test('paint invalidation stops at nearest RepaintBoundary', () {
    final owner = PipelineOwner();
    var visualUpdates = 0;
    owner.onNeedsVisualUpdate = () => visualUpdates++;
    final child = _CountingRenderBox();
    final boundary = RenderRepaintBoundary()..child = child;
    boundary.attach(owner);
    boundary.layout(BoxConstraints.tight(Size(4, 1)));
    owner.takeNodesNeedingPaint();

    child.markNeedsPaint();
    final dirty = owner.takeNodesNeedingPaint();
    expect(dirty, contains(boundary));
    expect(visualUpdates, greaterThan(0));
  });
}
