import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('Icon renders terminal-safe Unicode by default', () async {
    await testCinder('icon unicode fallback', (tester) async {
      await tester.pumpWidget(const Icon(TerminalIcons.check));
      expect(tester.terminalState, containsText('✓'));
    });
  });

  test('IconTheme can force ASCII rendering', () async {
    await testCinder('icon ascii fallback', (tester) async {
      await tester.pumpWidget(
        const IconTheme(
          data: IconThemeData(renderMode: IconRenderMode.ascii),
          child: Icon(TerminalIcons.check),
        ),
      );
      expect(tester.terminalState, containsText('v'));
    });
  });

  test('unicode mode forces monochrome text presentation', () {
    const data = IconData.terminal('⚠️', asciiFallback: '!');
    expect(
      data.resolveGlyph(
        mode: IconRenderMode.unicode,
        usePrivateUseGlyphs: false,
        fallbackGlyph: '?',
      ),
      '⚠︎',
    );
  });

  test('emoji mode preserves the declared emoji presentation', () {
    const data = IconData.terminal('⚠️', asciiFallback: '!');
    expect(
      data.resolveGlyph(
        mode: IconRenderMode.emoji,
        usePrivateUseGlyphs: false,
        fallbackGlyph: '?',
      ),
      '⚠️',
    );
  });

  test('font mode renders the original private-use code point', () {
    const data = IconData(
      0xe001,
      fontFamily: 'ExampleIcons',
      unicodeFallback: '✓',
      asciiFallback: 'v',
    );
    expect(
      data.resolveGlyph(
        mode: IconRenderMode.font,
        usePrivateUseGlyphs: true,
        fallbackGlyph: '?',
      ),
      String.fromCharCode(0xe001),
    );
  });

  test('auto prefers a real icon-font glyph when explicitly enabled', () {
    const data = IconData(
      0xe001,
      fontFamily: 'ExampleIcons',
      unicodeFallback: '⚠️',
      asciiFallback: '!',
    );
    expect(
      data.resolveGlyph(
        mode: IconRenderMode.auto,
        usePrivateUseGlyphs: true,
        fallbackGlyph: '?',
      ),
      String.fromCharCode(0xe001),
    );
    expect(
      data.resolveGlyph(
        mode: IconRenderMode.auto,
        usePrivateUseGlyphs: false,
        fallbackGlyph: '?',
      ),
      '⚠︎',
    );
  });

  test('matchTextDirection mirrors terminal arrow fallbacks', () {
    expect(
      TerminalIcons.arrowLeft.resolveGlyph(
        mode: IconRenderMode.unicode,
        usePrivateUseGlyphs: false,
        fallbackGlyph: '?',
        textDirection: TextDirection.rtl,
      ),
      '→︎',
    );
  });
}
