import 'package:test/test.dart';
import 'package:cinder/cinder.dart';

class FirstWidget extends StatelessWidget {
  const FirstWidget();

  @override
  Widget build(BuildContext context) {
    return Text('1');
  }
}

class SecondWidget extends StatelessWidget {
  const SecondWidget();

  @override
  Widget build(BuildContext context) {
    return Text('2');
  }
}

// Example widget for testing
class ColumnBugDemo extends StatefulWidget {
  const ColumnBugDemo();

  @override
  State<ColumnBugDemo> createState() => _ColumnBugDemoState();
}

class _ColumnBugDemoState extends State<ColumnBugDemo> {
  bool first = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(seconds: 1), () {
      setState(() {
        first = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    print('Building with first=$first');
    return Column(
      children: [
        first ? FirstWidget() : SecondWidget(),
      ],
    );
  }
}

void main() {
  group('Column Bug Ternary', () {
    test('ternary column replacement', () async {
      await testCinder('debug output', (tester) async {
        await tester.pumpComponent(
          const ColumnBugDemo(),
        );

        print('Initial render:');
        final output = tester.renderToString(showBorders: false);
        print(output);
        expect(tester.terminalState, containsText('1'));
        expect(tester.terminalState, isNot(containsText('2')));

        await Future.delayed(Duration(milliseconds: 2000));
        await tester.pump();

        print('\nAfter state change:');
        final output2 = tester.renderToString(showBorders: false);
        print(output2);

        // We expect only "2" to be shown
        expect(tester.terminalState, containsText('2'));
        expect(tester.terminalState, isNot(containsText('1')));
      });
    });
  });
}
