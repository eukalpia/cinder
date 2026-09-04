import 'package:cinder/cinder.dart';
import 'package:cinder_provider/provider.dart';
import 'package:test/test.dart';

class _Counter extends ChangeNotifier {
  var count = 0;

  void increment() {
    count++;
    notifyListeners();
  }
}

class _Rebuildable extends StatefulWidget {
  const _Rebuildable({required this.builder});

  final Widget Function(BuildContext, StateSetter) builder;

  @override
  State<_Rebuildable> createState() => _RebuildableState();
}

class _RebuildableState extends State<_Rebuildable> {
  @override
  Widget build(BuildContext context) => widget.builder(context, setState);
}

class _Value extends StatelessWidget {
  const _Value();

  @override
  Widget build(BuildContext context) => Text('Value: ${context.watch<int>()}');
}

void main() {
  test(
    'ChangeNotifierProvider rebuilds consumers after notifications',
    () async {
      final counter = _Counter();
      addTearDown(counter.dispose);
      await testCinder('provider notifier updates', (tester) async {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: counter,
            child: Consumer<_Counter>(
              builder: (context, value, child) => Text('Count: ${value.count}'),
            ),
          ),
        );
        expect(tester.terminalState, containsText('Count: 0'));

        counter.increment();
        await tester.pump();

        expect(tester.terminalState, containsText('Count: 1'));
      });
    },
  );

  test(
    'Provider.value notifies an unchanged child when its value changes',
    () async {
      await testCinder('provider value updates', (tester) async {
        var value = 1;
        late StateSetter update;
        await tester.pumpWidget(
          _Rebuildable(
            builder: (context, setState) {
              update = setState;
              return Provider<int>.value(value: value, child: const _Value());
            },
          ),
        );
        expect(tester.terminalState, containsText('Value: 1'));

        update(() => value = 2);
        await tester.pump();

        expect(tester.terminalState, containsText('Value: 2'));
      });
    },
  );

  test(
    'ProxyProvider recomputes values after its dependency changes',
    () async {
      final counter = _Counter();
      addTearDown(counter.dispose);
      await testCinder('proxy provider updates', (tester) async {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: counter,
            child: ProxyProvider<_Counter, int>(
              update: (context, value, previous) => value.count * 2,
              child: const _Value(),
            ),
          ),
        );
        expect(tester.terminalState, containsText('Value: 0'));

        counter.increment();
        await tester.pump();

        expect(tester.terminalState, containsText('Value: 2'));
      });
    },
  );

  test('ProxyProvider recomputes when its update callback changes', () async {
    await testCinder('proxy provider callback updates', (tester) async {
      var value = 1;
      late StateSetter update;
      await tester.pumpWidget(
        _Rebuildable(
          builder: (context, setState) {
            update = setState;
            return ProxyProvider0<int>(
              update: (context, previous) => value,
              child: const _Value(),
            );
          },
        ),
      );
      expect(tester.terminalState, containsText('Value: 1'));

      update(() => value = 2);
      await tester.pump();

      expect(tester.terminalState, containsText('Value: 2'));
    });
  });
}
