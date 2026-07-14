import 'package:cinder/src/buffer.dart';
import 'package:test/test.dart';

void main() {
  group('Buffer V2', () {
    test('reuses cell identity across writes and clears', () {
      final buffer = Buffer(8, 3);
      final original = buffer.getCell(2, 1);

      buffer.writeCell(2, 1, char: 'X');
      expect(identical(original, buffer.getCell(2, 1)), isTrue);
      expect(buffer.getCell(2, 1).char, 'X');

      buffer.clear();
      expect(identical(original, buffer.getCell(2, 1)), isTrue);
      expect(buffer.getCell(2, 1).char, ' ');
      expect(buffer.isRowDirty(1), isFalse);
    });

    test('tracks the minimal touched span per row', () {
      final buffer = Buffer(20, 4)
        ..writeCell(7, 2, char: 'A')
        ..writeCell(11, 2, char: 'B');

      expect(buffer.dirtyStartForRow(2), 7);
      expect(buffer.dirtyEndForRow(2), 11);
      expect(buffer.dirtyCellUpperBound, 5);
      expect(buffer.isRowDirty(0), isFalse);
    });

    test('wide graphemes reserve and clear their continuation cell', () {
      final buffer = Buffer(8, 1)..setString(0, 0, '界');

      expect(buffer.getCell(0, 0).char, '界');
      expect(buffer.getCell(0, 0).width, 2);
      expect(buffer.getCell(1, 0).char, '\u200B');

      buffer.clear();
      expect(buffer.getCell(0, 0).char, ' ');
      expect(buffer.getCell(1, 0).char, ' ');
    });

    test('clips dirty rectangles to the viewport', () {
      final buffer = Buffer(10, 3)..markDirtyRect(-5, 1, 30, 3);

      expect(buffer.dirtyStartForRow(1), 0);
      expect(buffer.dirtyEndForRow(1), 9);
      expect(buffer.dirtyStartForRow(2), 0);
      expect(buffer.dirtyEndForRow(2), 9);
      expect(buffer.isRowDirty(0), isFalse);
    });
  });
}
