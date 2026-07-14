import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('IconData', () {
    const icon = IconData(
      0xe8b6,
      fontFamily: 'Material Icons',
      terminalGlyph: '⌕',
      asciiFallback: '?',
      semanticLabel: 'search',
    );

    test('uses terminal glyph by default', () {
      expect(icon.resolveGlyph(), '⌕');
    });

    test('uses font code point when icon fonts are enabled', () {
      expect(icon.resolveGlyph(supportsIconFont: true), String.fromCharCode(0xe8b6));
    });

    test('falls back to ASCII when no terminal glyph exists', () {
      const fallback = IconData(0xf000, asciiFallback: '#');
      expect(fallback.resolveGlyph(), '#');
    });
  });

  test('IconThemeData copyWith preserves unspecified values', () {
    const original = IconThemeData(
      color: Color.fromRGB(10, 20, 30),
      size: 2,
      supportsIconFont: true,
      fallbackGlyph: '*',
    );

    final updated = original.copyWith(size: 3);

    expect(updated.color, original.color);
    expect(updated.size, 3);
    expect(updated.supportsIconFont, isTrue);
    expect(updated.fallbackGlyph, '*');
  });
}
