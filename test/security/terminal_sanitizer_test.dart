import 'dart:math';

import 'package:cinder/cinder.dart';
import 'package:cinder/src/rendering/frame_diff.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalTextSanitizer', () {
    test('neutralizes ANSI, OSC, DCS, and alternate-screen injection', () {
      final input = <String>[
        '\x1b[31mred\x1b[0m',
        '\x1b]52;c;YXR0YWNr\x07',
        '\x1b]8;;https://evil.example\x07click\x1b]8;;\x07',
        '\x1b]0;fake title\x07',
        '\x1b[8;200;300t',
        '\x1b[2J\x1b[Hfake approval',
        '\x1b[?1049h',
        '\x1b_Gf=100;AAAA\x1b\\',
        '\x1bPq"1;1;1;1#0;2;0;0;0~\x1b\\',
      ].join('\n');

      final output = TerminalTextSanitizer.sanitize(input);

      expect(output.contains('\x1b'), isFalse);
      expect(output, contains('␛[31mred␛[0m'));
      expect(output, contains('␛]52'));
      expect(output, contains('fake approval'));
    });

    test('normalizes controls while preserving Unicode graphemes', () {
      const input = 'A\r\nB\tC\u0000👨‍👩‍👧‍👦界';
      final output = TerminalTextSanitizer.sanitize(input, tabWidth: 2);

      expect(output, 'A\nB  C␀👨‍👩‍👧‍👦界');
    });

    test('makes bidi overrides and hidden separators visible', () {
      const input = 'safe\u202Eexe.txt\u202C\u200Bend';
      expect(
        TerminalTextSanitizer.sanitize(input),
        'safe⟦RLO⟧exe.txt⟦PDF⟧⟦ZWSP⟧end',
      );
    });

    test('neutralizes additional invisible format controls', () {
      final shorthand = String.fromCharCode(0x1BCA0);
      const input = 'a\u00ADb\u034Fc\u180Ed\u206Ae\uFFF9f';
      expect(
        TerminalTextSanitizer.sanitize('$input$shorthand'),
        contains(
          'a⟦SHY⟧b⟦CGJ⟧c⟦MVS⟧d⟦ISS⟧e⟦IAA⟧f'
          '⟦SHORTHAND_FORMAT_U+1BCA0⟧',
        ),
      );
    });

    test('rejects malformed UTF-16 and preserves valid surrogate pairs', () {
      final malformed = String.fromCharCodes([0xD800, 0x61, 0xDC00]);
      expect(TerminalTextSanitizer.isDisplaySafe(malformed), isFalse);
      expect(TerminalTextSanitizer.sanitize(malformed), '�a�');
      expect(TerminalTextSanitizer.sanitize('😀'), '😀');
    });

    test('cell sanitizer never permits multi-cell control payloads', () {
      expect(TerminalTextSanitizer.sanitizeCell('A'), 'A');
      expect(TerminalTextSanitizer.sanitizeCell('👨‍👩‍👧‍👦'), '👨‍👩‍👧‍👦');
      expect(TerminalTextSanitizer.sanitizeCell('abc'), '�');
      expect(TerminalTextSanitizer.sanitizeCell('\x1b[2J'), '�');
    });

    test('trusted display text rejects control characters', () {
      expect(() => TerminalText.trusted('\x1b[31m'), throwsArgumentError);
      expect(TerminalText.trusted('framework label').trusted, isTrue);
    });

    test('safe terminal text stores sanitized content', () {
      final widget = TerminalText.safe('status: \x1b[32mok');
      expect(widget.data, 'status: ␛[32mok');
      expect(widget.trusted, isFalse);
    });

    test('terminal diff is a final defense for raw Cell writes', () {
      final previous = Buffer(8, 1);
      final current = Buffer(8, 1);
      current.writeCell(0, 0, char: '\x1b[2J');

      final output = StringBuffer();
      emitFrameDiff(
        current: current,
        previous: previous,
        emitRun: (x, y, data) => output.write(data),
      );

      expect(output.toString().contains('\x1b'), isFalse);
      expect(output.toString(), contains('�'));
    });

    test('fuzz: raw Cell values never become terminal commands', () {
      final random = Random(0xFEEDC1);
      for (var sample = 0; sample < 1000; sample++) {
        final previous = Buffer(4, 1);
        final current = Buffer(4, 1);
        final length = 1 + random.nextInt(8);
        final input = String.fromCharCodes(
          List<int>.generate(length, (_) => random.nextInt(0x10000)),
        );
        current.writeCell(0, 0, char: input);
        final output = StringBuffer();
        emitFrameDiff(
          current: current,
          previous: previous,
          emitRun: (x, y, data) => output.write(data),
        );
        expect(output.toString().contains('\x1b'), isFalse);
        expect(output.toString().contains('\x9b'), isFalse);
        expect(output.toString().contains('\x9d'), isFalse);
      }
    });

    test('fuzz: sanitized output never contains terminal controls', () {
      final random = Random(0xC1D3E);
      for (var sample = 0; sample < 5000; sample++) {
        final length = random.nextInt(256);
        final codeUnits = List<int>.generate(
          length,
          (_) => random.nextInt(0x10000),
          growable: false,
        );
        final input = String.fromCharCodes(codeUnits);
        final output = TerminalTextSanitizer.sanitize(input);
        expect(
          TerminalTextSanitizer.isDisplaySafe(output),
          isTrue,
          reason: 'unsafe output for sample $sample',
        );
        expect(output.contains('\x1b'), isFalse);
        expect(output.contains('\x9b'), isFalse);
        expect(output.contains('\x9d'), isFalse);
      }
    });
  });

  test('canvas is a final sanitization boundary', () async {
    await testCinder('canvas is a final sanitization boundary', (tester) async {
      await tester.pumpWidget(const Text('before\x1b[2J\x1b[Hafter'));

      expect(tester.terminalState.containsText('before␛[2J␛[Hafter'), isTrue);
    });
  });
}
