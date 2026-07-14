import 'package:cinder/src/utils/terminal_color_support_internal.dart';
import 'package:test/test.dart';

void main() {
  group('detectTruecolorFromEnv', () {
    test('CINDER_TRUECOLOR overrides to true', () {
      expect(
        detectTruecolorFromEnv({'CINDER_TRUECOLOR': '1'}),
        isTrue,
      );
      expect(
        detectTruecolorFromEnv({'CINDER_TRUECOLOR': 'true'}),
        isTrue,
      );
    });

    test('CINDER_TRUECOLOR overrides to false', () {
      expect(
        detectTruecolorFromEnv({'CINDER_TRUECOLOR': '0'}),
        isFalse,
      );
      expect(
        detectTruecolorFromEnv({'CINDER_TRUECOLOR': 'off'}),
        isFalse,
      );
    });

    test('COLORTERM enables truecolor', () {
      expect(
        detectTruecolorFromEnv({'COLORTERM': 'truecolor'}),
        isTrue,
      );
      expect(
        detectTruecolorFromEnv({'COLORTERM': '24bit'}),
        isTrue,
      );
    });

    test('TERM enables truecolor', () {
      expect(
        detectTruecolorFromEnv({'TERM': 'xterm-truecolor'}),
        isTrue,
      );
      expect(
        detectTruecolorFromEnv({'TERM': 'screen-24bit'}),
        isTrue,
      );
    });

    test('defaults to false when no signals are present', () {
      expect(detectTruecolorFromEnv({}), isFalse);
      expect(detectTruecolorFromEnv({'TERM': 'xterm-256color'}), isFalse);
    });
  });
}
