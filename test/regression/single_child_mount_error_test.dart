import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

/// Regression tests for errors raised while inflating the child of a
/// single-child render object widget.
///
/// `SingleChildRenderObjectElement` read its widget's `child` through
/// `dynamic` inside a `try`/`catch` that discarded every exception. That
/// catch also swallowed errors thrown while mounting or updating the child
/// subtree (`initState`, `createRenderObject`, asserts), so a broken child
/// under a `SizedBox` silently vanished while the same child under a
/// `Column` threw.
void main() {
  group('errors while inflating a single child', () {
    test('a throwing initState under a root SizedBox is thrown', () async {
      await testCinder('root SizedBox child throws', (tester) async {
        await expectLater(
          tester.pumpWidget(const SizedBox(child: _ThrowsInInitState())),
          throwsA(isA<_InitStateFailure>()),
        );
      });
    });

    test('a throwing initState for a new SizedBox child is reported', () async {
      final errors = <CinderErrorDetails>[];
      final previousHandler = CinderError.onError;
      CinderError.onError = errors.add;
      addTearDown(() => CinderError.onError = previousHandler);

      await testCinder('SizedBox child update throws', (tester) async {
        await tester.pumpWidget(const _ToggleSizedBoxChild());
        expect(errors, hasLength(0));

        tester.findState<_ToggleSizedBoxChildState>().showThrowingChild();
        await tester.pump();

        expect(
          errors.map((details) => details.exception),
          contains(isA<_InitStateFailure>()),
          reason:
              'an exception thrown while mounting the new child must reach '
              'CinderError.onError instead of being discarded',
        );
      });
    });
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

class _ToggleSizedBoxChild extends StatefulWidget {
  const _ToggleSizedBoxChild();

  @override
  State<_ToggleSizedBoxChild> createState() => _ToggleSizedBoxChildState();
}

class _ToggleSizedBoxChildState extends State<_ToggleSizedBoxChild> {
  bool _showThrowingChild = false;

  void showThrowingChild() {
    setState(() => _showThrowingChild = true);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: _showThrowingChild
          ? const _ThrowsInInitState()
          : const Text('healthy'),
    );
  }
}
