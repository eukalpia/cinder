import 'dart:mirrors';

import 'package:cinder/src/third_party/xterm_pure.dart/src/utils/byte_consumer.dart';
import 'package:cinder/src/third_party/xterm_pure.dart/src/utils/debugger.dart';
import 'package:cinder/src/third_party/xterm_pure.dart/xterm.dart';
import 'package:test/test.dart';

void main() {
  for (final sequence in ['\x1b]2;', '\x1b[']) {
    test(
      'incomplete ${sequence.codeUnits} advances without retaining input',
      () {
        final terminal = Terminal()..resize(80, 24);
        final parser = EscapeParser(terminal);
        parser.write(sequence);
        var consumed = sequence.length;
        final block = sequence.endsWith('[') ? '1;' * 64 : 'x' * 128;
        for (var i = 0; i < 512; i++) {
          parser.write(block);
          consumed += block.length;
          expect(parser.tokenEnd, consumed);
          expect(_retainedInputRunes(parser), 0);
          expect(_retainedSequenceUnits(parser), lessThanOrEqualTo(8192));
        }
      },
    );
  }

  test('oversized OSC discards until BEL or split ST and then recovers', () {
    for (final terminator in ['\x07', '\x1b\\']) {
      final titles = <String>[];
      final terminal = Terminal(onTitleChange: titles.add)..resize(80, 24);
      final parser = EscapeParser(terminal);
      parser.write('\x1b]2;');
      for (var i = 0; i < 100; i++) {
        parser.write('🙂' * 64);
      }
      parser.write('\x1bXhidden');
      for (final char in terminator.runes) {
        parser.write(String.fromCharCode(char));
      }
      parser.write('VISIBLE\x1b]2;normal\x07');
      expect(titles, ['normal']);
      expect(terminal.buffer.lines[0].getText(), 'VISIBLE');
      expect(_retainedInputRunes(parser), 0);
      expect(_retainedSequenceUnits(parser), 0);
    }
  });

  test('oversized CSI never dispatches its accumulated parameters', () {
    final terminal = _ObservedTerminal()..resize(80, 24);
    final parser = EscapeParser(terminal);
    parser.write('\x1b[');
    for (var i = 0; i < 100; i++) {
      parser.write('1;' * 64);
    }
    parser.write('1mVISIBLE');
    expect(terminal.boldCalls, 0);
    expect(terminal.buffer.lines[0].getText(), 'VISIBLE');
    parser.write('\x1b[1m');
    expect(terminal.boldCalls, 1);
    expect(_retainedInputRunes(parser), 0);
    expect(_retainedSequenceUnits(parser), 0);
  });

  test('normal split OSC BEL and ST preserve Unicode titles and text', () {
    for (final terminator in ['\x07', '\x1b\\']) {
      final titles = <String>[];
      final terminal = Terminal(onTitleChange: titles.add)..resize(80, 24);
      final parser = EscapeParser(terminal);
      final input = '\x1b]2;🙂 café$terminator你好';
      for (final rune in input.runes) {
        parser.write(String.fromCharCode(rune));
      }
      expect(titles, ['🙂 café']);
      expect(terminal.buffer.lines[0].getText(), '你好');
      expect(_retainedInputRunes(parser), 0);
      expect(_retainedSequenceUnits(parser), 0);
    }
  });

  test('OSC limit counts encoded Unicode bytes and includes terminators', () {
    final titles = <String>[];
    final terminal = Terminal(onTitleChange: titles.add)..resize(80, 24);
    final parser = EscapeParser(terminal);
    final asciiLimit = 'x' * 8187;
    final unicodeLimit = '🙂' * 2046;
    parser.write('\x1b]2;$asciiLimit\x07');
    parser.write('\x1b]2;${asciiLimit}x\x07');
    parser.write('\x1b]2;$unicodeLimit\x07');
    parser.write('\x1b]2;$unicodeLimit🙂\x07');
    expect(titles, [asciiLimit, unicodeLimit]);
    expect(_retainedInputRunes(parser), 0);
    expect(_retainedSequenceUnits(parser), 0);
  });

  test('truncated extended color parameters do not interrupt later text', () {
    for (final sequence in ['38m', '38;2m', '48;5m', '48;2;1;2m']) {
      final terminal = Terminal()..resize(80, 24);
      final parser = EscapeParser(terminal);
      parser.write('\x1b[$sequence');
      parser.write('VISIBLE\x1b[0m');
      expect(terminal.buffer.lines[0].getText(), 'VISIBLE');
    }
  });

  test('split CSI and charset sequences retain normal rendered behavior', () {
    final terminal = _ObservedTerminal()..resize(80, 24);
    final parser = EscapeParser(terminal);
    for (final chunk in ['\x1b', '[2;', '3', 'H', '\x1b[', '1', 'm', '🙂']) {
      parser.write(chunk);
    }
    expect(terminal.buffer.lines[1].getText(), '🙂');
    expect(terminal.boldCalls, 1);
    parser.write('\x1b(');
    parser.write('0q');
    expect(terminal.buffer.lines[1].getText(), '🙂─');
    expect(_retainedInputRunes(parser), 0);
  });

  test('split RGB and indexed colors keep their complete parameters', () {
    final terminal = _ObservedTerminal()..resize(80, 24);
    final parser = EscapeParser(terminal);
    for (final rune in '\x1b[38;2;12;34;56m\x1b[48;5;123m'.runes) {
      parser.write(String.fromCharCode(rune));
    }
    expect(terminal.foregroundRgb, (12, 34, 56));
    expect(terminal.backgroundIndex, 123);
  });

  test('debugger token spans survive split sequences', () {
    final debugger = TerminalDebugger();
    debugger.write('\x1b[2;');
    debugger.write('3H');
    final command = debugger.commands.single;
    expect(command.start, 0);
    expect(command.end, 6);
    expect(command.chars, '\x1b[2;3H');
  });

  test(
    'a failed completed dispatch does not consume later text as control',
    () {
      final cases = [
        (
          terminal: Terminal(
            onTitleChange: (_) => throw StateError('callback'),
          ),
          control: '\x1b]2;title\x07',
        ),
        (terminal: _ObservedTerminal()..failBold = true, control: '\x1b[1m'),
        (terminal: _ObservedTerminal()..failSave = true, control: '\x1b7'),
      ];
      for (final entry in cases) {
        final terminal = entry.terminal..resize(80, 24);
        final parser = EscapeParser(terminal);
        expect(() => parser.write(entry.control), throwsStateError);
        expect(_retainedInputRunes(parser), 0);
        parser.write('VISIBLE');
        expect(terminal.buffer.lines[0].getText(), 'VISIBLE');
      }
    },
  );

  test('callback writes are queued after already received terminal output', () {
    late Terminal terminal;
    terminal = Terminal(onTitleChange: (_) => terminal.write('CALLBACK'))
      ..resize(80, 24);
    terminal.write('\x1b]2;title\x07AFTER');
    expect(terminal.buffer.lines[0].getText(), 'AFTERCALLBACK');
  });

  test('callback reentry followed by an error preserves queued output', () {
    late Terminal terminal;
    terminal = Terminal(
      onTitleChange: (_) {
        terminal.write('CALLBACK');
        throw StateError('callback');
      },
    )..resize(80, 24);
    expect(() => terminal.write('\x1b]2;title\x07AFTER'), throwsStateError);
    terminal.write('LATER');
    expect(terminal.buffer.lines[0].getText(), 'AFTERCALLBACKLATER');
  });

  test('ByteConsumer releases its final exhausted block immediately', () {
    final consumer = ByteConsumer()..add('x' * 65536);
    while (consumer.isNotEmpty) {
      consumer.consume();
    }
    consumer.unrefConsumedBlocks();
    expect(_retainedConsumerRunes(consumer), 0);
    consumer.add('🙂');
    expect(consumer.consume(), 0x1f642);
    consumer.unrefConsumedBlocks();
    expect(_retainedConsumerRunes(consumer), 0);
  });
}

