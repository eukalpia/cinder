import 'package:cinder/src/buffer.dart';
import 'package:cinder/src/rendering/frame_diff.dart';

void main() {
  const width = 200;
  const height = 60;
  const iterations = 20000;

  final previous = Buffer(width, height)..writeCell(120, 30, char: 'A');
  final current = Buffer(width, height)..writeCell(120, 30, char: 'B');

  final warmup = emitFrameDiff(
    current: current,
    previous: previous,
    emitRun: (x, y, output) {
      if (x < 0 || y < 0 || output.isEmpty) {
        throw StateError('Invalid renderer run');
      }
    },
  );
  if (warmup.comparedCells != 1 || warmup.ansiRuns != 1) {
    throw StateError('Single-cell damage contract regressed: $warmup');
  }

  final stopwatch = Stopwatch()..start();
  var comparisons = 0;
  var runs = 0;
  for (var i = 0; i < iterations; i++) {
    final stats = emitFrameDiff(
      current: current,
      previous: previous,
      emitRun: (x, y, output) {
        if (x < 0 || y < 0 || output.isEmpty) {
          throw StateError('Invalid renderer run');
        }
      },
    );
    comparisons += stats.comparedCells;
    runs += stats.ansiRuns;
  }
  stopwatch.stop();

  final microsPerDiff = stopwatch.elapsedMicroseconds / iterations;
  print('Renderer V2 single-cell diff');
  print('viewport: ${width}x$height');
  print('iterations: $iterations');
  print('average: ${microsPerDiff.toStringAsFixed(3)} us');
  print('compared cells/frame: ${comparisons / iterations}');
  print('ANSI runs/frame: ${runs / iterations}');
}
