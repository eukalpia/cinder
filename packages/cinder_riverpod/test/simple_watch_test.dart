import 'package:cinder/cinder.dart';
import 'package:cinder_riverpod/cinder_riverpod.dart';
import 'package:test/test.dart';

void main() {
  test('Basic watch functionality', () async {
    final counterProvider = StateProvider<int>((ref) => 0);

    await testCinder(
      'basic watch',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: _SimpleWatchWidget(counterProvider: counterProvider),
          ),
        );

        // Initial state
        expect(tester.terminalState, containsText('Count: 0'));

        // Manually trigger state change and rebuild
        // For now, we'll need manual setState since automatic rebuild isn't working yet
      },
      debugPrintAfterPump: true,
    );
  });
}

class _SimpleWatchWidget extends StatefulWidget {
  const _SimpleWatchWidget({required this.counterProvider});

  final StateProvider<int> counterProvider;

  @override
  State<_SimpleWatchWidget> createState() => _SimpleWatchWidgetState();
}

class _SimpleWatchWidgetState extends State<_SimpleWatchWidget> {
  @override
  Widget build(BuildContext context) {
    // Try to use watch
    final count = context.watch(widget.counterProvider);

    return Column(
      children: [
        Text('Count: $count'),
        KeyboardListener(
          onKeyEvent: (key) {
            if (key == LogicalKey.arrowUp) {
              context.read(widget.counterProvider.notifier).state++;
              // For testing: manually trigger rebuild since auto-rebuild isn't working
              setState(() {});
            }
            return false;
          },
          child: const Text('Press up to increment'),
        ),
      ],
    );
  }
}
