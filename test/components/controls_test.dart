import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('Button activates with Enter when focused', () async {
    var presses = 0;
    await testCinder('button keyboard activation', (tester) async {
      await tester.pumpWidget(
        Button.text(
          'Run',
          autofocus: true,
          onPressed: () => presses++,
        ),
      );
      await tester.sendKey(LogicalKey.enter);
      expect(presses, 1);
      expect(tester.terminalState, containsText('Run'));
    });
  });

  test('Checkbox and Switch respond to keyboard activation', () async {
    bool? checked = false;
    var switched = false;
    final first = FocusNode(debugLabel: 'checkbox');
    final second = FocusNode(debugLabel: 'switch');

    await testCinder('toggle controls', (tester) async {
      await tester.pumpWidget(
        Row(
          children: <Widget>[
            Checkbox(
              value: checked,
              focusNode: first,
              autofocus: true,
              onChanged: (value) => checked = value,
              label: const Text('Check'),
            ),
            const SizedBox(width: 2),
            Switch(
              value: switched,
              focusNode: second,
              onChanged: (value) => switched = value,
              label: const Text('Power'),
            ),
          ],
        ),
      );
      await tester.sendKey(LogicalKey.space);
      expect(checked, isTrue);
      await tester.sendTab();
      await tester.sendKey(LogicalKey.enter);
      expect(switched, isTrue);
    });

    first.dispose();
    second.dispose();
  });
}
