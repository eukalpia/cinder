import 'package:cinder/cinder.dart';
import 'package:cinder_riverpod/cinder_riverpod.dart';
import 'package:test/test.dart';

// Test providers
final counterProvider = StateProvider<int>((ref) => 0);

final greetingProvider = Provider<String>((ref) {
  final count = ref.watch(counterProvider);
  return 'Count: $count';
});

// Use StateNotifier instead of ChangeNotifier
class CounterNotifier extends StateNotifier<int> {
  CounterNotifier() : super(0);

  void increment() => state++;
  void decrement() => state--;
}

final counterNotifierProvider = StateNotifierProvider<CounterNotifier, int>(
  (ref) => CounterNotifier(),
);

// Test components
class CounterDisplay extends StatelessWidget {
  const CounterDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch(counterProvider);
    return Text('Counter: $count');
  }
}

class CounterControls extends StatelessWidget {
  const CounterControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('Controls'),
        // In a real app, these would be buttons
        Text('[+] Increment'),
        Text('[-] Decrement'),
      ],
    );
  }
}

class GreetingDisplay extends StatelessWidget {
  const GreetingDisplay({super.key});

  @override
  Widget build(BuildContext context) {
    final greeting = context.watch(greetingProvider);
    return Text(greeting);
  }
}

class StateNotifierCounter extends StatelessWidget {
  const StateNotifierCounter({super.key});

  @override
  Widget build(BuildContext context) {
    final count = context.watch(counterNotifierProvider);
    return Text('StateNotifier Count: $count');
  }
}

class ListenerWidget extends StatefulWidget {
  const ListenerWidget({super.key});

  @override
  State<ListenerWidget> createState() => _ListenerWidgetState();
}

class _ListenerWidgetState extends State<ListenerWidget> {
  String _lastChange = 'No changes yet';

