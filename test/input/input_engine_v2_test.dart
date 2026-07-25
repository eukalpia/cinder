import 'package:cinder/cinder.dart';
import 'package:cinder/src/keyboard/input_parser.dart';
import 'package:test/test.dart';

void main() {
  group('InputParser ambiguity handling', () {
    test('waits for a split CSI sequence instead of emitting Escape', () {
      final parser = InputParser();
      parser.addBytes(const <int>[0x1B]);

      expect(parser.parseNext(), isNull);
      expect(parser.hasPendingEscape, isTrue);

      parser.addBytes(const <int>[0x5B, 0x41]);
      final event = parser.parseNext() as KeyboardInputEvent;
      expect(event.event.logicalKey, LogicalKey.arrowUp);
      expect(parser.hasPendingEscape, isFalse);
    });

    test('flushes a genuine standalone Escape after timeout ownership', () {
      final parser = InputParser()..addBytes(const <int>[0x1B]);

      final event = parser.flushPendingEscape();

      expect(event, isNotNull);
      expect(event!.event.logicalKey, LogicalKey.escape);
      expect(parser.bufferedByteCount, 0);
    });

    test('normalizes terminal focus reports', () {
      final parser = InputParser();

      final focusIn = parser.parseBytes('\x1b[I'.codeUnits);
      final focusOut = parser.parseBytes('\x1b[O'.codeUnits);

      expect(focusIn, isA<TerminalFocusInputEvent>());
      expect((focusIn! as TerminalFocusInputEvent).hasFocus, isTrue);
      expect(focusOut, isA<TerminalFocusInputEvent>());
      expect((focusOut! as TerminalFocusInputEvent).hasFocus, isFalse);
    });

    test('preserves kitty repeat and release lifecycle', () {
      final parser = InputParser();

      final repeat =
          parser.parseBytes('\x1b[97;1;2u'.codeUnits) as KeyboardInputEvent;
      final release =
          parser.parseBytes('\x1b[97;1;3u'.codeUnits) as KeyboardInputEvent;

      expect(repeat.event.type, KeyEventType.repeat);
      expect(release.event.type, KeyEventType.up);
    });

    test('bounds malformed unterminated input', () {
      final parser = InputParser(maxBufferedBytes: 8);
      parser.addBytes(const <int>[0x1B, 0x5B, 0x32]);

      expect(
        () => parser.addBytes(List<int>.filled(6, 0x30)),
        throwsFormatException,
      );
      expect(parser.bufferedByteCount, 0);
    });
  });

  group('InputRouter', () {
    test('dispatches capture, target, then reverse bubble order', () {
      final order = <String>[];
      final router = InputRouter(
        capture: <InputHandler>[
          (_, __) {
            order.add('capture-a');
            return InputDisposition.ignored;
          },
          (_, __) {
            order.add('capture-b');
            return InputDisposition.handled;
          },
        ],
        target: <InputHandler>[
          (_, __) {
            order.add('target');
            return InputDisposition.ignored;
          },
        ],
        bubble: <InputHandler>[
          (_, __) {
            order.add('bubble-root');
            return InputDisposition.ignored;
          },
          (_, __) {
            order.add('bubble-leaf');
            return InputDisposition.ignored;
          },
        ],
      );

      final result = router.route(const TextInputEvent('x'));

      expect(result, InputDisposition.handled);
      expect(order, <String>[
        'capture-a',
        'capture-b',
        'target',
        'bubble-leaf',
        'bubble-root',
      ]);
    });

    test('stopPropagation prevents later phases', () {
      var targetCalled = false;
      final router = InputRouter(
        capture: <InputHandler>[
          (_, __) => InputDisposition.stopPropagation,
        ],
        target: <InputHandler>[
          (_, __) {
            targetCalled = true;
            return InputDisposition.ignored;
          },
        ],
      );

      expect(
        router.route(const TextInputEvent('x')),
        InputDisposition.stopPropagation,
      );
      expect(targetCalled, isFalse);
    });
  });
}
