import 'package:characters/characters.dart';

/// Sanitizes untrusted text before it reaches Cinder's terminal cell buffer.
///
/// The sanitizer neutralizes terminal control characters and Unicode controls
/// that can alter cursor position, colors, clipboard state, terminal title,
/// screen buffers, image protocols, or the visual order of trusted UI text.
final class TerminalTextSanitizer {
  const TerminalTextSanitizer._();

  static const Map<int, String> _namedUnicodeControls = <int, String>{
    0x00AD: 'SHY',
    0x034F: 'CGJ',
    0x061C: 'ALM',
    0x180E: 'MVS',
    0x200B: 'ZWSP',
    0x200E: 'LRM',
    0x200F: 'RLM',
    0x202A: 'LRE',
    0x202B: 'RLE',
    0x202C: 'PDF',
    0x202D: 'LRO',
    0x202E: 'RLO',
    0x2060: 'WJ',
    0x2061: 'F(A)',
    0x2062: 'INVISIBLE_TIMES',
    0x2063: 'INVISIBLE_SEPARATOR',
    0x2064: 'INVISIBLE_PLUS',
    0x2066: 'LRI',
    0x2067: 'RLI',
    0x2068: 'FSI',
    0x2069: 'PDI',
    0x206A: 'ISS',
    0x206B: 'ASS',
    0x206C: 'IAFS',
    0x206D: 'AAFS',
    0x206E: 'NADS',
    0x206F: 'NODS',
    0xFEFF: 'BOM',
    0xFFF9: 'IAA',
    0xFFFA: 'IAS',
    0xFFFB: 'IAT',
  };

  /// Returns true when [input] can be placed in a terminal cell buffer without
  /// creating terminal commands or visually reordering trusted UI text.
  static bool isDisplaySafe(String input) {
    for (var index = 0; index < input.length; index++) {
      final codeUnit = input.codeUnitAt(index);
      if (_isUnsafeCodeUnit(codeUnit)) return false;
      if (_isHighSurrogate(codeUnit)) {
        if (index + 1 >= input.length ||
            !_isLowSurrogate(input.codeUnitAt(index + 1))) {
          return false;
        }
        final scalar = _surrogateScalar(codeUnit, input.codeUnitAt(index + 1));
        if (_supplementaryControlName(scalar) != null) return false;
        index++;
      } else if (_isLowSurrogate(codeUnit)) {
        return false;
      }
    }
    return true;
  }

  /// Sanitizes [input] into display-only text.
  ///
  /// Newlines are preserved, tabs become spaces, CRLF is normalized, C0
  /// controls become Unicode control pictures, C1 controls and dangerous
  /// zero-width/bidirectional controls become visible labels.
  static String sanitize(String input, {int tabWidth = 4}) {
    if (input.isEmpty || isDisplaySafe(input)) return input;
    if (tabWidth < 0) {
      throw ArgumentError.value(tabWidth, 'tabWidth', 'must be non-negative');
    }

    final output = StringBuffer();
    for (var index = 0; index < input.length; index++) {
      final codeUnit = input.codeUnitAt(index);

      if (_isHighSurrogate(codeUnit)) {
        if (index + 1 < input.length &&
            _isLowSurrogate(input.codeUnitAt(index + 1))) {
          final low = input.codeUnitAt(index + 1);
          final scalar = _surrogateScalar(codeUnit, low);
          final controlName = _supplementaryControlName(scalar);
          if (controlName != null) {
            output.write('⟦$controlName⟧');
            index++;
          } else {
            output
              ..writeCharCode(codeUnit)
              ..writeCharCode(low);
            index++;
          }
        } else {
          output.write('�');
        }
        continue;
      }
      if (_isLowSurrogate(codeUnit)) {
        output.write('�');
        continue;
      }

      if (codeUnit == 0x0D) {
        if (index + 1 < input.length && input.codeUnitAt(index + 1) == 0x0A) {
          output.write('\n');
          index++;
        } else {
          output.write('␍');
        }
        continue;
      }

      if (codeUnit == 0x0A) {
        output.write('\n');
        continue;
      }

      if (codeUnit == 0x09) {
        output.write(' ' * tabWidth);
        continue;
      }

      if (codeUnit >= 0x00 && codeUnit <= 0x1F) {
        output.writeCharCode(0x2400 + codeUnit);
        continue;
      }

      if (codeUnit == 0x7F) {
        output.write('␡');
        continue;
      }

      if (codeUnit >= 0x80 && codeUnit <= 0x9F) {
        output.write(
          '⟦U+${codeUnit.toRadixString(16).toUpperCase().padLeft(4, '0')}⟧',
        );
        continue;
      }

      final namedControl = _namedUnicodeControls[codeUnit];
      if (namedControl != null) {
        output.write('⟦$namedControl⟧');
        continue;
      }

      if (codeUnit == 0x2028 || codeUnit == 0x2029) {
        output.write('\n');
        continue;
      }

      output.writeCharCode(codeUnit);
    }

    return output.toString();
  }

  /// Converts arbitrary content into exactly one display-safe grapheme.
  ///
  /// This is the final defense for low-level cell writers. High-level text APIs
  /// should use [sanitize] so the complete escaped evidence remains visible.
  static String sanitizeCell(String input) {
    if (input.isEmpty) return ' ';
    final sanitized = sanitize(input);
    final graphemes = sanitized.characters;
    if (graphemes.length != 1) return '�';
    final grapheme = graphemes.first;
    return isDisplaySafe(grapheme) ? grapheme : '�';
  }

  /// Validates framework-generated display text.
  ///
  /// Trusted text is not a path for raw ANSI. Framework terminal commands must
  /// be emitted by the backend encoder, never stored in terminal cells.
  static String requireDisplaySafe(String input) {
    if (!isDisplaySafe(input)) {
      throw ArgumentError.value(
        input,
        'input',
        'Trusted terminal text contains control or bidi characters. '
            'Use TerminalText.safe for untrusted content and EscapeCodes/backend '
            'APIs for framework terminal commands.',
      );
    }
    return input;
  }

  static int _surrogateScalar(int high, int low) =>
      0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00);

  static String? _supplementaryControlName(int scalar) {
    if (scalar >= 0x1BCA0 && scalar <= 0x1BCAF) {
      return 'SHORTHAND_FORMAT_U+${scalar.toRadixString(16).toUpperCase()}';
    }
    if (scalar >= 0x13430 && scalar <= 0x1343F) {
      return 'HIEROGLYPH_FORMAT_U+${scalar.toRadixString(16).toUpperCase()}';
    }
    return null;
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  static bool _isLowSurrogate(int codeUnit) =>
      codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;

  static bool _isUnsafeCodeUnit(int codeUnit) {
    if (codeUnit == 0x0A) return false;
    if (codeUnit == 0x09) return true;
    if (codeUnit == 0x0D) return true;
    if (codeUnit <= 0x1F || codeUnit == 0x7F) return true;
    if (codeUnit >= 0x80 && codeUnit <= 0x9F) return true;
    if (_namedUnicodeControls.containsKey(codeUnit)) return true;
    return codeUnit == 0x2028 || codeUnit == 0x2029;
  }
}
