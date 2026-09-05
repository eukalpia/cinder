import 'dart:convert';

import 'package:cinder/cinder.dart';
import 'package:cinder/src/keyboard/input_parser.dart';
import 'package:test/test.dart';

void main() {
  test('batched CSI, SS3, Alt and text preserve every event in order', () {
    final parser = InputParser();
    parser.addBytes(utf8.encode('\x1b[A\x1bOP\x1b[5~\x1baz'));
    final events = <KeyboardEvent>[];
    InputEvent? event;
    while ((event = parser.parseNext()) != null) {
      events.add((event! as KeyboardInputEvent).event);
    }
    expect(events.map((event) => event.logicalKey), [
      LogicalKey.arrowUp,
      LogicalKey.f1,
      LogicalKey.pageUp,
      LogicalKey.keyA,
      LogicalKey.keyZ,
    ]);
    expect(events[3].isAltPressed, isTrue);
    expect(parser.bufferedByteCount, 0);
  });

  test('every split of a mixed burst produces the same keys', () {
    final bytes = utf8.encode('界\x1b[1;5D\x1bOQ\x1b[24~x');
    for (var split = 0; split <= bytes.length; split++) {
      final parser = InputParser();
      final events = <KeyboardEvent>[];
      void drain() {
        InputEvent? event;
        while ((event = parser.parseNext()) != null) {
          events.add((event! as KeyboardInputEvent).event);
        }
      }

      parser.addBytes(bytes.sublist(0, split));
      drain();
      parser.addBytes(bytes.sublist(split));
      drain();
      expect(events.map((event) => event.logicalKey), [
        LogicalKey.fromCharacter('界'),
        LogicalKey.arrowLeft,
        LogicalKey.f2,
        LogicalKey.f12,
        LogicalKey.keyX,
      ], reason: 'split at byte $split');
      expect(events[1].isControlPressed, isTrue);
      expect(parser.bufferedByteCount, 0);
    }
  });

  test('unknown CSI bursts do not recurse or discard the following key', () {
    final parser = InputParser();
    parser.addBytes(utf8.encode('${'\x1b[999~' * 20000}x'));
    expect((parser.parseNext() as KeyboardInputEvent).event.character, 'x');
    expect(parser.bufferedByteCount, 0);
  });

  test('a skipped-byte budget yields with subsequent keys still buffered', () {
    final parser = InputParser();
    parser.addBytes(utf8.encode('${'\x1b[2A' * 10000}x'));
    expect(parser.parseNext(maxSkippedBytes: 1024), isNull);
    expect(parser.bufferedByteCount, 40001 - 1024);
    expect((parser.parseNext() as KeyboardInputEvent).event.character, 'x');
    expect(parser.bufferedByteCount, 0);
  });
}
