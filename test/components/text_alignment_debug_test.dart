import 'package:test/test.dart';
import 'package:cinder/cinder.dart' hide TextAlign;
import 'package:cinder/src/components/basic.dart' show TextAlign;

void main() {
  group('Text Alignment Debug', () {
    test('debug constraints passing', () async {
      await testCinder(
        'constraints debug',
        (tester) async {
          // Simple case - Text directly in a Container
          await tester.pumpWidget(
            Container(
              width: 30,
              height: 5,
              decoration: BoxDecoration(
                border: BoxBorder.all(style: BoxBorderStyle.solid),
              ),
              child: const Text(
                'Direct in container',
                textAlign: TextAlign.center,
              ),
            ),
          );

          print('Direct in container:');
          print(tester.terminalState.getText());

          // Text in Column in Container
          await tester.pumpWidget(
            Container(
              width: 30,
              height: 5,
              decoration: BoxDecoration(
                border: BoxBorder.all(style: BoxBorderStyle.solid),
              ),
              child: Column(
                children: const [
                  Text(
                    'In Column',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );

          print('\nIn Column:');
          print(tester.terminalState.getText());

          // Text in Column with crossAxisAlignment
          await tester.pumpWidget(
            Container(
              width: 30,
              height: 5,
              decoration: BoxDecoration(
                border: BoxBorder.all(style: BoxBorderStyle.solid),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  Text(
                    'With stretch',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );

          print('\nWith CrossAxisAlignment.stretch:');
          print(tester.terminalState.getText());
        },
        debugPrintAfterPump: false,
      );
    });
  });
}
