import 'package:cinder/cinder.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';
import 'package:test/test.dart';

class _DerivedStyle extends TextStyle {
  const _DerivedStyle() : super(color: const Color(0xff0000));
}

void main() {
  late Buffer buffer;
  late TerminalCanvas canvas;

  setUp(() {
    buffer = Buffer(8, 2);
    canvas = TerminalCanvas(buffer, const Rect.fromLTWH(0, 0, 8, 2));
  });

  test('plain text reuses its immutable style across cells', () {
    const style = TextStyle();
    canvas.drawText(Offset.zero, 'hello', style: style);

    for (var x = 0; x < 5; x++) {
      expect(buffer.getCell(x, 0).style, same(style));
    }
  });

  test('opaque styled text reuses the style on wide continuation cells', () {
    const style = TextStyle(
      color: Color(0xff0000),
      backgroundColor: Color(0x0000ff),
      fontWeight: FontWeight.bold,
      fontStyle: FontStyle.italic,
      decoration: TextDecoration.overline,
      reverse: true,
    );
    canvas.drawText(Offset.zero, 'A界👩‍💻', style: style);

    expect(
      [for (var x = 0; x < 5; x++) buffer.getCell(x, 0).char],
      ['A', '界', '\u200b', '👩‍💻', '\u200b'],
    );
    for (var x = 0; x < 5; x++) {
      expect(buffer.getCell(x, 0).style, same(style));
    }
  });

  test('rectangle fill reuses unchanged styles', () {
    const style = TextStyle(decoration: TextDecoration.lineThrough);
    canvas.fillRect(const Rect.fromLTWH(0, 0, 8, 2), '.', style: style);

    for (var y = 0; y < 2; y++) {
      for (var x = 0; x < 8; x++) {
        expect(buffer.getCell(x, y).style, same(style));
      }
    }
  });

  test('unspecified colors inherit while text attributes are replaced', () {
    const background = TextStyle(
      color: Color(0x00ff00),
      backgroundColor: Color(0x0000ff),
      fontWeight: FontWeight.bold,
      fontStyle: FontStyle.italic,
      decoration: TextDecoration.underline,
      reverse: true,
    );
    canvas.fillRect(const Rect.fromLTWH(0, 0, 8, 2), '.', style: background);
    const style = TextStyle(decoration: TextDecoration.overline);
    canvas.drawText(Offset.zero, 'A', style: style);

    expect(buffer.getCell(0, 0).style, isNot(same(style)));
    expect(
      buffer.getCell(0, 0).style,
      const TextStyle(
        color: Color(0x00ff00),
        backgroundColor: Color(0x0000ff),
        decoration: TextDecoration.overline,
      ),
    );
  });

  test('transparent foreground and background still blend independently', () {
    canvas.fillRect(
      const Rect.fromLTWH(0, 0, 8, 2),
      '.',
      style: const TextStyle(backgroundColor: Color(0x0000ff)),
    );
    const style = TextStyle(
      color: Color.fromARGB(128, 255, 0, 0),
      backgroundColor: Color.fromARGB(128, 0, 255, 0),
      fontWeight: FontWeight.dim,
      reverse: true,
    );
    canvas.drawText(Offset.zero, 'A', style: style);

    expect(buffer.getCell(0, 0).style, isNot(same(style)));
    expect(
      buffer.getCell(0, 0).style,
      const TextStyle(
        color: Color.fromRGB(128, 0, 127),
        backgroundColor: Color.fromRGB(0, 128, 127),
        fontWeight: FontWeight.dim,
        reverse: true,
      ),
    );
  });

  test('terminal default colors remain distinct from explicit black', () {
    const style = TextStyle(
      color: Color.defaultColor,
      backgroundColor: Color.defaultColor,
    );
    canvas.drawText(Offset.zero, 'A', style: style);

    expect(buffer.getCell(0, 0).style, same(style));
    expect(buffer.getCell(0, 0).style.color!.isDefault, isTrue);
    expect(buffer.getCell(0, 0).style.color, isNot(const Color(0)));
  });

  test('wide glyphs blend each occupied cell against its own background', () {
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
      '界',
      style: const TextStyle(color: Color.fromARGB(128, 255, 0, 0)),
    );

    expect(buffer.getCell(0, 0).char, '界');
    expect(buffer.getCell(1, 0).char, '\u200b');
    expect(
      buffer.getCell(0, 0).style,
      const TextStyle(
        color: Color.fromRGB(128, 0, 127),
        backgroundColor: Color(0x0000ff),
      ),
    );
    expect(
      buffer.getCell(1, 0).style,
      const TextStyle(
        color: Color.fromRGB(128, 127, 0),
        backgroundColor: Color(0x00ff00),
      ),
    );
  });

  test('derived styles retain the existing base-style snapshot semantics', () {
    canvas.drawText(Offset.zero, 'A', style: const _DerivedStyle());

    expect(buffer.getCell(0, 0).style.runtimeType, TextStyle);
    expect(buffer.getCell(0, 0).style, const TextStyle(color: Color(0xff0000)));
  });
}
