import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalCapabilities safety profiles', () {
    test('CI disables terminal control even with an xterm TERM', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-256color',
          'CI': 'true',
        },
      );

      expect(capabilities.isCi, isTrue);
      expect(capabilities.isInteractive, isFalse);
      expect(capabilities.supportsRawMode, isFalse);
      expect(capabilities.supportsAlternateScreen, isFalse);
      expect(capabilities.supportsMouse, isFalse);
    });

    test('redirected stdout disables interactive control', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{'TERM': 'xterm-kitty'},
        stdoutHasTerminal: false,
      );

      expect(capabilities.isRedirected, isTrue);
      expect(capabilities.isInteractive, isFalse);
      expect(capabilities.supportsKittyKeyboard, isFalse);
      expect(capabilities.preferredImageProtocol, ImageProtocol.unicodeBlocks);
    });

    test('NO_COLOR disables color without disabling keyboard input', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-256color',
          'NO_COLOR': '1',
        },
      );

      expect(capabilities.isInteractive, isTrue);
      expect(capabilities.supports256Colors, isFalse);
      expect(capabilities.supportsTrueColor, isFalse);
      expect(capabilities.supportsModifyOtherKeys, isTrue);
    });

    test('force interactive is an explicit escape hatch for controlled CI', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-kitty',
          'CI': 'true',
          'CINDER_FORCE_INTERACTIVE': 'true',
        },
      );

      expect(capabilities.isCi, isTrue);
      expect(capabilities.isInteractive, isTrue);
      expect(capabilities.supportsRawMode, isTrue);
      expect(capabilities.supportsKittyKeyboard, isTrue);
    });
  });
}
