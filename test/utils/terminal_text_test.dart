import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalText.safe', () {
    test('removes ANSI, OSC, DCS, and terminal state injection', () {
      const input = 'before'
          '\x1b[31mred\x1b[0m'
          '\x1b]52;c;c2VjcmV0\x07'
          '\x1b]2;spoofed title\x1b\\'
          '\x1bPqpayload\x1b\\'
          'after';

      expect(TerminalText.safe(input), 'beforeredafter');
    });

    test('normalizes carriage returns and keeps useful whitespace', () {
      const input = '10%\r20%\nnext\tvalue';

      expect(TerminalText.safe(input), '10%\n20%\nnext\tvalue');
    });

    test('removes bidi overrides without damaging emoji sequences', () {
      const input = 'safe\u202Etxt 👩‍💻 cafe\u0301';

      expect(TerminalText.safe(input), 'safetxt 👩‍💻 cafe\u0301');
    });
  });

  group('TerminalText column operations', () {
    test('measures grapheme clusters in terminal columns', () {
      expect(TerminalText.measure('plain'), 5);
      expect(TerminalText.measure('A界B'), 4);
      expect(TerminalText.measure('x\nA界B'), 4);
      expect(TerminalText.measure('👩‍💻'), 2);
    });

    test('truncates without splitting wide graphemes', () {
      expect(TerminalText.truncate('abcdef', width: 4), 'abc…');
      expect(TerminalText.truncate('A界BC', width: 4), 'A界…');
      expect(TerminalText.measure(TerminalText.truncate('A界BC', width: 4)), 4);
    });

    test('slices only complete graphemes', () {
      expect(TerminalText.sliceColumns('A界BC', 0, 3), 'A界');
      expect(TerminalText.sliceColumns('A界BC', 1, 3), '界');
      expect(TerminalText.sliceColumns('A界BC', 2, 4), 'B');
    });
  });
}
