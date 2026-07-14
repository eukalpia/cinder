import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

class WidgetA extends StatelessWidget {
  const WidgetA();

  @override
  Widget build(BuildContext context) {
    return Text('A');
  }
}

class WidgetB extends StatelessWidget {
  const WidgetB();

  @override
  Widget build(BuildContext context) {
    return Text('B');
  }
}

void main() {
  test('Column properly replaces StatelessWidget children', () async {
    await testCinder('stateless replacement', (tester) async {
      // Start with WidgetA
      await tester.pumpWidget(
        Column(children: [
          WidgetA(),
        ]),
      );

      expect(tester.terminalState, containsText('A'));
      expect(tester.terminalState, isNot(containsText('B')));

      // Replace with WidgetB
      await tester.pumpWidget(
        Column(children: [
          WidgetB(),
        ]),
      );

      // Should only show B, not A
      expect(tester.terminalState, containsText('B'));
      expect(tester.terminalState, isNot(containsText('A')));
    });
  });
}
