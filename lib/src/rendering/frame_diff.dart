import '../buffer.dart';
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
        final nextCell = current.getCell(scan, y);
        final oldCell = previous.getCell(scan, y);
        if (nextCell.isImagePlaceholder || oldCell.isImagePlaceholder) {
          break;
        }
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
