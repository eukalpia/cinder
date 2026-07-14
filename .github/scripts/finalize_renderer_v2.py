#!/usr/bin/env python3
from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    if old not in text:
        if new in text:
            return
        raise RuntimeError(f'Expected fragment not found in {path}:\n{old[:500]}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def write_frame_diff() -> None:
    path = ROOT / 'lib/src/rendering/frame_diff.dart'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(r'''import '../buffer.dart';
import '../style.dart';

/// Receives one cursor-positioned terminal output run.
typedef TerminalRunEmitter = void Function(int x, int y, String output);

/// Deterministic statistics for one differential-rendering pass.
final class FrameDiffStats {
  const FrameDiffStats({
    required this.comparedCells,
    required this.ansiRuns,
    required this.writtenCells,
    required this.outputCodeUnits,
  });

  final int comparedCells;
  final int ansiRuns;
  final int writtenCells;
  final int outputCodeUnits;
}

/// Compares dirty row spans and emits cost-aware ANSI runs.
///
/// A small unchanged gap is included in the surrounding run when rewriting the
/// cells is cheaper than another cursor-positioning sequence. Wide graphemes,
/// style transitions, removals, and image placeholders remain correct.
FrameDiffStats emitFrameDiff({
  required Buffer current,
  required Buffer previous,
  required TerminalRunEmitter emitRun,
  int maxUnchangedGap = 4,
}) {
  if (current.width != previous.width || current.height != previous.height) {
    throw ArgumentError('Frame buffers must have identical dimensions.');
  }
  if (maxUnchangedGap < 0) {
    throw ArgumentError.value(
      maxUnchangedGap,
      'maxUnchangedGap',
      'must be non-negative',
    );
  }

  var comparedCells = 0;
  var ansiRuns = 0;
  var writtenCells = 0;
  var outputCodeUnits = 0;

  bool isVisibleChange(int x, int y) {
    comparedCells++;
    final next = current.getCell(x, y);
    final old = previous.getCell(x, y);
    if (next.matches(old)) return false;

    // The leading wide grapheme paints this continuation cell. The reverse
    // transition (old continuation -> current blank) is intentionally visible
    // so a removed wide grapheme clears its trailing terminal column.
    if (next.char == '\u200B') return false;
    return true;
  }

  for (var y = 0; y < current.height; y++) {
    final currentDirty = current.isRowDirty(y);
    final previousDirty = previous.isRowDirty(y);
    if (!currentDirty && !previousDirty) continue;

    final start = currentDirty && previousDirty
        ? _min(current.dirtyStartForRow(y), previous.dirtyStartForRow(y))
        : currentDirty
            ? current.dirtyStartForRow(y)
            : previous.dirtyStartForRow(y);
    final end = currentDirty && previousDirty
        ? _max(current.dirtyEndForRow(y), previous.dirtyEndForRow(y))
        : currentDirty
            ? current.dirtyEndForRow(y)
            : previous.dirtyEndForRow(y);

    var scan = start;
    while (scan <= end) {
      while (scan <= end && !isVisibleChange(scan, y)) {
        scan++;
      }
      if (scan > end) break;

      final runStart = scan;
      var runEnd = scan;
      var unchangedGap = 0;
      scan++;

      while (scan <= end) {
        if (isVisibleChange(scan, y)) {
          runEnd = scan;
          unchangedGap = 0;
        } else {
          unchangedGap++;
          if (unchangedGap > maxUnchangedGap) break;
        }
        scan++;
      }

      final encoded = _encodeRun(current, y, runStart, runEnd);
      emitRun(runStart, y, encoded.output);
      ansiRuns++;
      writtenCells += encoded.writtenCells;
      outputCodeUnits += encoded.output.length;
    }
  }

  return FrameDiffStats(
    comparedCells: comparedCells,
    ansiRuns: ansiRuns,
    writtenCells: writtenCells,
    outputCodeUnits: outputCodeUnits,
  );
}

({String output, int writtenCells}) _encodeRun(
  Buffer buffer,
  int y,
  int start,
  int end,
) {
  final output = StringBuffer();
  TextStyle? activeStyle;
  var writtenCells = 0;
  var x = start;

  while (x <= end) {
    final cell = buffer.getCell(x, y);
    if (cell.char == '\u200B') {
      x++;
      continue;
    }

    final style = cell.isImagePlaceholder ? const TextStyle() : cell.style;
    final hasStyle = _hasVisibleStyle(style);
    if (hasStyle) {
      if (activeStyle != style) {
        if (activeStyle != null) output.write(TextStyle.reset);
        output.write(style.toAnsi());
        activeStyle = style;
      }
    } else if (activeStyle != null) {
      output.write(TextStyle.reset);
      activeStyle = null;
    }

    if (cell.isImagePlaceholder) {
      output.write(' ');
      writtenCells++;
      x++;
      continue;
    }

    output.write(cell.char);
    final width = cell.width > 1 ? cell.width : 1;
    writtenCells += width;
    x += width;
  }

  if (activeStyle != null) output.write(TextStyle.reset);
  return (output: output.toString(), writtenCells: writtenCells);
}

bool _hasVisibleStyle(TextStyle style) {
  return style.color != null ||
      style.backgroundColor != null ||
      style.fontWeight == FontWeight.bold ||
      style.fontWeight == FontWeight.dim ||
      style.fontStyle == FontStyle.italic ||
      style.decoration?.hasUnderline == true ||
      style.reverse;
}

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;
''', encoding='utf-8')


def patch_escape_codes() -> None:
    path = ROOT / 'lib/src/utils/escape_codes.dart'
    replace_once(
        path,
        "  static const mainBuffer = '\\x1b[?1049l';\n",
        "  static const mainBuffer = '\\x1b[?1049l';\n"
        "\n"
        "  /// Begin a synchronized terminal update (DEC private mode 2026).\n"
        "  static const beginSynchronizedOutput = '\\x1b[?2026h';\n"
        "\n"
        "  /// End a synchronized terminal update. Unsupported terminals ignore it.\n"
        "  static const endSynchronizedOutput = '\\x1b[?2026l';\n",
    )


def patch_terminal_binding() -> None:
    path = ROOT / 'lib/src/binding/terminal_binding.dart'
    replace_once(
        path,
        "import '../rendering/mouse_hit_test.dart';\n",
        "import '../rendering/frame_diff.dart';\n"
        "import '../rendering/mouse_hit_test.dart';\n",
    )
    replace_once(
        path,
        "  int _lastComparedCells = 0;\n"
        "  int _lastAnsiRuns = 0;\n"
        "\n"
        "  /// Number of cells compared by the most recent differential frame.\n"
        "  int get lastComparedCells => _lastComparedCells;\n"
        "\n"
        "  /// Number of cursor-positioned ANSI runs emitted by the most recent frame.\n"
        "  int get lastAnsiRuns => _lastAnsiRuns;\n",
        "  int _lastComparedCells = 0;\n"
        "  int _lastAnsiRuns = 0;\n"
        "  int _lastWrittenCells = 0;\n"
        "  int _lastOutputCodeUnits = 0;\n"
        "\n"
        "  /// Number of cells compared by the most recent differential frame.\n"
        "  int get lastComparedCells => _lastComparedCells;\n"
        "\n"
        "  /// Number of cursor-positioned ANSI runs emitted by the most recent frame.\n"
        "  int get lastAnsiRuns => _lastAnsiRuns;\n"
        "\n"
        "  /// Number of terminal cells rewritten by the most recent frame.\n"
        "  int get lastWrittenCells => _lastWrittenCells;\n"
        "\n"
        "  /// Number of UTF-16 code units emitted, including ANSI style sequences.\n"
        "  int get lastOutputCodeUnits => _lastOutputCodeUnits;\n",
    )

    text = path.read_text(encoding='utf-8')
    start = text.index('  /// Dirty-span differential renderer.\n')
    end = text.index('  /// Full redraw (used for first frame or after resize).', start)
    replacement = '''  /// Dirty-span differential renderer with cost-aware row batching.\n  void _renderFullDiff(buf.Buffer buffer, buf.Buffer previous) {\n    final stats = emitFrameDiff(\n      current: buffer,\n      previous: previous,\n      emitRun: (x, y, output) {\n        terminal.moveCursor(x, y);\n        terminal.write(output);\n      },\n    );\n    _lastComparedCells = stats.comparedCells;\n    _lastAnsiRuns = stats.ansiRuns;\n    _lastWrittenCells = stats.writtenCells;\n    _lastOutputCodeUnits = stats.outputCodeUnits;\n\n    _renderPendingImages(buffer);\n  }\n\n'''
    text = text[:start] + replacement + text[end:]
    path.write_text(text, encoding='utf-8')

    replace_once(
        path,
        "    // Render to terminal using differential rendering (buffer diff)\n"
        "    _renderDifferential(buffer);\n"
        "\n"
        "    // After rendering, position the terminal cursor at the focused text\n"
        "    // field's cursor location. This stabilises the IME composition window\n"
        "    // (e.g. Chinese Pinyin) so it doesn't flicker across the screen.\n"
        "    _positionImeCursor();\n"
        "    terminal.flush();\n",
        "    // DEC synchronized output makes the terminal present the complete frame\n"
        "    // atomically. Unsupported terminals safely ignore private mode 2026.\n"
        "    terminal.write(EscapeCodes.beginSynchronizedOutput);\n"
        "    try {\n"
        "      _renderDifferential(buffer);\n"
        "\n"
        "      // Keep IME composition anchored after all cursor-moving diff runs.\n"
        "      _positionImeCursor();\n"
        "    } finally {\n"
        "      terminal.write(EscapeCodes.endSynchronizedOutput);\n"
        "      terminal.flush();\n"
        "    }\n",
    )


def write_tests() -> None:
    rendering = ROOT / 'test/rendering'
    rendering.mkdir(parents=True, exist_ok=True)

    (rendering / 'buffer_v2_test.dart').write_text(r'''import 'package:cinder/src/buffer.dart';
import 'package:test/test.dart';

void main() {
  group('Buffer V2', () {
    test('reuses cell identity across writes and clears', () {
      final buffer = Buffer(8, 3);
      final original = buffer.getCell(2, 1);

      buffer.writeCell(2, 1, char: 'X');
      expect(identical(original, buffer.getCell(2, 1)), isTrue);
      expect(buffer.getCell(2, 1).char, 'X');

      buffer.clear();
      expect(identical(original, buffer.getCell(2, 1)), isTrue);
      expect(buffer.getCell(2, 1).char, ' ');
      expect(buffer.isRowDirty(1), isFalse);
    });

    test('tracks the minimal touched span per row', () {
      final buffer = Buffer(20, 4)
        ..writeCell(7, 2, char: 'A')
        ..writeCell(11, 2, char: 'B');

      expect(buffer.dirtyStartForRow(2), 7);
      expect(buffer.dirtyEndForRow(2), 11);
      expect(buffer.dirtyCellUpperBound, 5);
      expect(buffer.isRowDirty(0), isFalse);
    });

    test('wide graphemes reserve and clear their continuation cell', () {
      final buffer = Buffer(8, 1)..setString(0, 0, '界');

      expect(buffer.getCell(0, 0).char, '界');
      expect(buffer.getCell(0, 0).width, 2);
      expect(buffer.getCell(1, 0).char, '\u200B');

      buffer.clear();
      expect(buffer.getCell(0, 0).char, ' ');
      expect(buffer.getCell(1, 0).char, ' ');
    });

    test('clips dirty rectangles to the viewport', () {
      final buffer = Buffer(10, 3)..markDirtyRect(-5, 1, 30, 3);

      expect(buffer.dirtyStartForRow(1), 0);
      expect(buffer.dirtyEndForRow(1), 9);
      expect(buffer.dirtyStartForRow(2), 0);
      expect(buffer.dirtyEndForRow(2), 9);
      expect(buffer.isRowDirty(0), isFalse);
    });
  });
}
''', encoding='utf-8')

    (rendering / 'frame_diff_test.dart').write_text(r'''import 'package:cinder/src/buffer.dart';
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
    return other is _Run && x == other.x && y == other.y && output == other.output;
  }

  @override
  int get hashCode => Object.hash(x, y, output);

  @override
  String toString() => '_Run($x, $y, $output)';
}
''', encoding='utf-8')


def write_benchmark() -> None:
    path = ROOT / 'benchmark/renderer_v2_benchmark.dart'
    path.write_text(r'''import 'package:cinder/src/buffer.dart';
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
    emitRun: (_x, _y, _output) {},
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
      emitRun: (_x, _y, _output) {},
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
''', encoding='utf-8')


def write_ci() -> None:
    path = ROOT / '.github/workflows/ci.yml'
    path.write_text(r'''name: CI

on:
  push:
    branches: [dev, test, main]
  pull_request:
    branches: [dev, test, main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  root:
    name: Root package
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable
      - name: Install dependencies
        run: dart pub get
      - name: Check formatting of changed Dart files
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before }}
        run: |
          base="$BASE_SHA"
          if [ -z "$base" ] || [ "$base" = "0000000000000000000000000000000000000000" ]; then
            base="$(git rev-parse HEAD^ 2>/dev/null || git rev-list --max-parents=0 HEAD)"
          fi
          mapfile -t files < <(git diff --name-only --diff-filter=ACMR "$base" HEAD | grep -E '^(lib|test|example|benchmark)/.*\.dart$' || true)
          if [ "${#files[@]}" -gt 0 ]; then
            dart format --output=none --set-exit-if-changed "${files[@]}"
          else
            echo "No changed root Dart files."
          fi
      - name: Analyze
        run: dart analyze --fatal-infos
      - name: Test
        run: dart test --reporter expanded

  packages:
    name: ${{ matrix.package }}
    runs-on: ubuntu-latest
    timeout-minutes: 20
    strategy:
      fail-fast: false
      matrix:
        package:
          - cinder_nested
          - cinder_provider
          - cinder_riverpod
          - cinder_bloc
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable
      - name: Install dependencies
        working-directory: packages/${{ matrix.package }}
        run: dart pub get
      - name: Check formatting of changed package files
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before }}
        run: |
          base="$BASE_SHA"
          if [ -z "$base" ] || [ "$base" = "0000000000000000000000000000000000000000" ]; then
            base="$(git rev-parse HEAD^ 2>/dev/null || git rev-list --max-parents=0 HEAD)"
          fi
          prefix="packages/${{ matrix.package }}/"
          mapfile -t files < <(git diff --name-only --diff-filter=ACMR "$base" HEAD | grep -E "^${prefix}.*\\.dart$" || true)
          if [ "${#files[@]}" -gt 0 ]; then
            dart format --output=none --set-exit-if-changed "${files[@]}"
          else
            echo "No changed Dart files in ${{ matrix.package }}."
          fi
      - name: Analyze
        working-directory: packages/${{ matrix.package }}
        run: dart analyze --fatal-infos
      - name: Test when present
        working-directory: packages/${{ matrix.package }}
        run: |
          if find test -name '*_test.dart' -print -quit 2>/dev/null | grep -q .; then
            dart test --reporter expanded
          else
            echo "No tests in ${{ matrix.package }}"
          fi
''', encoding='utf-8')

    renderer = ROOT / '.github/workflows/renderer_v2.yml'
    renderer.write_text(r'''name: Renderer V2

on:
  push:
    branches: [dev, test, main]
    paths:
      - 'lib/src/buffer.dart'
      - 'lib/src/rendering/frame_diff.dart'
      - 'lib/src/framework/terminal_canvas.dart'
      - 'lib/src/binding/terminal_binding.dart'
      - 'lib/src/utils/escape_codes.dart'
      - 'test/rendering/**'
      - 'benchmark/renderer_v2_benchmark.dart'
      - '.github/workflows/renderer_v2.yml'
  pull_request:
    branches: [dev, test, main]
    paths:
      - 'lib/src/buffer.dart'
      - 'lib/src/rendering/frame_diff.dart'
      - 'lib/src/framework/terminal_canvas.dart'
      - 'lib/src/binding/terminal_binding.dart'
      - 'lib/src/utils/escape_codes.dart'
      - 'test/rendering/**'
      - 'benchmark/renderer_v2_benchmark.dart'
      - '.github/workflows/renderer_v2.yml'

concurrency:
  group: renderer-v2-${{ github.ref }}
  cancel-in-progress: true

jobs:
  validate:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v6
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: stable
      - run: dart pub get
      - name: Analyze Renderer V2
        run: dart analyze lib/src/buffer.dart lib/src/rendering/frame_diff.dart lib/src/framework/terminal_canvas.dart lib/src/binding/terminal_binding.dart test/rendering benchmark/renderer_v2_benchmark.dart
      - name: Renderer correctness and contracts
        run: dart test test/rendering/buffer_v2_test.dart test/rendering/frame_diff_test.dart --reporter expanded
      - name: Renderer microbenchmark
        run: dart run benchmark/renderer_v2_benchmark.dart
''', encoding='utf-8')


def update_readme() -> None:
    path = ROOT / 'README.md'
    text = path.read_text(encoding='utf-8')
    text = text.replace(
        '| Renderer V2 dirty-region pipeline | Planned |',
        '| Renderer V2 reusable dirty-span pipeline | Available in `dev` |\n'
        '| Repaint boundaries and cached layers | Planned |',
    )
    old = '''The planned Renderer V2 will focus on:

- reusable flat front/back buffers;
- dirty-region painting;
- repaint boundaries and cached layers;
- row-span output diffs;
- terminal scroll-region optimization;
- synchronized output where supported.'''
    new = '''Renderer V2 now provides:

- reusable flat front/back buffers and stable cell identities;
- per-row dirty spans instead of unconditional full-screen comparison;
- cost-aware row batching for ANSI output;
- correct removal of wide graphemes and image-placeholder cleanup;
- synchronized terminal output using DEC private mode 2026;
- deterministic comparison/run metrics and regression benchmarks.

The next rendering phase adds repaint boundaries, cached layers, and terminal
scroll-region acceleration so static subtrees do not repaint during streaming
log updates.'''
    if old in text:
        text = text.replace(old, new, 1)
    text = text.replace('- [ ] Renderer V2', '- [x] Renderer V2 reusable dirty-span foundation')
    path.write_text(text, encoding='utf-8')


def cleanup_temporary_files() -> None:
    paths = [
        '.github/scripts/apply_renderer_v2.py',
        '.github/scripts/fix_focus_runtime.py',
        '.github/workflows/ci_diagnostic.yml',
        '.github/workflows/focus_runtime_fix.yml',
        '.github/workflows/renderer_v2_apply.yml',
        'tool/ci_trigger.txt',
    ]
    for relative in paths:
        path = ROOT / relative
        if path.exists():
            path.unlink()

    diagnostics = ROOT / 'ci_diagnostics'
    if diagnostics.exists():
        shutil.rmtree(diagnostics)


def main() -> None:
    write_frame_diff()
    patch_escape_codes()
    patch_terminal_binding()
    write_tests()
    write_benchmark()
    write_ci()
    update_readme()
    cleanup_temporary_files()
    print('Renderer V2 finalization applied.')


if __name__ == '__main__':
    main()
