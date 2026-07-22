import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalCapabilities.fromEnvironment', () {
    test('disables interactive features for dumb terminals', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{'TERM': 'dumb'},
      );

      expect(capabilities.isDumb, isTrue);
      expect(capabilities.supportsMouse, isFalse);
      expect(capabilities.supportsBracketedPaste, isFalse);
      expect(capabilities.supportsHyperlinks, isFalse);
      expect(capabilities.preferredImageProtocol, ImageProtocol.unicodeBlocks);
    });

    test('detects modern kitty sessions over SSH', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-kitty',
          'KITTY_WINDOW_ID': '1',
          'SSH_CONNECTION': 'client server',
          'COLORTERM': 'truecolor',
        },
      );

      expect(capabilities.isSsh, isTrue);
      expect(capabilities.supportsKittyGraphics, isTrue);
      expect(capabilities.supportsKittyKeyboard, isTrue);
      expect(capabilities.supportsTrueColor, isTrue);
      expect(capabilities.supportsSynchronizedOutput, isTrue);
      expect(capabilities.preferredImageProtocol, ImageProtocol.kitty);
    });

    test('does not assume generic xterm has sixel', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{'TERM': 'xterm-256color'},
      );

      expect(capabilities.supports256Colors, isTrue);
      expect(capabilities.supportsMouse, isTrue);
      expect(capabilities.supportsSixel, isFalse);
    });

    test('supports explicit sixel detection and protocol overrides', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-256color',
          'CINDER_SIXEL': 'true',
          'CINDER_IMAGE_PROTOCOL': 'unicode',
        },
      );

      expect(capabilities.supportsSixel, isTrue);
      expect(capabilities.preferredImageProtocol, ImageProtocol.unicodeBlocks);
    });

    test('tracks tmux sessions separately from terminal features', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'tmux-256color',
          'TMUX': '/tmp/tmux,1,0',
        },
      );

      expect(capabilities.isTmux, isTrue);
      expect(capabilities.supportsMouse, isTrue);
      expect(capabilities.supportsKittyGraphics, isFalse);
    });
  });
}
