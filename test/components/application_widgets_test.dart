import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('Dialog, menu and state widgets render coherently', () async {
    await testCinder('application widgets', (tester) async {
      await tester.pumpWidget(
        Column(
          children: <Widget>[
            AlertDialog(
              title: 'Confirm',
              message: 'Continue deployment?',
              actions: <Widget>[
                Button.text('Cancel', onPressed: () {}),
                Button.text('Deploy', onPressed: () {}),
              ],
            ),
            const EmptyState(
              title: 'No incidents',
              description: 'Everything is healthy.',
            ),
          ],
        ),
      );
      expect(tester.terminalState, containsText('Confirm'));
      expect(tester.terminalState, containsText('Continue deployment?'));
      expect(tester.terminalState, containsText('No incidents'));
    });
  });

  test('Menu activates its first item from the keyboard', () async {
    var activated = false;
    await testCinder('menu activation', (tester) async {
      await tester.pumpWidget(
        Menu(
          items: <MenuItem>[
            MenuItem(label: 'Open', onSelected: () => activated = true),
            const MenuItem(label: 'Disabled'),
          ],
        ),
      );
      await tester.sendKey(LogicalKey.enter);
      expect(activated, isTrue);
    });
  });
}
