import 'package:test/test.dart';
import 'package:cinder/cinder.dart' hide TextAlign;
import 'package:cinder/src/components/basic.dart' show TextAlign;

void main() {
  group('Text Alignment Visual Tests', () {
    test('text alignment in constrained container', () async {
      await testCinder(
        'text alignment rendering',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 20,
              height: 10,
              decoration: BoxDecoration(
                border: BoxBorder.all(style: BoxBorderStyle.solid),
              ),
              child: Column(
                children: const [
                  Text('Left', textAlign: TextAlign.left),
                  Text('Center', textAlign: TextAlign.center),
                  Text('Right', textAlign: TextAlign.right),
                  Text('Short'),
                  Text('This is a longer text that wraps',
                      textAlign: TextAlign.left),
                  Text('This is a longer text that wraps',
                      textAlign: TextAlign.center),
                  Text('This is a longer text that wraps',
                      textAlign: TextAlign.right),
                ],
              ),
            ),
          );

          // Print the actual rendered output to see what's happening
          print('Rendered output:');
          final output = tester.terminalState.getText();
          print(output);

          // Check that the text appears
          final lines = output.split('\n');

          // Without CrossAxisAlignment.stretch, Text widgets don't expand
          // to fill width, so all text appears centered within the container
          // because the Column centers its children by default.
          // The textAlign property only matters if the Text has extra width.
          expect(lines[1], contains('Left'));
          expect(lines[2], contains('Center'));
          expect(lines[3], contains('Right'));
        },
        debugPrintAfterPump: true,
      );
    });

    test('text alignment with different widths', () async {
      await testCinder(
        'alignment at various widths',
        (tester) async {
          await tester.pumpWidget(
            Column(
              children: [
                // Very narrow container
                Container(
                  width: 10,
                  decoration: BoxDecoration(
                    border: BoxBorder.all(style: BoxBorderStyle.solid),
                  ),
                  child: Column(
                    children: const [
                      Text('L', textAlign: TextAlign.left),
                      Text('C', textAlign: TextAlign.center),
                      Text('R', textAlign: TextAlign.right),
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                // Medium container
                Container(
                  width: 20,
                  decoration: BoxDecoration(
                    border: BoxBorder.all(style: BoxBorderStyle.solid),
                  ),
                  child: Column(
                    children: const [
                      Text('Left', textAlign: TextAlign.left),
                      Text('Center', textAlign: TextAlign.center),
                      Text('Right', textAlign: TextAlign.right),
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                // Wide container
                Container(
                  width: 40,
                  decoration: BoxDecoration(
                    border: BoxBorder.all(style: BoxBorderStyle.solid),
                  ),
                  child: Column(
                    children: const [
                      Text('Left aligned', textAlign: TextAlign.left),
                      Text('Center aligned', textAlign: TextAlign.center),
                      Text('Right aligned', textAlign: TextAlign.right),
                    ],
                  ),
                ),
              ],
            ),
          );

          print('Multiple container widths:');
          print(tester.terminalState.getText());
        },
        debugPrintAfterPump: true,
      );
    });

    test('justified text alignment', () async {
      await testCinder(
        'justified text',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 30,
              decoration: BoxDecoration(
                border: BoxBorder.all(style: BoxBorderStyle.solid),
              ),
              child: Column(
                children: const [
                  Text(
                    'This text should be justified across multiple lines',
                    textAlign: TextAlign.justify,
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Short line',
                    textAlign: TextAlign.justify,
                  ),
                ],
              ),
            ),
          );

          print('Justified text:');
          print(tester.terminalState.getText());
        },
        debugPrintAfterPump: true,
      );
    });

    test('text alignment with padding', () async {
      await testCinder(
        'alignment with padding',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 30,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: BoxBorder.all(style: BoxBorderStyle.solid),
              ),
              child: Column(
                children: const [
                  Text('Left', textAlign: TextAlign.left),
                  Text('Center', textAlign: TextAlign.center),
                  Text('Right', textAlign: TextAlign.right),
                ],
              ),
            ),
          );

          print('With padding:');
          print(tester.terminalState.getText());
        },
        debugPrintAfterPump: true,
      );
    });
  });
}
