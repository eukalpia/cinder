#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CANVAS = ROOT / 'lib/src/framework/terminal_canvas.dart'
BINDING = ROOT / 'lib/src/binding/terminal_binding.dart'


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise RuntimeError(f'Expected fragment not found:\n{old[:300]}')
    return text.replace(old, new, 1)


def migrate_canvas() -> None:
    text = CANVAS.read_text(encoding='utf-8')

    replacements = [
        (
            """      _buffer.setCell(
        cellX,
        cellY,
        Cell(
          char: grapheme, // Use the full grapheme cluster, not individual runes
          style: finalStyle,
        ),
      );""",
            """      _buffer.writeCell(
        cellX,
        cellY,
        char: grapheme, // Use the full grapheme cluster, not individual runes
        style: finalStyle,
      );""",
        ),
        (
            """        _buffer.setCell(
          nextCellX,
          nextCellY,
          Cell(
            char: '\\u200B', // Zero-width space as a marker
            style: nextFinalStyle,
          ),
        );""",
            """        _buffer.writeCell(
          nextCellX,
          nextCellY,
          char: '\\u200B', // Zero-width space as a marker
          style: nextFinalStyle,
        );""",
        ),
        (
            """        _buffer.setCell(
          cellX,
          cellY,
          Cell(
            char: char,
            style: finalStyle,
          ),
        );""",
            """        _buffer.writeCell(
          cellX,
          cellY,
          char: char,
          style: finalStyle,
        );""",
        ),
        (
            """        _buffer.setCell(
          cellX,
          cellY,
          Cell(
            char: existingCell.char, // Keep the existing character!
            style: TextStyle(
              color: blendedFg,
              backgroundColor: blendedBg,
              fontWeight: existingCell.style.fontWeight,
              fontStyle: existingCell.style.fontStyle,
              decoration: existingCell.style.decoration,
              reverse: existingCell.style.reverse,
            ),
          ),
        );""",
            """        _buffer.writeCell(
          cellX,
          cellY,
          char: existingCell.char, // Keep the existing character!
          style: TextStyle(
            color: blendedFg,
            backgroundColor: blendedBg,
            fontWeight: existingCell.style.fontWeight,
            fontStyle: existingCell.style.fontStyle,
            decoration: existingCell.style.decoration,
            reverse: existingCell.style.reverse,
          ),
        );""",
        ),
        (
            """    _buffer.setCell(
      cellX,
      cellY,
      Cell(
        char: char,
        style: finalStyle,
      ),
    );""",
            """    _buffer.writeCell(
      cellX,
      cellY,
      char: char,
      style: finalStyle,
    );""",
        ),
    ]

    for old, new in replacements:
        text = replace_once(text, old, new)

    CANVAS.write_text(text, encoding='utf-8')


def replace_method(text: str, start_marker: str, end_marker: str, new: str) -> str:
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[:start] + new + text[end:]


