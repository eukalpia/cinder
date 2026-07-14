import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

Widget _focusLabel(String label) {
  return Builder(
    builder: (context) {
      final focused = Focus.of(context).hasPrimaryFocus;
      return Text('$label:${focused ? 'focused' : 'idle'}');
    },
  );
}

void main() {
  test('FocusNode requestFocus updates primary focus and listeners', () async {
    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');
    var notifications = 0;
    first.addListener(() => notifications++);

    await testCinder('focus node request', (tester) async {
      await tester.pumpWidget(
        FocusScope(
          child: Row(
            children: [
              Focus(focusNode: first, child: _focusLabel('first')),
              Focus(focusNode: second, child: _focusLabel('second')),
            ],
          ),
        ),
      );

      first.requestFocus();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(first));
      expect(first.hasPrimaryFocus, isTrue);
      expect(notifications, greaterThan(0));
      expect(tester.terminalState, containsText('first:focused'));
    });

    first.dispose();
    second.dispose();
  });

  test('autofocus and tab traversal move primary focus', () async {
    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');

    await testCinder('focus traversal', (tester) async {
      await tester.pumpWidget(
        FocusScope(
          child: Row(
            children: [
              Focus(
                focusNode: first,
                autofocus: true,
                child: _focusLabel('first'),
              ),
              Focus(
                focusNode: second,
                child: _focusLabel('second'),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(first.hasPrimaryFocus, isTrue);
      expect(tester.terminalState, containsText('first:focused'));

      await tester.sendTab();
      expect(second.hasPrimaryFocus, isTrue);
      expect(tester.terminalState, containsText('second:focused'));

      await tester.sendKeyEvent(
        const KeyboardEvent(
          logicalKey: LogicalKey.tab,
          modifiers: ModifierKeys(shift: true),
        ),
      );
      expect(first.hasPrimaryFocus, isTrue);
    });

    first.dispose();
    second.dispose();
  });

  test('skipTraversal is skipped but explicit focus remains available',
      () async {
    final first = FocusNode(debugLabel: 'first');
    final skipped = FocusNode(debugLabel: 'skipped', skipTraversal: true);
    final last = FocusNode(debugLabel: 'last');

    await testCinder('skip traversal', (tester) async {
      await tester.pumpWidget(
        FocusScope(
          child: Row(
            children: [
              Focus(focusNode: first, autofocus: true, child: const Text('1')),
              Focus(focusNode: skipped, child: const Text('2')),
              Focus(focusNode: last, child: const Text('3')),
            ],
          ),
        ),
      );
      await tester.pump();

      await tester.sendTab();
      expect(last.hasPrimaryFocus, isTrue);

      skipped.requestFocus();
      await tester.pump();
      expect(skipped.hasPrimaryFocus, isTrue);
    });

    first.dispose();
    skipped.dispose();
    last.dispose();
  });

  test('scope autofocus restores its first traversable descendant', () async {
    final node = FocusNode(debugLabel: 'scoped child');

    await testCinder('scope autofocus', (tester) async {
      await tester.pumpWidget(
        FocusScope(
          autofocus: true,
          child: Focus(
            focusNode: node,
            child: _focusLabel('child'),
          ),
        ),
      );
      await tester.pump();

      expect(node.hasPrimaryFocus, isTrue);
      expect(tester.terminalState, containsText('child:focused'));
    });

    node.dispose();
  });
}
