import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  late CinderTestBinding binding;

  setUp(() {
    binding = CinderTestBinding();
  });

  tearDown(() => binding.shutdown());

  test('pumpAndSettle returns after one idle frame', () async {
    binding.attachRootWidget(const Text('Ready'));
    await binding.pump();

    await binding.pumpAndSettle(Duration.zero, 1);

    expect(binding.frameCount, 2);
    expect(binding.hasScheduledFrame, isFalse);
  });

  test(
    'pumpAndSettle renders updates scheduled by post-frame callbacks',
    () async {
      final key = GlobalKey<_CounterState>();
      binding.attachRootWidget(_Counter(key: key));
      await binding.pump();

      void incrementAfterFrame(Duration _) {
        key.currentState!.increment();
        if (key.currentState!.value < 2) {
          binding.addPostFrameCallback(incrementAfterFrame);
        }
      }

      binding.addPostFrameCallback(incrementAfterFrame);
      await binding.pumpAndSettle(Duration.zero, 5);

      expect(
        TerminalState(buffer: binding.lastBuffer!, size: binding.size),
        containsText('Count: 2'),
      );
      expect(binding.hasScheduledFrame, isFalse);
    },
  );

  test('pumpAndSettle accepts completion on the final allowed frame', () async {
    var callbacks = 0;
    void runFrame(Duration _) {
      callbacks++;
      if (callbacks < 3) binding.scheduleFrameCallback(runFrame);
    }

    binding.scheduleFrameCallback(runFrame);
    await binding.pumpAndSettle(Duration.zero, 3);

    expect(callbacks, 3);
    expect(binding.hasScheduledFrame, isFalse);
  });

  test(
    'pumpAndSettle stops continuously scheduled frames at its limit',
    () async {
      binding.addPersistentFrameCallback((_) => binding.scheduleFrame());

      await expectLater(
        binding.pumpAndSettle(Duration.zero, 3),
        throwsStateError,
      );

      expect(binding.frameCount, 3);
    },
  );
}

class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int value = 0;

  void increment() => setState(() => value++);

  @override
  Widget build(BuildContext context) => Text('Count: $value');
}
