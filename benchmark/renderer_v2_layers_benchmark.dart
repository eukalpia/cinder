import 'package:cinder/cinder.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';

class _StaticPanel extends RenderObject {
  int paints = 0;
  @override
  void performLayout() => size = constraints.constrain(const Size(100, 30));
  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    paints++;
    canvas.fillRect(const Rect.fromLTWH(0, 0, 100, 30), 'x');
    super.paint(canvas, offset);
  }
}

void main() {
  final child = _StaticPanel();
  final boundary = RenderRepaintBoundary()..child = child;
  boundary.layout(BoxConstraints.tight(Size(100, 30)));
  final target = Buffer(200, 60);
  final canvas = TerminalCanvas(target, const Rect.fromLTWH(0, 0, 200, 60));

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < 1000; i++) {
    boundary.paintWithContext(canvas, Offset.zero);
  }
  stopwatch.stop();

  if (child.paints != 1 || boundary.cacheHits != 999) {
    throw StateError('cached layer contract failed');
  }
  print('1000 cached panel composites: ${stopwatch.elapsedMicroseconds} us');
}
