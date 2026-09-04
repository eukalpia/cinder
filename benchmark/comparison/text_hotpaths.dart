import 'package:cinder/cinder.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';
import 'package:cinder/src/text/text_layout_engine.dart' as text;
import 'package:cinder/src/rendering/frame_diff.dart';
import 'package:cinder/src/components/render_paragraph.dart';

int sink = 0;

void bench(String name, void Function() body, {int iterations = 200}) {
  for (var i = 0; i < 50; i++) {
    body();
  }
  final samples = <double>[];
  for (var s = 0; s < 7; s++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      body();
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds / iterations);
  }
  samples.sort();
  print(
    '$name: median=${samples[3].toStringAsFixed(3)}us range=${samples.first.toStringAsFixed(3)}..${samples.last.toStringAsFixed(3)}',
  );
}

void main() {
  for (final count in [200, 2000]) {
    final content = List.filled(
      count,
      'log event status=200 latency=3.5ms request finished',
    ).join('\n');
    bench('layout ASCII $count lines maxLines=3', () {
      final result = text.TextLayoutEngine.layout(
        content,
        const text.TextLayoutConfig(maxWidth: 80, maxLines: 3),
      );
      sink += result.actualWidth;
    }, iterations: 50);
  }
  for (final count in [20, 200]) {
    final content = List.filled(
      count,
      'log event status=200 latency=3.5ms request finished',
    ).join('\n');
    final paragraph = RenderParagraph(text: TextSpan(text: content));
    final constraint = BoxConstraints.tight(Size(80, count.toDouble()));
    paragraph.layout(constraint);
    final buffer = Buffer(80, count);
    final canvas = TerminalCanvas(
      buffer,
      Rect.fromLTWH(0, 0, 80, count.toDouble()),
    );
    bench('paragraph layout $count lines', () {
      paragraph.markNeedsLayout();
      paragraph.layout(constraint);
      sink += paragraph.size.width.toInt();
    }, iterations: 50);
    bench('paragraph paint $count lines no selection', () {
      paragraph.paintWithContext(canvas, Offset.zero);
      sink += buffer.getCell(0, 0).char.length;
    }, iterations: 50);
    paragraph.setSelectionRange(2, 10);
    bench('paragraph paint $count lines 8-char selection', () {
      paragraph.paintWithContext(canvas, Offset.zero);
      sink += buffer.getCell(0, 0).char.length;
    }, iterations: 50);
  }
  for (final styled in [false, true]) {
    final previous = Buffer(200, 60);
    final current = Buffer(200, 60);
    current.fillArea(
      const Rect.fromLTWH(0, 0, 200, 60),
      'X',
      style: styled
          ? const TextStyle(color: Colors.red, backgroundColor: Colors.black)
          : null,
    );
    bench('full frame diff 200x60 styled=$styled', () {
      final stats = emitFrameDiff(
        current: current,
        previous: previous,
        emitRun: (x, y, value) {
          sink += value.length;
        },
      );
      sink += stats.comparedCells;
    });
  }
  print('sink=$sink');
}
