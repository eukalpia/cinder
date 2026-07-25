import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('TerminalText offset/column mapping', () {
    test('never splits a family emoji grapheme', () {
      const text = 'A👨‍👩‍👧‍👦B';
      final emojiStart = 1;
      final emojiEnd = text.length - 1;

      expect(TerminalText.graphemeCount(text), 3);
      expect(TerminalText.columnForOffset(text, emojiStart), 1);
      expect(TerminalText.columnForOffset(text, emojiStart + 2), 1);
      expect(TerminalText.columnForOffset(text, emojiEnd), 3);
      expect(TerminalText.offsetForColumn(text, 2), emojiStart);
      expect(
        TerminalText.offsetForColumn(text, 2, roundUpWide: true),
        emojiEnd,
      );
    });

    test('maps CJK wide cells deterministically', () {
      const text = 'A界B';

      expect(TerminalText.columnForOffset(text, 2), 3);
      expect(TerminalText.offsetForColumn(text, 2), 1);
      expect(TerminalText.offsetForColumn(text, 2, roundUpWide: true), 2);
      expect(TerminalText.offsetForColumn(text, 3), 2);
    });

    test('normalizes offsets inside combining sequences', () {
      const text = 'cafe\u0301!';
      final combiningOffset = text.indexOf('\u0301');

      expect(TerminalText.normalizeOffset(text, combiningOffset), 3);
      expect(
        TerminalText.normalizeOffset(text, combiningOffset, roundUp: true),
        5,
      );
    });
  });
}
