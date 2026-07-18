import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalCapabilities.fromEnvironment', () {
    test('uses Unicode blocks in VS Code despite xterm TERM', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-256color',
          'TERM_PROGRAM': 'vscode',
          'COLORTERM': 'truecolor',
        },
      );

      expect(capabilities.supportsSixel, isFalse);
      expect(
        capabilities.preferredImageProtocol,
        ImageProtocol.unicodeBlocks,
      );
    });

    test('uses Unicode blocks in Windows Terminal despite xterm TERM', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-256color',
          'WT_SESSION': 'session-id',
          'COLORTERM': 'truecolor',
        },
      );

      expect(capabilities.supportsNativeImages, isFalse);
      expect(
        capabilities.preferredImageProtocol,
        ImageProtocol.unicodeBlocks,
      );
    });

    test('does not infer Sixel from generic xterm-256color', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-256color',
        },
      );

      expect(capabilities.supportsSixel, isFalse);
      expect(
        capabilities.preferredImageProtocol,
        ImageProtocol.unicodeBlocks,
      );
    });

    test('detects an explicitly named Sixel terminal', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-sixel',
        },
      );

      expect(capabilities.supportsSixel, isTrue);
      expect(capabilities.preferredImageProtocol, ImageProtocol.sixel);
    });

    test('respects an explicit protocol override in VS Code', () {
      final capabilities = TerminalCapabilities.fromEnvironment(
        const <String, String>{
          'TERM': 'xterm-256color',
          'TERM_PROGRAM': 'vscode',
          'CINDER_IMAGE_PROTOCOL': 'sixel',
        },
      );

      expect(capabilities.preferredImageProtocol, ImageProtocol.sixel);
    });
  });
}
