import 'package:cinder/cinder.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';
import 'package:test/test.dart';

void main() {
  test('a NaN canvas width retains ASCII and mixed-text drawing behavior', () {
    final buffer = Buffer(8, 2);
    final canvas = TerminalCanvas(
      buffer,
      const Rect.fromLTWH(0, 0, double.nan, 2),
    );

    canvas.drawText(Offset.zero, 'abc');
    canvas.drawText(const Offset(0, 1), 'abe\u0301');

    expect(
      [for (var x = 0; x < 3; x++) buffer.getCell(x, 0).char],
      ['a', 'b', 'c'],
    );
    expect(
      [for (var x = 0; x < 3; x++) buffer.getCell(x, 1).char],
      ['a', 'b', 'e\u0301'],
    );
  });

  test('ASCII drawing resolves the canvas origin once per run', () {
    final buffer = Buffer(16, 4);
    final area = _CountingRect(3, 1, 8, 2);
    final canvas = TerminalCanvas(buffer, area);

    canvas.drawText(const Offset(1, 1), 'hello');

    expect(area.leftReads, 1);
    expect(area.topReads, 1);
    expect(
      [for (var x = 4; x < 9; x++) buffer.getCell(x, 2).char].join(),
      'hello',
    );
  });

  test('ASCII clipping and tabs preserve their existing cell positions', () {
    final buffer = Buffer(8, 2);
    final canvas = TerminalCanvas(buffer, const Rect.fromLTWH(2, 1, 4, 1));

    canvas.drawText(const Offset(1, 0), 'a\tbc');

    expect(
      [for (var x = 0; x < 8; x++) buffer.getCell(x, 1).char].join(),
      '   a b  ',
    );
  });

  test('ASCII following a wide glyph clears either overwritten partner', () {
    final buffer = Buffer(6, 1);
    final canvas = TerminalCanvas(buffer, const Rect.fromLTWH(0, 0, 6, 1));
    canvas.drawText(Offset.zero, '界界');
    canvas.drawText(const Offset(1, 0), 'ab');

    expect(
      [for (var x = 0; x < 6; x++) buffer.getCell(x, 0).char],
      [' ', 'a', 'b', ' ', ' ', ' '],
    );
  });

  test('an ASCII prefix keeps combining and variation-selector clusters', () {
    final buffer = Buffer(8, 1);
    final canvas = TerminalCanvas(buffer, const Rect.fromLTWH(0, 0, 8, 1));

    canvas.drawText(Offset.zero, 'ABe\u0301A\ufe0f界');

    expect(
      [for (var x = 0; x < 8; x++) buffer.getCell(x, 0).char],
      ['A', 'B', 'e\u0301', 'A\ufe0f', '\u200b', '界', '\u200b', ' '],
    );
  });

  test('ASCII colors still inherit and blend independently for every cell', () {
    final buffer = Buffer(2, 1);
    final canvas = TerminalCanvas(buffer, const Rect.fromLTWH(0, 0, 2, 1));
    buffer.writeCell(
      0,
      0,
      char: '.',
      style: const TextStyle(backgroundColor: Color(0x0000ff)),
    );
    buffer.writeCell(
      1,
      0,
      char: '.',
      style: const TextStyle(backgroundColor: Color(0x00ff00)),
    );

    canvas.drawText(
      Offset.zero,
      'ab',
      style: const TextStyle(color: Color.fromARGB(128, 255, 0, 0)),
    );

    expect(buffer.getCell(0, 0).style.color, const Color.fromRGB(128, 0, 127));
    expect(buffer.getCell(1, 0).style.color, const Color.fromRGB(128, 127, 0));
    expect(buffer.getCell(0, 0).style.backgroundColor, const Color(0x0000ff));
    expect(buffer.getCell(1, 0).style.backgroundColor, const Color(0x00ff00));
  });
}

class _CountingRect extends Rect {
  _CountingRect(super.left, super.top, super.width, super.height)
    : super.fromLTWH();

  int leftReads = 0;
  int topReads = 0;

  @override
  double get left {
    leftReads++;
    return super.left;
  }

  @override
  double get top {
    topReads++;
    return super.top;
  }
}
