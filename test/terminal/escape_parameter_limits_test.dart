import 'package:cinder/src/third_party/xterm_pure.dart/xterm.dart';
import 'package:test/test.dart';

void main() {
  test('child resize requests never reach the allocation handler', () {
    final handler = _RecordingHandler();
    final parser = EscapeParser(handler);
    parser.write('\x1b[8;5000;5000t');
    parser.write('\x1b[8;24;80t');
    expect(handler.resizes, isEmpty);
  });

  test('host resize remains authoritative and reports actual dimensions', () {
    final resizes = <(int, int)>[];
    final replies = <String>[];
    final terminal = Terminal(
      onResize: (width, height, _, _) => resizes.add((width, height)),
      onOutput: replies.add,
    );
    terminal.resize(93, 27);
    terminal.write('\x1b[8;10;10t\x1b[18t');
    expect((terminal.viewWidth, terminal.viewHeight), (93, 27));
    expect(resizes, [(93, 27)]);
    expect(replies.single, '\x1b[8;27;93t');
    terminal.resize(111, 39);
    expect((terminal.viewWidth, terminal.viewHeight), (111, 39));
    expect(resizes, [(93, 27), (111, 39)]);
  });

  test('REP expansion is limited to the current viewport character budget', () {
    final terminal = Terminal()..resize(5, 3);
    // A small, safe request exposes the missing bound without a huge loop.
    terminal.write('X\x1b[1000b!');
    expect(_lines(terminal), ['XXXXX', 'XXXXX', 'XXXXX', 'X!']);
    expect((terminal.buffer.cursorX, terminal.buffer.cursorY), (2, 2));
  });

  test('ordinary REP preserves wrapping and scrolling margins', () {
    final terminal = Terminal()..resize(5, 4);
    terminal.write('TOP\x1b[4;1HBOT\x1b[2;3r\x1b[2;1HX\x1b[12b');
    expect(_lines(terminal), ['TOP', 'XXXXX', 'XXX', 'BOT']);
    expect((terminal.buffer.cursorX, terminal.buffer.cursorY), (3, 2));
  });

  test('REP handles wide characters and the zero/default count', () {
    final terminal = Terminal()..resize(8, 3);
    terminal.write('🙂\x1b[0b\x1b[b');
    expect(_lines(terminal), ['🙂🙂🙂', '', '']);
    expect(terminal.buffer.cursorX, 6);
  });

  test('numeric CSI overflow discards the sequence without wrapped values', () {
    final handler = _RecordingHandler();
    final parser = EscapeParser(handler);
    parser.write('\x1b[2147483647b');
    // Both values exceed signed32bit; the latter wraps to1 on native int64.
    parser.write('\x1b[2147483648b');
    parser.write('\x1b[18446744073709551617b');
    parser.write('VISIBLE\x1b[3b');
    expect(handler.repeats, [2147483647, 3]);
    expect(handler.text.toString(), 'VISIBLE');
  });
}

List<String> _lines(Terminal terminal) => [
  for (var i = 0; i < terminal.buffer.lines.length; i++)
    terminal.buffer.lines[i].getText(),
];

// Records parser side effects without performing any requested allocation or
// expansion. Actual low-viewport behavior is exercised by the Terminal tests.
class _RecordingHandler implements EscapeHandler {
  final resizes = <(int, int)>[];
  final repeats = <int>[];
  final text = StringBuffer();

  @override
  void resize(int cols, int rows) => resizes.add((cols, rows));

  @override
  void repeatPreviousCharacter(int count) => repeats.add(count);

  @override
  void writeChar(int char) => text.writeCharCode(char);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
