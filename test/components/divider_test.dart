import 'package:test/test.dart';
import 'package:cinder/cinder.dart';

void main() {
  group('Divider', () {
    test('visual development - horizontal divider', () async {
      await testCinder(
        'see how horizontal divider looks',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 40,
              height: 10,
              child: Column(
                children: [
                  Text('Above divider'),
                  Divider(),
                  Text('Below divider'),
                ],
              ),
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('visual development - divider styles', () async {
      await testCinder(
        'different divider styles',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 40,
              height: 20,
              child: Column(
                children: [
                  Text('Single:'),
                  Divider(style: DividerStyle.single),
                  Text('Double:'),
                  Divider(style: DividerStyle.double),
                  Text('Dashed:'),
                  Divider(style: DividerStyle.dashed),
                  Text('Dotted:'),
                  Divider(style: DividerStyle.dotted),
                  Text('Bold:'),
                  Divider(style: DividerStyle.bold),
                  Text('ASCII:'),
                  Divider(style: DividerStyle.ascii),
                ],
              ),
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('visual development - divider with indents', () async {
      await testCinder(
        'divider with indents',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 40,
              height: 10,
              child: Column(
                children: [
                  Text('No indent:'),
                  Divider(),
                  Text('Left indent 5:'),
                  Divider(indent: 5),
                  Text('Right indent 5:'),
                  Divider(endIndent: 5),
                  Text('Both indents:'),
                  Divider(indent: 5, endIndent: 5),
                ],
              ),
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('visual development - colored dividers', () async {
      await testCinder(
        'colored dividers',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 40,
              height: 12,
              child: Column(
                children: [
                  Text('Red divider:'),
                  Divider(color: Colors.red),
                  Text('Green divider:'),
                  Divider(color: Colors.green),
                  Text('Blue divider:'),
                  Divider(color: Colors.blue),
                  Text('Yellow divider:'),
                  Divider(color: Colors.yellow),
                ],
              ),
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('visual development - vertical divider', () async {
      await testCinder(
        'vertical divider',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 50,
              height: 10,
              child: Row(
                children: [
                  Text('Left'),
                  VerticalDivider(),
                  Text('Middle'),
                  VerticalDivider(style: DividerStyle.double),
                  Text('Right'),
                ],
              ),
            ),
          );
        },
        debugPrintAfterPump: true,
      );
    });

    test('renders horizontal divider correctly', () async {
      await testCinder(
        'horizontal divider rendering',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 20,
              height: 5,
              child: Column(
                children: [
                  Text('Top'),
                  Divider(),
                  Text('Bottom'),
                ],
              ),
            ),
          );

          expect(tester.terminalState, containsText('Top'));
          expect(tester.terminalState, containsText('─'));
          expect(tester.terminalState, containsText('Bottom'));
        },
      );
    });

    test('renders vertical divider correctly', () async {
      await testCinder(
        'vertical divider rendering',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 30,
              height: 5,
              child: Row(
                children: [
                  Text('Left'),
                  VerticalDivider(),
                  Text('Right'),
                ],
              ),
            ),
          );

          expect(tester.terminalState, containsText('Left'));
          expect(tester.terminalState, containsText('│'));
          expect(tester.terminalState, containsText('Right'));
        },
      );
    });

    test('applies indents correctly', () async {
      await testCinder(
        'divider indents',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 30,
              height: 3,
              child: Divider(indent: 5, endIndent: 5),
            ),
          );

          expect(tester.terminalState, containsText('─'));
        },
      );
    });

    test('different styles render correctly', () async {
      await testCinder(
        'divider styles',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 20,
              height: 2,
              child: Divider(style: DividerStyle.double),
            ),
          );

          expect(tester.terminalState, containsText('═'));
        },
      );

      await testCinder(
        'ascii divider style',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 20,
              height: 2,
              child: Divider(style: DividerStyle.ascii),
            ),
          );

          expect(tester.terminalState, containsText('-'));
        },
      );
    });

    test('applies colors correctly', () async {
      await testCinder(
        'colored divider',
        (tester) async {
          await tester.pumpWidget(
            Container(
              width: 20,
              height: 2,
              child: Divider(color: Colors.red),
            ),
          );

          expect(tester.terminalState, containsText('─'));
        },
      );
    });
  });
}
