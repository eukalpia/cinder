import 'package:cinder/cinder.dart';
import 'package:test/test.dart' hide isEmpty, isNotEmpty;

/// Unit tests for the terminal-state matchers, with emphasis on the
/// discriminating power that plain containsText lacks.
void main() {
  group('containsTextOnce', () {
    test('matches a single occurrence', () async {
      await testCinder('single occurrence', (tester) async {
        await tester.pumpComponent(const Text('UNIQUE'));
        expect(tester.terminalState, containsTextOnce('UNIQUE'));
      }, size: const Size(20, 3));
    });

    test('fails when the text is absent', () async {
      await testCinder('absent', (tester) async {
        await tester.pumpComponent(const Text('something'));
        expect(containsTextOnce('MISSING').matches(tester.terminalState, {}),
            isFalse);
      }, size: const Size(20, 3));
    });

    test('fails on duplicates - the stale-ghost symptom containsText misses',
        () async {
      await testCinder('duplicates', (tester) async {
        await tester.pumpComponent(
          const Column(children: [Text('GHOST'), Text('GHOST')]),
        );
        // containsText is satisfied by either copy...
        expect(tester.terminalState, containsText('GHOST'));
        // ...containsTextOnce is not.
        expect(containsTextOnce('GHOST').matches(tester.terminalState, {}),
            isFalse);
        // The mismatch description lists every position.
        final mismatch = StringDescription();
        final state = <dynamic, dynamic>{};
        containsTextOnce('GHOST').matches(tester.terminalState, state);
        containsTextOnce('GHOST')
            .describeMismatch(tester.terminalState, mismatch, state, false);
        expect(mismatch.toString(), contains('2 occurrences'));
      }, size: const Size(20, 4));
    });
  });

  group('hasTextAt', () {
    test('matches text at the exact position only', () async {
      await testCinder('positional', (tester) async {
        await tester.pumpComponent(
          const Align(alignment: Alignment.topLeft, child: Text('AB')),
        );
        expect(tester.terminalState, hasTextAt(0, 0, 'AB'));
        expect(
            hasTextAt(1, 0, 'AB').matches(tester.terminalState, {}), isFalse);
        expect(
            hasTextAt(0, 1, 'AB').matches(tester.terminalState, {}), isFalse);
      }, size: const Size(10, 3));
    });
  });
}