  @override
  void initState() {
    super.initState();
    // Listen to counter changes
    context.listen<int>(counterProvider, (previous, next) {
      setState(() {
        _lastChange = 'Changed from ${previous ?? "null"} to $next';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(_lastChange);
  }
}

// Builder-like widget for cinder
class SimpleBuilder extends StatelessWidget {
  const SimpleBuilder({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return builder(context);
  }
}

void main() {
  group('cinder_riverpod', () {
    test('ProviderScope provides container to descendants', () async {
      await testCinder(
        'provider scope basic',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: SimpleBuilder(
                builder: (context) {
                  // Should be able to read providers
                  final value = context.read(counterProvider);
                  return Text('Value: $value');
                },
              ),
            ),
          );

          expect(tester.terminalState, containsText('Value: 0'));
        },
      );
    });

    test('watch triggers rebuilds', () async {
      await testCinder(
        'watch rebuilds',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: Column(
                children: [
                  const CounterDisplay(),
                  SimpleBuilder(
                    builder: (context) {
                      return KeyboardListener(
                        onKeyEvent: (key) {
                          if (key == LogicalKey.arrowUp) {
                            context.read(counterProvider.notifier).state++;
                          } else if (key == LogicalKey.arrowDown) {
                            context.read(counterProvider.notifier).state--;
                          }
                          return false;
                        },
                        child: const Text('Use arrows to change'),
                      );
                    },
                  ),
                ],
              ),
            ),
          );

          // Initial state
          expect(tester.terminalState, containsText('Counter: 0'));

          // Increment
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState, containsText('Counter: 1'));

          // Increment again
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState, containsText('Counter: 2'));

          // Decrement
          await tester.sendKey(LogicalKey.arrowDown);
          await tester.pump();
          expect(tester.terminalState, containsText('Counter: 1'));
        },
      );
    });

    test('computed providers update when dependencies change', () async {
      await testCinder(
        'computed providers',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: Column(
                children: [
                  const GreetingDisplay(),
                  SimpleBuilder(
                    builder: (context) {
                      return KeyboardListener(
                        onKeyEvent: (key) {
                          if (key == LogicalKey.arrowUp) {
                            context.read(counterProvider.notifier).state++;
                          }
                          return false;
                        },
                        child: const Text('Press up to increment'),
                      );
                    },
                  ),
                ],
              ),
            ),
          );

          // Initial state
          expect(tester.terminalState, containsText('Count: 0'));

          // Increment counter
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState, containsText('Count: 1'));

          // Increment again
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState, containsText('Count: 2'));
        },
      );
    });

    test('StateNotifierProvider works correctly', () async {
      await testCinder(
        'state notifier provider',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: Column(
                children: [
                  const StateNotifierCounter(),
                  SimpleBuilder(
                    builder: (context) {
                      return KeyboardListener(
                        onKeyEvent: (key) {
                          final notifier =
                              context.read(counterNotifierProvider.notifier);
                          if (key == LogicalKey.arrowUp) {
                            notifier.increment();
                          } else if (key == LogicalKey.arrowDown) {
                            notifier.decrement();
                          }
                          return false;
                        },
                        child: const Text('Use arrows to change'),
                      );
                    },
                  ),
                ],
              ),
            ),
          );

          // Initial state
          expect(tester.terminalState, containsText('StateNotifier Count: 0'));

          // Increment
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState, containsText('StateNotifier Count: 1'));

          // Increment again
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState, containsText('StateNotifier Count: 2'));

          // Decrement
          await tester.sendKey(LogicalKey.arrowDown);
          await tester.pump();
          expect(tester.terminalState, containsText('StateNotifier Count: 1'));
        },
      );
    });

    test('listen receives updates', () async {
      await testCinder(
        'listen updates',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: Column(
                children: [
                  const ListenerWidget(),
                  SimpleBuilder(
                    builder: (context) {
                      return KeyboardListener(
                        onKeyEvent: (key) {
                          if (key == LogicalKey.arrowUp) {
                            context.read(counterProvider.notifier).state++;
                          }
                          return false;
                        },
                        child: const Text('Press up to increment'),
                      );
                    },
                  ),
                ],
              ),
            ),
          );

          // Initial state
          expect(tester.terminalState, containsText('No changes yet'));

          // Trigger change
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState, containsText('Changed from 0 to 1'));

          // Another change
          await tester.sendKey(LogicalKey.arrowUp);
          await tester.pump();
          expect(tester.terminalState, containsText('Changed from 1 to 2'));
        },
      );
    });

    test('provider overrides work', () async {
      await testCinder(
        'provider overrides',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                counterProvider.overrideWith((ref) => 42),
              ],
              child: const CounterDisplay(),
            ),
          );

          // Should show overridden value
          expect(tester.terminalState, containsText('Counter: 42'));
        },
      );
    });

    test('nested ProviderScopes work', () async {
      await testCinder(
        'nested scopes',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: Column(
                children: [
                  const CounterDisplay(),
                  ProviderScope(
                    overrides: [
                      counterProvider.overrideWith((ref) => 100),
                    ],
                    child: const CounterDisplay(),
                  ),
                ],
              ),
            ),
          );

          // Both values should be present
          expect(tester.terminalState, containsText('Counter: 0'));
          expect(tester.terminalState, containsText('Counter: 100'));
        },
      );
    });

    test('refresh works correctly', () async {
      int refreshCount = 0;
      final refreshableProvider = Provider<int>((ref) {
        return ++refreshCount;
      });

      await testCinder(
        'refresh provider',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: SimpleBuilder(
                builder: (context) {
                  final value = context.watch(refreshableProvider);
                  return Column(
                    children: [
                      Text('Refresh count: $value'),
                      KeyboardListener(
                        onKeyEvent: (key) {
                          if (key == LogicalKey.enter) {
                            context.refresh(refreshableProvider);
                          }
                          return false;
                        },
                        child: const Text('Press Enter to refresh'),
                      ),
                    ],
                  );
                },
              ),
            ),
          );

          // Initial state
          expect(tester.terminalState, containsText('Refresh count: 1'));

          // Refresh
          await tester.sendKey(LogicalKey.enter);
          await tester.pump();
          expect(tester.terminalState, containsText('Refresh count: 2'));

          // Refresh again
          await tester.sendKey(LogicalKey.enter);
          await tester.pump();
          expect(tester.terminalState, containsText('Refresh count: 3'));
        },
      );
    });

    test('invalidate works correctly', () async {
      int buildCount = 0;
      final invalidatableProvider = Provider<int>((ref) {
        return ++buildCount;
      });

      await testCinder(
        'invalidate provider',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: SimpleBuilder(
                builder: (context) {
                  final value = context.watch(invalidatableProvider);
                  return Column(
                    children: [
                      Text('Build count: $value'),
                      KeyboardListener(
                        onKeyEvent: (key) {
                          if (key == LogicalKey.enter) {
                            context.invalidate(invalidatableProvider);
                          }
                          return false;
                        },
                        child: const Text('Press Enter to invalidate'),
                      ),
                    ],
                  );
                },
              ),
            ),
          );

          // Initial state
          expect(tester.terminalState, containsText('Build count: 1'));

          // Invalidate
          await tester.sendKey(LogicalKey.enter);
          await tester.pump();
          expect(tester.terminalState, containsText('Build count: 2'));
        },
      );
    });
  });
}
