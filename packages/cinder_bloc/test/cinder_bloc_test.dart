import 'package:cinder/cinder.dart';
import 'package:cinder_bloc/cinder_bloc.dart';
import 'package:test/test.dart';

class CounterCubit extends Cubit<int> {
  CounterCubit() : super(0);

  void increment() => emit(state + 1);
}

void main() {
  test('BlocProvider and BlocBuilder rebuild on cubit changes', () async {
    await testCinder('cinder bloc counter', (tester) async {
      await tester.pumpWidget(
        BlocProvider<CounterCubit>(
          create: (_) => CounterCubit(),
          child: BlocBuilder<CounterCubit, int>(
            builder: (context, count) {
              return Column(
                children: [
                  Text('Count: $count'),
                  KeyboardListener(
                    onKeyEvent: (event) {
                      if (event == LogicalKey.arrowUp) {
                        context.read<CounterCubit>().increment();
                      }
                      return false;
                    },
                    child: const Text('Press up'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      expect(tester.terminalState, containsText('Count: 0'));

      await tester.sendKey(LogicalKey.arrowUp);
      await tester.pump();

      expect(tester.terminalState, containsText('Count: 1'));
    });
  });

  test('BlocSelector rebuilds selected state', () async {
    await testCinder('cinder bloc selector', (tester) async {
      await tester.pumpWidget(
        BlocProvider<CounterCubit>(
          create: (_) => CounterCubit(),
          child: BlocSelector<CounterCubit, int, bool>(
            selector: (state) => state.isEven,
            builder: (context, isEven) {
              return Column(
                children: [
                  Text(isEven ? 'Even' : 'Odd'),
                  KeyboardListener(
                    onKeyEvent: (event) {
                      if (event == LogicalKey.arrowUp) {
                        context.read<CounterCubit>().increment();
                      }
                      return false;
                    },
                    child: const Text('Press up'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      expect(tester.terminalState, containsText('Even'));
      await tester.sendKey(LogicalKey.arrowUp);
      await tester.pump();
      expect(tester.terminalState, containsText('Odd'));
    });
  });
}
