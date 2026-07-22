import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('terminal metadata methods cannot inject nested control sequences', () {
    final backend = _RecordingBackend();
    final terminal = Terminal(backend);

    terminal
      ..setWindowTitle('Cinder\x1b]52;c;c2VjcmV0\x07\x1b[2J')
      ..setIconName('icon\nname')
      ..setTitleAndIcon('safe\x1b[31mred\x1b[0m')
      ..flush();

    expect(
      backend.output.toString(),
      '\x1b]2;Cinder\x07'
      '\x1b]1;iconname\x07'
      '\x1b]0;safered\x07',
    );
  });

  test('clipboard content is encoded inside the OSC payload', () {
    final backend = _RecordingBackend();
    final terminal = Terminal(backend);

    terminal
      ..writeClipboardCopy('text\x1b]2;title\x07')
      ..flush();

    final output = backend.output.toString();
    expect(output, startsWith('\x1b]52;c;'));
    expect(output, endsWith('\x07'));
    expect(output.substring(5, output.length - 1), isNot(contains('\x1b')));
  });

  test('reset emits terminated color restore sequences', () {
    final backend = _RecordingBackend();
    final terminal = Terminal(backend)..reset();

    expect(backend.output.toString(), contains('\x1b]110\x07'));
    expect(backend.output.toString(), contains('\x1b]111\x07'));
    expect(backend.output.toString(), endsWith('\x1b[0m'));
  });
}

final class _RecordingBackend extends TerminalBackend {
  final StringBuffer output = StringBuffer();

  @override
  void writeRaw(String data) => output.write(data);

  @override
  Size getSize() => const Size(80, 24);

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream => null;

  @override
  Stream<Size>? get resizeStream => null;

  @override
  Stream<void>? get shutdownStream => null;

  @override
  void enableRawMode() {}

  @override
  void disableRawMode() {}

  @override
  bool get isAvailable => true;

  @override
  void requestExit([int exitCode = 0]) {}

  @override
  void dispose() {}
}
