import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

/// Regression test for `BuildOwner.buildScope` recovering from an element
/// whose rebuild throws.
///
/// An exception escaping `buildScope` skipped its cleanup, so the dirty list
/// was never cleared and `_scheduledFlushDirtyElements` stayed `true`. From
/// then on `scheduleBuildFor` never asked the binding for a frame, so
/// `setState` calls no longer scheduled frames, and the failed element was
/// rebuilt again on every later frame ahead of the elements behind it.
void main() {
  test('a throwing rebuild does not stop later setState calls from '
      'scheduling frames', () async {
    final errors = <CinderErrorDetails>[];
    final previousHandler = CinderError.onError;
    CinderError.onError = errors.add;
    addTearDown(() => CinderError.onError = previousHandler);

    await testCinder('throwing rebuild recovery', (tester) async {
      // The probe is the root, so it is the shallowest dirty element and
      // rebuilds before the counter below it.
      await tester.pumpWidget(
        const _RebuildProbe(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_Counter()],
          ),
        ),
      );
      final probe = _RebuildProbeElement.latest!..rebuildAttempts = 0;
      expect(tester.terminalState, containsText('count 0'));

      probe
        ..throwOnRebuild = true
        ..markNeedsBuild();
      await tester.pump();
      expect(errors.map((details) => details.exception), [
        isA<_RebuildFailure>(),
      ]);
      expect(probe.rebuildAttempts, 1);

      expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
      tester.findState<_CounterState>().increment();
      expect(
        SchedulerBinding.instance.hasScheduledFrame,
        isTrue,
        reason:
            'setState after a failed build must still ask the binding '
            'for a frame',
      );

      await tester.pump();
      expect(tester.terminalState, containsText('count 1'));
      expect(
        probe.rebuildAttempts,
        1,
        reason: 'the element that failed must not be rebuilt on every frame',
      );
      expect(errors, hasLength(1));

      // The failed element is clean again, so it can be rebuilt on request.
      probe
        ..throwOnRebuild = false
        ..markNeedsBuild();
      await tester.pump();
      expect(probe.rebuildAttempts, 2);
      expect(errors, hasLength(1));
    }, size: const Size(20, 3));
  });

  test('dirty elements queued behind a throwing rebuild still rebuild in '
      'the same frame', () async {
    final errors = <CinderErrorDetails>[];
    final previousHandler = CinderError.onError;
    CinderError.onError = errors.add;
    addTearDown(() => CinderError.onError = previousHandler);

    await testCinder('rebuild after throwing element', (tester) async {
      await tester.pumpWidget(
        const _RebuildProbe(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_Counter()],
          ),
        ),
      );
      final probe = _RebuildProbeElement.latest!;

      probe
        ..throwOnRebuild = true
        ..markNeedsBuild();
      tester.findState<_CounterState>().increment();
      await tester.pump();

      expect(errors.map((details) => details.exception), [
        isA<_RebuildFailure>(),
      ]);
      expect(
        tester.terminalState,
        containsText('count 1'),
        reason: 'one failing element must not abort the rest of the build',
      );

      // The counter is clean and out of the dirty list, so it still
      // responds to setState.
      tester.findState<_CounterState>().increment();
      await tester.pump();
      expect(tester.terminalState, containsText('count 2'));
    }, size: const Size(20, 3));
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _RebuildFailure implements Exception {
  const _RebuildFailure();

  @override
  String toString() => '_RebuildFailure';
}

/// A pass-through widget whose element can be told to throw from
/// [Element.performRebuild], outside the `build()` call that
/// [BuildableElement] already guards.
class _RebuildProbe extends StatelessWidget {
  const _RebuildProbe({required this.child});

  final Widget child;

  @override
  StatelessElement createElement() => _RebuildProbeElement(this);

  @override
  Widget build(BuildContext context) => child;
}

class _RebuildProbeElement extends StatelessElement {
  _RebuildProbeElement(super.widget);

  static _RebuildProbeElement? latest;

  bool throwOnRebuild = false;
  int rebuildAttempts = 0;

  @override
  void mount(Element? parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    latest = this;
  }

  @override
  void performRebuild() {
    rebuildAttempts++;
    if (throwOnRebuild) throw const _RebuildFailure();
    super.performRebuild();
  }
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  void increment() => setState(() => _count++);

  @override
  Widget build(BuildContext context) => Text('count $_count');
}
