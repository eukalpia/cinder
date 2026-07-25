import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('SIGINT (Ctrl+C) handling', () {
    test('widget can intercept Ctrl+C', () async {
      bool ctrlCReceived = false;

      await testCinder(
        'intercept ctrl+c',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: true,
              onKeyEvent: (event) {
                if (event.matches(LogicalKey.keyC, ctrl: true)) {
                  ctrlCReceived = true;
                  return true; // Handle it
                }
                return false;
              },
              child: const Text('App'),
            ),
          );

          // Simulate Ctrl+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );

          expect(ctrlCReceived, isTrue);
        },
      );
    });

    test('unhandled Ctrl+C should trigger shutdown', () async {
      // This test verifies the event is created but not handled
      bool ctrlCReceived = false;

      await testCinder(
        'fallback to shutdown',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: true,
              onKeyEvent: (event) {
                if (event.matches(LogicalKey.keyC, ctrl: true)) {
                  ctrlCReceived = true;
                  return false; // Don't handle - should trigger shutdown
                }
                return false;
              },
              child: const Text('App'),
            ),
          );

          // Simulate Ctrl+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );

          expect(ctrlCReceived, isTrue);
        },
      );
    });

    test('Ctrl+C has correct event properties', () async {
      KeyboardEvent? receivedEvent;

      await testCinder(
        'event properties',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: true,
              onKeyEvent: (event) {
                if (event.matches(LogicalKey.keyC, ctrl: true)) {
                  receivedEvent = event;
                  return true;
                }
                return false;
              },
              child: const Text('App'),
            ),
          );

          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );

          expect(receivedEvent, isNotNull);
          expect(receivedEvent!.logicalKey, equals(LogicalKey.keyC));
          expect(receivedEvent!.modifiers.ctrl, isTrue);
          expect(receivedEvent!.modifiers.shift, isFalse);
          expect(receivedEvent!.modifiers.alt, isFalse);
        },
      );
    });

    test('only focused widget receives Ctrl+C', () async {
      bool focusedReceived = false;
      bool unfocusedReceived = false;

      await testCinder(
        'focus respects routing',
        (tester) async {
          await tester.pumpWidget(
            Column(
              children: [
                Focusable(
                  focused: true,
                  onKeyEvent: (event) {
                    if (event.matches(LogicalKey.keyC, ctrl: true)) {
                      focusedReceived = true;
                      return true;
                    }
                    return false;
                  },
                  child: const Text('Focused'),
                ),
                Focusable(
                  focused: false,
                  onKeyEvent: (event) {
                    if (event.matches(LogicalKey.keyC, ctrl: true)) {
                      unfocusedReceived = true;
                      return true;
                    }
                    return false;
                  },
                  child: const Text('Unfocused'),
                ),
              ],
            ),
          );

          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );

          expect(focusedReceived, isTrue);
          expect(unfocusedReceived, isFalse);
        },
      );
    });

    test('child can prevent parent from seeing Ctrl+C', () async {
      bool childReceived = false;
      bool parentReceived = false;

      await testCinder(
        'event bubbling',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: true,
              onKeyEvent: (event) {
                if (event.matches(LogicalKey.keyC, ctrl: true)) {
                  parentReceived = true;
                  return true;
                }
                return false;
              },
              child: Focusable(
                focused: true,
                onKeyEvent: (event) {
                  if (event.matches(LogicalKey.keyC, ctrl: true)) {
                    childReceived = true;
                    return true; // Handle it, parent won't see
                  }
                  return false;
                },
                child: const Text('Child'),
              ),
            ),
          );

          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );

          expect(childReceived, isTrue);
          expect(parentReceived, isFalse); // Child handled it
        },
      );
    });

    test('press twice pattern works', () async {
      int ctrlCCount = 0;

      await testCinder(
        'press twice pattern',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: true,
              onKeyEvent: (event) {
                if (event.matches(LogicalKey.keyC, ctrl: true)) {
                  ctrlCCount++;
                  return true;
                }
                // Reset on other keys
                ctrlCCount = 0;
                return false;
              },
              child: const Text('App'),
            ),
          );

          // First Ctrl+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );
          expect(ctrlCCount, equals(1));

          // Second Ctrl+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );
          expect(ctrlCCount, equals(2));
        },
      );
    });

    test('counter resets on other key press', () async {
      int ctrlCCount = 0;

      await testCinder(
        'counter reset',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: true,
              onKeyEvent: (event) {
                if (event.matches(LogicalKey.keyC, ctrl: true)) {
                  ctrlCCount++;
                  return true;
                }
                // Reset on other keys
                ctrlCCount = 0;
                return false;
              },
              child: const Text('App'),
            ),
          );

          // First Ctrl+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );
          expect(ctrlCCount, equals(1));

          // Press another key
          await tester.sendKey(LogicalKey.keyA);
          expect(ctrlCCount, equals(0)); // Reset

          // Ctrl+C again - should be 1, not 2
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );
          expect(ctrlCCount, equals(1));
        },
      );
    });

    test('Ctrl+C without ctrl modifier is just regular C', () async {
      bool ctrlCReceived = false;
      bool regularCReceived = false;

      await testCinder(
        'distinguish ctrl+c from c',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: true,
              onKeyEvent: (event) {
                if (event.matches(LogicalKey.keyC, ctrl: true)) {
                  ctrlCReceived = true;
                  return true;
                }
                if (event.logicalKey == LogicalKey.keyC) {
                  regularCReceived = true;
                  return true;
                }
                return false;
              },
              child: const Text('App'),
            ),
          );

          // Send regular C
          await tester.sendKey(LogicalKey.keyC);
          expect(regularCReceived, isTrue);
          expect(ctrlCReceived, isFalse);

          // Reset
          regularCReceived = false;
          ctrlCReceived = false;

          // Send Ctrl+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );
          expect(ctrlCReceived, isTrue);
          expect(regularCReceived, isFalse);
        },
      );
    });

    test('nested focused components - child handles before parent', () async {
      final List<String> handlerOrder = [];

      await testCinder(
        'handler precedence',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: true,
              onKeyEvent: (event) {
                if (event.matches(LogicalKey.keyC, ctrl: true)) {
                  handlerOrder.add('parent');
                  return false; // Don't handle, let it bubble
                }
                return false;
              },
              child: Focusable(
                focused: true,
                onKeyEvent: (event) {
                  if (event.matches(LogicalKey.keyC, ctrl: true)) {
                    handlerOrder.add('child');
                    return false; // Don't handle, let it bubble
                  }
                  return false;
                },
                child: const Text('Nested'),
              ),
            ),
          );

          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );

          // Child should be called before parent due to depth-first dispatch
          expect(handlerOrder, equals(['child', 'parent']));
        },
      );
    });

    test('multiple modifiers with Ctrl+C', () async {
      KeyboardEvent? receivedEvent;

      await testCinder(
        'ctrl+shift+c',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: true,
              onKeyEvent: (event) {
                if (event.logicalKey == LogicalKey.keyC) {
                  receivedEvent = event;
                  return true;
                }
                return false;
              },
              child: const Text('App'),
            ),
          );

          // Send Ctrl+Shift+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true, shift: true),
            ),
          );

          expect(receivedEvent, isNotNull);
          expect(receivedEvent!.logicalKey, equals(LogicalKey.keyC));
          expect(receivedEvent!.modifiers.ctrl, isTrue);
          expect(receivedEvent!.modifiers.shift, isTrue);
          expect(receivedEvent!.modifiers.alt, isFalse);

          // Verify matches works with partial modifier matching
          expect(receivedEvent!.matches(LogicalKey.keyC, ctrl: true), isTrue);
          expect(
              receivedEvent!.matches(LogicalKey.keyC, ctrl: true, shift: true),
              isTrue);
        },
      );
    });

    test('stateful widget with Ctrl+C counter', () async {
      await testCinder(
        'stateful counter',
        (tester) async {
          // Create a simple stateful widget
          await tester.pumpWidget(
            const _CounterApp(),
          );

          // Initial state
          expect(tester.terminalState, containsText('Count: 0'));

          // First Ctrl+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );
          expect(tester.terminalState, containsText('Count: 1'));

          // Second Ctrl+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );
          expect(tester.terminalState, containsText('Count: 2'));

          // Press another key to reset
          await tester.sendKey(LogicalKey.keyA);
          expect(tester.terminalState, containsText('Count: 0'));
        },
      );
    });

    test('Ctrl+C in unfocused widget should not be handled', () async {
      bool unfocusedHandlerCalled = false;

      await testCinder(
        'unfocused no handling',
        (tester) async {
          await tester.pumpWidget(
            Focusable(
              focused: false, // Not focused
              onKeyEvent: (event) {
                if (event.matches(LogicalKey.keyC, ctrl: true)) {
                  unfocusedHandlerCalled = true;
                  return true;
                }
                return false;
              },
              child: const Text('Unfocused App'),
            ),
          );

          // Send Ctrl+C
          await tester.sendKeyEvent(
            KeyboardEvent(
              logicalKey: LogicalKey.keyC,
              modifiers: const ModifierKeys(ctrl: true),
            ),
          );

          // Handler should not be called because widget is not focused
          expect(unfocusedHandlerCalled, isFalse);
        },
      );
    });
  });
}

/// Simple stateful widget for testing Ctrl+C counter pattern
class _CounterApp extends StatefulWidget {
  const _CounterApp();

  @override
  State<_CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<_CounterApp> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (event.matches(LogicalKey.keyC, ctrl: true)) {
          setState(() {
            _count++;
          });
          return true;
        }
        // Reset on other keys
        setState(() {
          _count = 0;
        });
        return false;
      },
      child: Text('Count: $_count'),
    );
  }
}
