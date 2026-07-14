import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('Buffer scrollRegion scrolls only the requested rows', () {
    final buffer = Buffer(3, 5);
    for (var y = 0; y < 5; y++) {
      buffer.setString(0, y, '$y$y$y');
    }
    buffer.resetDirtyTracking();

    buffer.scrollRegion(1, 4, 1);

    expect(buffer.getCell(0, 0).char, '0');
    expect(buffer.getCell(0, 1).char, '2');
    expect(buffer.getCell(0, 2).char, '3');
    expect(buffer.getCell(0, 3).char, ' ');
    expect(buffer.getCell(0, 4).char, '4');
  });

  test('synchronizeFrom repairs alternating buffer divergence', () {
    final front = Buffer(5, 2)..setString(0, 0, 'hello');
    final back = Buffer(5, 2)..setString(0, 1, 'stale');
    back.synchronizeFrom(front);
    expect(back.getCell(0, 0).char, 'h');
    expect(back.getCell(0, 1).char, ' ');
    expect(back.dirtyCellUpperBound, 0);
  });

  test('escape codes define and reset a DEC scroll region', () {
    expect(EscapeCodes.setScrollRegion(2, 10), '\x1b[3;10r');
    expect(EscapeCodes.scrollUp(2), '\x1b[2S');
    expect(EscapeCodes.scrollDown(3), '\x1b[3T');
    expect(EscapeCodes.resetScrollRegion, '\x1b[r');
  });
}