class _ObservedTerminal extends Terminal {
  int boldCalls = 0;
  bool failBold = false;
  bool failSave = false;
  (int, int, int)? foregroundRgb;
  int? backgroundIndex;

  @override
  void setCursorBold() {
    if (failBold) throw StateError('bold callback');
    boldCalls++;
    super.setCursorBold();
  }

  @override
  void saveCursor() {
    if (failSave) throw StateError('save callback');
    super.saveCursor();
  }

  @override
  void setForegroundColorRgb(int r, int g, int b) {
    foregroundRgb = (r, g, b);
    super.setForegroundColorRgb(r, g, b);
  }

  @override
  void setBackgroundColor256(int index) {
    backgroundIndex = index;
    super.setBackgroundColor256(index);
  }
}

// Inspect resource ownership locally in the test without shipping diagnostics
// or counters in the vendored parser. This catches references to spent chunks,
// even when the parser reports zero unread characters.
dynamic _field(Object object, String name) {
  final reflected = reflect(object);
  final owner = reflected.type.owner as LibraryMirror;
  return reflected.getField(MirrorSystem.getSymbol(name, owner)).reflectee;
}

int _retainedInputRunes(EscapeParser parser) =>
    _retainedConsumerRunes(_field(parser, '_queue') as ByteConsumer);

int _retainedConsumerRunes(ByteConsumer consumer) {
  var retained = 0;
  for (final name in ['_queue', '_consumed']) {
    for (final block in _field(consumer, name) as Iterable) {
      retained += (block as List).length;
    }
  }
  return retained;
}

int _retainedSequenceUnits(EscapeParser parser) {
  var retained = 0;
  final instance = reflect(parser);
  for (final entry in instance.type.declarations.entries) {
    final declaration = entry.value;
    if (declaration is! VariableMirror || declaration.isStatic) continue;
    final value = instance.getField(entry.key).reflectee;
    if (value is StringBuffer) retained += value.length;
    if (value is List<String>) {
      retained += value.fold<int>(0, (total, text) => total + text.length);
    }
  }
  final csi = _field(parser, '_csi') as Object;
  retained += (_field(csi, 'params') as List).length;
  return retained;
}
