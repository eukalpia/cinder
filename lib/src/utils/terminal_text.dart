import 'package:characters/characters.dart';

import 'unicode_width.dart';

/// Terminal-safe text operations based on grapheme clusters and cell widths.
abstract final class TerminalText {
  /// Marks framework-generated text as trusted.
  ///
  /// This method intentionally performs no transformation. It documents the
  /// trust boundary at call sites where escape sequences are expected.
  static String trusted(String text) => text;

  /// Removes terminal control sequences and unsafe invisible formatting.
  ///
  /// Newlines and tabs are preserved by default. Carriage returns are converted
  /// to newlines so progress output cannot rewrite previously rendered content.
  static String safe(
    String text, {
    bool preserveNewlines = true,
    bool preserveTabs = true,
  }) {
    if (text.isEmpty) return text;

    final output = StringBuffer();
    final runes = text.runes.toList(growable: false);

    var index = 0;
    while (index < runes.length) {
      final rune = runes[index];

      if (rune == 0x1B) {
        index = _consumeEscapeSequence(runes, index);
        continue;
      }

      if (rune >= 0x80 && rune <= 0x9F) {
        index = _consumeC1Sequence(runes, index);
        continue;
      }

      if (rune == 0x0A) {
        if (preserveNewlines) output.writeCharCode(rune);
        index++;
        continue;
      }

      if (rune == 0x0D) {
        if (preserveNewlines &&
            (index + 1 >= runes.length || runes[index + 1] != 0x0A)) {
          output.write('\n');
        }
        index++;
        continue;
      }

      if (rune == 0x09) {
        if (preserveTabs) output.writeCharCode(rune);
        index++;
        continue;
      }

      if (_isUnsafeControl(rune) || _isUnsafeFormatting(rune)) {
        index++;
        continue;
      }

      output.writeCharCode(rune);
      index++;
    }

    return output.toString();
  }

  /// Returns the width of the widest line in terminal columns.
  static int measure(String text) {
    var widest = 0;
    for (final line in text.split('\n')) {
      final width = UnicodeWidth.stringWidth(line);
      if (width > widest) widest = width;
    }
    return widest;
  }

  /// Returns the width of [text] in terminal columns.
  static int lineWidth(String text) => UnicodeWidth.stringWidth(text);

  /// Truncates a single line without splitting a grapheme cluster.
  static String truncate(
    String text, {
    required int width,
    String ellipsis = '…',
  }) {
    if (width <= 0 || text.isEmpty) return '';

    final firstLineEnd = text.indexOf('\n');
    final line = firstLineEnd == -1 ? text : text.substring(0, firstLineEnd);
    if (lineWidth(line) <= width) return line;

    final fittedEllipsis = sliceColumns(ellipsis, 0, width);
    final ellipsisWidth = lineWidth(fittedEllipsis);
    final contentWidth = width - ellipsisWidth;
    if (contentWidth <= 0) return fittedEllipsis;

    final output = StringBuffer();
    var column = 0;
    for (final grapheme in line.characters) {
      final graphemeWidth = UnicodeWidth.graphemeWidth(grapheme);
      if (graphemeWidth == 0) continue;
      if (column + graphemeWidth > contentWidth) break;
      output.write(grapheme);
      column += graphemeWidth;
    }
    output.write(fittedEllipsis);
    return output.toString();
  }

  /// Returns complete graphemes occupying columns in `[start, end)`.
  ///
  /// A wide grapheme intersected by either boundary is omitted instead of being
  /// split into an invalid half-cell representation.
  static String sliceColumns(String text, int start, int end) {
    if (text.isEmpty || start >= end || end <= 0) return '';

    final effectiveStart = start < 0 ? 0 : start;
    final output = StringBuffer();
    var column = 0;

    for (final grapheme in text.characters) {
      if (grapheme == '\n') break;

      final width = UnicodeWidth.graphemeWidth(grapheme);
      if (width == 0) continue;

      final nextColumn = column + width;
      if (column >= end) break;
      if (column >= effectiveStart && nextColumn <= end) {
        output.write(grapheme);
      }
      column = nextColumn;
    }

    return output.toString();
  }

  static int _consumeEscapeSequence(List<int> runes, int index) {
    if (index + 1 >= runes.length) return runes.length;
    final next = runes[index + 1];

    if (next == 0x5B) return _consumeCsi(runes, index + 2);
    if (next == 0x5D) {
      return _consumeStringSequence(runes, index + 2, allowBell: true);
    }
    if (next == 0x50 || next == 0x58 || next == 0x5E || next == 0x5F) {
      return _consumeStringSequence(runes, index + 2, allowBell: false);
    }

    final nextIndex = index + 2;
    return nextIndex < runes.length ? nextIndex : runes.length;
  }

  static int _consumeC1Sequence(List<int> runes, int index) {
    final rune = runes[index];
    if (rune == 0x9B) return _consumeCsi(runes, index + 1);
    if (rune == 0x9D) {
      return _consumeStringSequence(runes, index + 1, allowBell: true);
    }
    if (rune == 0x90 || rune == 0x98 || rune == 0x9E || rune == 0x9F) {
      return _consumeStringSequence(runes, index + 1, allowBell: false);
    }
    return index + 1;
  }

  static int _consumeCsi(List<int> runes, int index) {
    while (index < runes.length) {
      final rune = runes[index++];
      if (rune >= 0x40 && rune <= 0x7E) break;
    }
    return index;
  }

  static int _consumeStringSequence(
    List<int> runes,
    int index, {
    required bool allowBell,
  }) {
    while (index < runes.length) {
      final rune = runes[index];
      if (allowBell && rune == 0x07) return index + 1;
      if (rune == 0x9C) return index + 1;
      if (rune == 0x1B &&
          index + 1 < runes.length &&
          runes[index + 1] == 0x5C) {
        return index + 2;
      }
      index++;
    }
    return index;
  }

  static bool _isUnsafeControl(int rune) {
    return rune < 0x20 || rune == 0x7F;
  }

  static bool _isUnsafeFormatting(int rune) {
    return rune == 0x061C ||
        rune == 0x200B ||
        rune == 0x200E ||
        rune == 0x200F ||
        (rune >= 0x202A && rune <= 0x202E) ||
        (rune >= 0x2066 && rune <= 0x2069) ||
        rune == 0xFEFF;
  }
}
