import 'package:cinder/cinder.dart';
import 'package:cinder_riverpod/cinder_riverpod.dart';
import 'package:cinder_riverpod/src/framework.dart'
    show UncontrolledProviderScope;
import 'package:test/test.dart';

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

class _Listener extends StatefulWidget {
  const _Listener({required this.provider, required this.onChanged});

  final StateProvider<int> provider;
  final void Function(int) onChanged;

  @override
  State<_Listener> createState() => _ListenerState();
}

class _ListenerState extends State<_Listener> {
  @override
  void initState() {
    super.initState();
    context.listen(widget.provider, (_, next) => widget.onChanged(next));
  }

  @override
  Widget build(BuildContext context) => const Text('Listening');
}

void main() {
  test('listeners are closed when their widget leaves the scope', () async {
    final provider = StateProvider<int>((ref) => 0);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final values = <int>[];

    await testCinder('remove provider listener', (tester) async {
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        _Rebuildable(
          builder: (context, setState) {
            update = setState;
            return UncontrolledProviderScope(
              container: container,
              child: visible
                  ? _Listener(provider: provider, onChanged: values.add)
                  : const Text('Removed'),
            );
          },
        ),
      );
      container.read(provider.notifier).state = 1;
      expect(values, [1]);

      update(() => visible = false);
      await tester.pump();
      container.read(provider.notifier).state = 2;

      expect(values, [1]);
    });
  });

  test('watched auto-dispose providers release removed widgets', () async {
    var disposed = false;
    final provider = Provider.autoDispose<int>((ref) {
      ref.onDispose(() => disposed = true);
      return 42;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await testCinder('remove provider watcher', (tester) async {
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        _Rebuildable(
          builder: (context, setState) {
            update = setState;
            return UncontrolledProviderScope(
              container: container,
              child: visible
                  ? Builder(
                      builder: (context) => Text('${context.watch(provider)}'),
                    )
                  : const Text('Removed'),
            );
          },
        ),
      );
      expect(disposed, isFalse);

      update(() => visible = false);
      await tester.pump();
      await container.pump();

      expect(disposed, isTrue);
    });
  });

  for (final useLayoutBuilder in [false, true]) {
    test(
      'watch releases unused providers in ${useLayoutBuilder ? 'LayoutBuilder' : 'build'}',
      () async {
        var disposed = false;
        final provider = Provider.autoDispose<int>((ref) {
          ref.onDispose(() => disposed = true);
          return 42;
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await testCinder('conditional provider watch', (tester) async {
          var watching = true;
          late StateSetter update;
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: _Rebuildable(
                builder: (context, setState) {
                  update = setState;
                  Widget buildValue(BuildContext context) => Text(
                    watching ? '${context.watch(provider)}' : 'Not watching',
                  );
                  return useLayoutBuilder
                      ? LayoutBuilder(
                          builder: (context, constraints) =>
                              buildValue(context),
                        )
                      : buildValue(context);
                },
              ),
            ),
          );
          expect(disposed, isFalse);

          update(() => watching = false);
          await tester.pump();
          await container.pump();

          expect(disposed, isTrue);
        });
      },
    );
  }
}
