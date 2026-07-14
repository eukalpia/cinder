import 'package:cinder/src/buffer.dart';
import 'package:cinder/src/rendering/frame_diff.dart';
import 'package:cinder/src/style.dart';
import 'package:test/test.dart';

void main() {
  group('Renderer V2 frame diff', () {
    test('does no work when neither buffer has damage', () {
      final runs = <_Run>[];
      final stats = emitFrameDiff(
        current: Buffer(200, 60),
        previous: Buffer(200, 60),
        emitRun: (x, y, output) => runs.add(_Run(x, y, output)),
      );

      expect(stats.comparedCells, 0);
      expect(stats.ansiRuns, 0);
      expect(runs, isEmpty);
    });

    test('single-cell update compares and writes one cell', () {
      final previous = Buffer(200, 60)..writeCell(31, 12, char: 'A');
      final current = Buffer(200, 60)..writeCell(31, 12, char: 'B');
      final runs = <_Run>[];

      final stats = emitFrameDiff(
        current: current,
        previous: previous,
        emitRun: (x, y, output) => runs.add(_Run(x, y, output)),
      );

      expect(stats.comparedCells, 1);
      expect(stats.ansiRuns, 1);
      expect(stats.writtenCells, 1);
      expect(runs.single, const _Run(31, 12, 'B'));
    });

    test('removing content emits spaces from previous damage', () {
      final previous = Buffer(20, 2)..setString(4, 1, 'old');
      final current = Buffer(20, 2);
      final runs = <_Run>[];

      emitFrameDiff(
        current: current,
        previous: previous,
        emitRun: (x, y, output) => runs.add(_Run(x, y, output)),
      );

      expect(runs.single, const _Run(4, 1, '   '));
    });

    test('replacing a wide grapheme clears its trailing column', () {
      final previous = Buffer(10, 1)..setString(0, 0, '界');
      final current = Buffer(10, 1)..setString(0, 0, 'A');
      final runs = <_Run>[];

      final stats = emitFrameDiff(
        current: current,
        previous: previous,
        emitRun: (x, y, output) => runs.add(_Run(x, y, output)),
      );

      expect(runs.single, const _Run(0, 0, 'A '));
      expect(stats.writtenCells, 2);
    });

    test('clears old text before an image placeholder is rendered', () {
      final previous = Buffer(4, 1)..writeCell(0, 0, char: 'X');
      final current = Buffer(4, 1)..markImageRegion(0, 0, 1, 1, 'sixel');
      final runs = <_Run>[];

      emitFrameDiff(
        current: current,
        previous: previous,
        emitRun: (x, y, output) => runs.add(_Run(x, y, output)),
      );

      expect(runs.single, const _Run(0, 0, ' '));
    });

    test('groups adjacent style transitions into one ANSI run', () {
      final previous = Buffer(8, 1);
      final current = Buffer(8, 1)
        ..writeCell(
          1,
          0,
          char: 'A',
          style: const TextStyle(color: Colors.red),
        )
        ..writeCell(2, 0, char: 'B');
      final runs = <_Run>[];

      final stats = emitFrameDiff(
        current: current,
        previous: previous,
        emitRun: (x, y, output) => runs.add(_Run(x, y, output)),
      );

      expect(stats.ansiRuns, 1);
      expect(runs.single.x, 1);
      expect(runs.single.output, contains('A'));
      expect(runs.single.output, contains('B'));
      expect(runs.single.output, contains(TextStyle.reset));
    });

    test('merges short unchanged gaps but splits distant updates', () {
      final previous = Buffer(30, 1);
      final current = Buffer(30, 1)
        ..writeCell(1, 0, char: 'A')
        ..writeCell(4, 0, char: 'B')
        ..writeCell(20, 0, char: 'C');
      final runs = <_Run>[];

      final stats = emitFrameDiff(
        current: current,
        previous: previous,
        emitRun: (x, y, output) => runs.add(_Run(x, y, output)),
      );

      expect(stats.ansiRuns, 2);
      expect(runs[0].x, 1);
      expect(runs[0].output, 'A  B');
      expect(runs[1], const _Run(20, 0, 'C'));
    });
  });
}

final class _Run {
  const _Run(this.x, this.y, this.output);

  final int x;
  final int y;
  final String output;

  @override
  bool operator ==(Object other) {
    return other is _Run &&
        x == other.x &&
        y == other.y &&
        output == other.output;
  }

  @override
  int get hashCode => Object.hash(x, y, output);

  @override
  String toString() => '_Run($x, $y, $output)';
}
