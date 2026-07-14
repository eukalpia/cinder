import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

class FirstWidget extends StatelessWidget {
  const FirstWidget();

  @override
  Widget build(BuildContext context) {
    return Text('FIRST');
  }
}

class SecondWidget extends StatelessWidget {
  const SecondWidget();

  @override
  Widget build(BuildContext context) {
    return Text('SECOND');
  }
}

void main() {
  test('Direct widget replacement in Column', () async {
    await testCinder('direct replacement', (tester) async {
      // Create a Column with FirstWidget
      await tester.pumpComponent(
        Column(children: [FirstWidget()]),
      );

      print('Initial state:');
      print(tester.renderToString(showBorders: false));
      expect(tester.terminalState, containsText('FIRST'));
      expect(tester.terminalState, isNot(containsText('SECOND')));

      // Replace with SecondWidget
      await tester.pumpComponent(
        Column(children: [SecondWidget()]),
      );

      print('\nAfter replacement:');
      print(tester.renderToString(showBorders: false));

      // Should only show SECOND
      expect(tester.terminalState, containsText('SECOND'));
      expect(tester.terminalState, isNot(containsText('FIRST')));
    });
  });

  test('Widget replacement via setState', () async {
    await testCinder('stateful replacement', (tester) async {
      bool showFirst = true;

      // Helper to build the column
      Widget buildColumn() {
        return Column(
          children: [
            showFirst ? FirstWidget() : SecondWidget(),
          ],
        );
      }

      // Initial state
      await tester.pumpComponent(buildColumn());

      print('Initial state (showFirst=true):');
      print(tester.renderToString(showBorders: false));
      expect(tester.terminalState, containsText('FIRST'));
      expect(tester.terminalState, isNot(containsText('SECOND')));

      // Change state
      showFirst = false;
      await tester.pumpComponent(buildColumn());

      print('\nAfter state change (showFirst=false):');
      print(tester.renderToString(showBorders: false));

      // Should only show SECOND
      expect(tester.terminalState, containsText('SECOND'));
      expect(tester.terminalState, isNot(containsText('FIRST')));
    });
  });
}
