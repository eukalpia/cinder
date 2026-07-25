import 'package:test/test.dart';
import 'package:cinder/cinder.dart';

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
    return Column(
      children: [
        first ? FirstWidget() : SecondWidget(),
      ],
    );
  }
}

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

void main() {
  group('TUI Testing Framework', () {
    test('can debug render output', () async {
      await testCinder('debug output', (tester) async {
        await tester.pumpWidget(
          const ColumnBugDemo(),
        );

        // Get debug output
        final output = tester.renderToString(showBorders: true);
        print(output);
        await Future.delayed(Duration(milliseconds: 2000));
        await tester.pump();
        final output2 = tester.renderToString(showBorders: true);
        print(output2);

        // Verify that we only see "2" after the state change, not both "1" and "2"
        expect(tester.terminalState, containsText('2'));
        expect(tester.terminalState, isNot(containsText('1')));
      });
    });
  });
}