def migrate_binding() -> None:
    text = BINDING.read_text(encoding='utf-8')

    text = replace_once(
        text,
        """  /// Previous frame's buffer for differential rendering.
  buf.Buffer? _previousBuffer;""",
        """  /// Front buffer currently represented by the physical terminal.
  buf.Buffer? _previousBuffer;

  /// Reusable back buffer painted for the next frame.
  buf.Buffer? _nextBuffer;

  int _lastComparedCells = 0;
  int _lastAnsiRuns = 0;

  /// Number of cells compared by the most recent differential frame.
  int get lastComparedCells => _lastComparedCells;

  /// Number of cursor-positioned ANSI runs emitted by the most recent frame.
  int get lastAnsiRuns => _lastAnsiRuns;""",
    )

    text = text.replace(
        """          // Clear previous buffer to force full redraw on resize
          _previousBuffer = null;
          scheduleFrame();""",
        """          // Drop both buffers to force a correctly sized full redraw.
          _previousBuffer = null;
          _nextBuffer = null;
          scheduleFrame();""",
    )

    text = replace_once(
        text,
        """    final size = terminal.size;
    final buffer = buf.Buffer(size.width.toInt(), size.height.toInt());
    final screenRect =""",
        """    final size = terminal.size;
    final buffer = _prepareNextBuffer(
      size.width.toInt(),
      size.height.toInt(),
    );
    final screenRect =""",
    )

    text = replace_once(
        text,
        """    // Store buffer for next frame comparison
    _previousBuffer = buffer;""",
        """    // Swap reusable front/back buffers. The old front becomes the next
    // paint target and will clear only the spans it touched previously.
    final reusable = _previousBuffer;
    _previousBuffer = buffer;
    _nextBuffer = reusable;""",
    )

    insert_marker = "  /// Renders only the cells that changed since the previous frame.\n"
    prepare_method = """  buf.Buffer _prepareNextBuffer(int width, int height) {
    var buffer = _nextBuffer;
    if (buffer == null || buffer.width != width || buffer.height != height) {
      buffer = buf.Buffer(width, height);
      _nextBuffer = buffer;
    } else {
      buffer.clear();
    }
    return buffer;
  }

"""
    if prepare_method not in text:
        text = text.replace(insert_marker, prepare_method + insert_marker, 1)

    old_start = "  /// Full buffer diff - compare every cell.\n  void _renderFullDiff"
    old_end = "  /// Full redraw (used for first frame or after resize)."
    new_method = """  /// Dirty-span differential renderer.
  ///
  /// Only the union of rows touched by the current and previous frame is
  /// inspected. Consecutive changed cells are emitted as one cursor-positioned
  /// ANSI run instead of one cursor move and write per cell.
  void _renderFullDiff(buf.Buffer buffer, buf.Buffer previous) {
    _lastComparedCells = 0;
    _lastAnsiRuns = 0;

    for (var y = 0; y < buffer.height; y++) {
      final currentDirty = buffer.isRowDirty(y);
      final previousDirty = previous.isRowDirty(y);
      if (!currentDirty && !previousDirty) continue;

      final start = currentDirty && previousDirty
          ? (buffer.dirtyStartForRow(y) < previous.dirtyStartForRow(y)
              ? buffer.dirtyStartForRow(y)
              : previous.dirtyStartForRow(y))
          : currentDirty
              ? buffer.dirtyStartForRow(y)
              : previous.dirtyStartForRow(y);
      final end = currentDirty && previousDirty
          ? (buffer.dirtyEndForRow(y) > previous.dirtyEndForRow(y)
              ? buffer.dirtyEndForRow(y)
              : previous.dirtyEndForRow(y))
          : currentDirty
              ? buffer.dirtyEndForRow(y)
              : previous.dirtyEndForRow(y);

      var x = start;
      while (x <= end) {
        _lastComparedCells++;
        final cell = buffer.getCell(x, y);
        final oldCell = previous.getCell(x, y);
        if (cell.matches(oldCell) ||
            cell.char == '\\u200B' ||
            cell.isImagePlaceholder) {
          x++;
          continue;
        }

        final runStart = x;
        final output = StringBuffer();
        TextStyle? activeStyle;

        while (x <= end) {
          _lastComparedCells++;
          final next = buffer.getCell(x, y);
          final old = previous.getCell(x, y);
          if (next.matches(old) ||
              next.char == '\\u200B' ||
              next.isImagePlaceholder) {
            break;
          }

          final hasStyle = _hasVisibleStyle(next.style);
          if (hasStyle) {
            if (activeStyle != next.style) {
              if (activeStyle != null) output.write(TextStyle.reset);
              output.write(next.style.toAnsi());
              activeStyle = next.style;
            }
          } else if (activeStyle != null) {
            output.write(TextStyle.reset);
            activeStyle = null;
          }

          output.write(next.char);
          x += next.width > 1 ? next.width : 1;
        }

        if (activeStyle != null) output.write(TextStyle.reset);
        terminal.moveCursor(runStart, y);
        terminal.write(output.toString());
        _lastAnsiRuns++;
      }
    }

    _renderPendingImages(buffer);
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

"""
    text = replace_method(text, old_start, old_end, new_method)

    BINDING.write_text(text, encoding='utf-8')


def main() -> None:
    migrate_canvas()
    migrate_binding()
    print('Renderer V2 core migration applied.')


if __name__ == '__main__':
    main()
