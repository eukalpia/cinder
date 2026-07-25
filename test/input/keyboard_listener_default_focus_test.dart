import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('KeyboardListener receives keys by default', () async {
    var received = false;

    await testCinder('keyboard listener default focus', (tester) async {
      await tester.pumpWidget(
        KeyboardListener(
          onKeyEvent: (key) {
            if (key == LogicalKey.enter) {
              received = true;
              return true;
            }
            return false;
          },
          child: const Text('Ready'),
        ),
      );

      await tester.sendKey(LogicalKey.enter);
      await tester.pump();

      expect(received, isTrue);
    });
  });

  test('KeyboardListener can opt out of automatic focus', () async {
    var received = false;

    await testCinder('keyboard listener explicit focus opt-out',
        (tester) async {
      await tester.pumpWidget(
        KeyboardListener(
          autofocus: false,
          onKeyEvent: (_) {
            received = true;
            return true;
          },
          child: const Text('Inactive'),
        ),
      );

      await tester.sendKey(LogicalKey.enter);
      await tester.pump();

      expect(received, isFalse);
    });
  });
}
