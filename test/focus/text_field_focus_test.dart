import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('TextField autofocus, traversal, and explicit focus use FocusNode',
      () async {
    final firstNode = FocusNode(debugLabel: 'first text field');
    final secondNode = FocusNode(debugLabel: 'second text field');
    final firstController = TextEditingController();
    final secondController = TextEditingController();
    final focusChanges = <String>[];

    await testCinder('text field focus nodes', (tester) async {
      await tester.pumpWidget(
        FocusScope(
          child: Column(
            children: [
              TextField(
                focusNode: firstNode,
                autofocus: true,
                controller: firstController,
                onFocusChange: (focused) {
                  focusChanges.add('first:$focused');
                },
              ),
              TextField(
                focusNode: secondNode,
                controller: secondController,
                onFocusChange: (focused) {
                  focusChanges.add('second:$focused');
                },
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(firstNode.hasPrimaryFocus, isTrue);
      await tester.enterText('A');
      expect(firstController.text, 'A');
      expect(secondController.text, '');

      await tester.sendTab();
      expect(secondNode.hasPrimaryFocus, isTrue);
      await tester.enterText('B');
      expect(firstController.text, 'A');
      expect(secondController.text, 'B');

      firstNode.requestFocus();
      await tester.pump();
      expect(firstNode.hasPrimaryFocus, isTrue);
      expect(
          focusChanges,
          containsAll(<String>[
            'first:true',
            'first:false',
            'second:true',
          ]));
    });

    firstNode.dispose();
    secondNode.dispose();
    firstController.dispose();
    secondController.dispose();
  });
}
