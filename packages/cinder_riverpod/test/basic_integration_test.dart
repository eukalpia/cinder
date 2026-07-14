import 'package:cinder/cinder.dart';
import 'package:cinder_riverpod/cinder_riverpod.dart';
import 'package:test/test.dart';

void main() {
  test('Riverpod integration - basic read and overrides', () async {
    // Define providers
    final nameProvider = Provider<String>((ref) => 'Cinder');
    final greetingProvider = Provider<String>((ref) {
      final name = ref.watch(nameProvider);
      return 'Hello, $name!';
    });

    await testCinder(
      'riverpod basic functionality',
      (tester) async {
        // Test 1: Basic provider read
        await tester.pumpWidget(
          ProviderScope(
            child: _SimpleBuilder(
              builder: (context) {
                final greeting = context.read(greetingProvider);
                return Text(greeting);
              },
            ),
          ),
        );

        expect(tester.terminalState, containsText('Hello, Cinder!'));

        // Test 2: Provider overrides
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              nameProvider.overrideWith((ref) => 'Riverpod'),
            ],
            child: _SimpleBuilder(
              builder: (context) {
                final greeting = context.read(greetingProvider);
                return Text(greeting);
              },
            ),
          ),
        );

        expect(tester.terminalState, containsText('Hello, Riverpod!'));
      },
    );
  });

  test('Riverpod integration - nested scopes', () async {
    final colorProvider = Provider<String>((ref) => 'blue');

    await testCinder(
      'nested provider scopes',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: Column(
              children: [
                _SimpleBuilder(
                  builder: (context) {
                    final color = context.read(colorProvider);
                    return Text('Outer: $color');
                  },
                ),
                ProviderScope(
                  overrides: [
                    colorProvider.overrideWith((ref) => 'red'),
                  ],
                  child: _SimpleBuilder(
                    builder: (context) {
                      final color = context.read(colorProvider);
                      return Text('Inner: $color');
                    },
                  ),
                ),
              ],
            ),
          ),
        );

        expect(tester.terminalState, containsText('Outer: blue'));
        expect(tester.terminalState, containsText('Inner: red'));
      },
    );
  });

  test('Riverpod integration - multiple providers', () async {
    final userProvider = Provider<String>((ref) => 'Alice');
    final ageProvider = Provider<int>((ref) => 30);
    final profileProvider = Provider<String>((ref) {
      final user = ref.watch(userProvider);
      final age = ref.watch(ageProvider);
      return '$user is $age years old';
    });

    await testCinder(
      'multiple providers',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: _SimpleBuilder(
              builder: (context) {
                final profile = context.read(profileProvider);
                return Text(profile);
              },
            ),
          ),
        );

        expect(tester.terminalState, containsText('Alice is 30 years old'));
      },
    );
  });
}

// Helper widget
class _SimpleBuilder extends StatelessWidget {
  const _SimpleBuilder({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return builder(context);
  }
}
