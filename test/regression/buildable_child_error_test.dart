import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

/// Regression tests for errors thrown while a [BuildableElement] mounts or
/// updates its child.
///
/// Errors thrown by `build()` were already reported and replaced by an
/// [ErrorWidget], but errors thrown below it, while `updateChild` mounted or
/// updated the built child (`initState`, `didUpdateWidget`,
/// `createRenderObject`, asserts), escaped. At startup that aborted
/// `runApp`; during a frame it left a half-updated subtree in the tree.
/// Like Flutter's `ComponentElement`, the element now reports the error and
/// replaces its child with an [ErrorWidget], without leaving render objects
/// from the failed subtree on screen.
void main() {
  late List<CinderErrorDetails> errors;

  setUp(() {
    errors = [];
    final previousHandler = CinderError.onError;
    CinderError.onError = errors.add;
    addTearDown(() => CinderError.onError = previousHandler);
  });

  test('a child that throws while mounting is reported and replaced by an '
      'ErrorWidget', () async {
    await testCinder('mount error', (tester) async {
      await tester.pumpWidget(
        const _Frame(child: _Inner(showThrowingChild: true)),
      );

      expect(errors.map((details) => details.exception), [
        isA<_InitStateFailure>(),
      ]);
      expect(tester.terminalState, containsText('Build error'));
      expect(tester.terminalState, containsText('top'));
      expect(tester.terminalState, containsText('bottom'));
      expect(
        tester.terminalState,
        isNot(containsText('inner')),
        reason:
            'render objects of the half-mounted subtree must not stay in '
            'the parent Column',
      );
    }, size: const Size(40, 14));
  });

  test('a child that throws during an update is replaced by an ErrorWidget '
      'and the tree recovers', () async {
    await testCinder('update error', (tester) async {
      await tester.pumpWidget(const _Frame(child: _ToggleInner()));
      expect(tester.toSnapshot(), 'top\ninner\nbottom');

      final toggle = tester.findState<_ToggleInnerState>();
      toggle.setThrowing(true);
      await tester.pump();

      expect(errors.map((details) => details.exception), [
        isA<_InitStateFailure>(),
      ]);
      expect(tester.terminalState, containsText('Build error'));
      expect(
        tester.terminalState,
        isNot(containsText('inner')),
        reason: 'the failed subtree must be removed from the parent Column',
      );

      toggle.setThrowing(false);
      await tester.pump();

      expect(tester.toSnapshot(), 'top\ninner\nbottom');
      expect(errors, hasLength(1));
    }, size: const Size(40, 14));
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _InitStateFailure implements Exception {
  const _InitStateFailure();

  @override
  String toString() => '_InitStateFailure';
}

class _ThrowsInInitState extends StatefulWidget {
  const _ThrowsInInitState();

  @override
  State<_ThrowsInInitState> createState() => _ThrowsInInitStateState();
}

class _ThrowsInInitStateState extends State<_ThrowsInInitState> {
  @override
  void initState() {
    super.initState();
    throw const _InitStateFailure();
  }

  @override
  Widget build(BuildContext context) => const Text('unreachable');
}

/// Places [child] between two rows of a left-aligned [Column].
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const Text('top'), child, const Text('bottom')],
    );
  }
}

/// A [Column] that mounts 'inner' before the optional throwing child, so a
/// failure leaves an already-attached render object behind.
class _Inner extends StatelessWidget {
  const _Inner({required this.showThrowingChild});

  final bool showThrowingChild;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('inner'),
        if (showThrowingChild) const _ThrowsInInitState(),
      ],
    );
  }
}

class _ToggleInner extends StatefulWidget {
  const _ToggleInner();

  @override
  State<_ToggleInner> createState() => _ToggleInnerState();
}

class _ToggleInnerState extends State<_ToggleInner> {
  bool _throwing = false;

  void setThrowing(bool value) => setState(() => _throwing = value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('inner'),
        if (_throwing) const _ThrowsInInitState(),
      ],
    );
  }
}
