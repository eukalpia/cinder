import 'package:test/test.dart';
import 'package:cinder/cinder.dart';

void main() {
  group('Overlay unmount regression', () {
    // Regression test for: "Null check operator used on a null value"
    // when OverlayEntry.remove() was called during unmount.
    // The issue was that OverlayState._remove called setState() even when
    // the state was no longer mounted, causing setState to fail.
    test('removing overlay entry during unmount does not throw', () async {
      await testCinder(
        'overlay entry removal during unmount',
        (tester) async {
          final entry = OverlayEntry(
            builder: (context) => Container(
              width: 20,
              height: 3,
              child: Text('Test Entry'),
            ),
          );

          // Create a stateful wrapper that removes the entry on dispose
          await tester.pumpComponent(
            _DisposingOverlayWrapper(entry: entry),
          );

          expect(tester.terminalState, containsText('Test Entry'));

          // Replace with a different widget - this triggers unmount
          // of the overlay and should not throw
          await tester.pumpComponent(
            Container(
              width: 20,
              height: 3,
              child: Text('Replaced'),
            ),
          );

          expect(tester.terminalState, containsText('Replaced'));
          expect(tester.terminalState, isNot(containsText('Test Entry')));
        },
      );
    });
  });
}

/// A wrapper that holds an overlay and calls entry.remove() in its dispose.
/// This simulates what happens when Route.dispose() is called during unmount.
class _DisposingOverlayWrapper extends StatefulWidget {
  final OverlayEntry entry;

  const _DisposingOverlayWrapper({required this.entry});

  @override
  State<_DisposingOverlayWrapper> createState() =>
      _DisposingOverlayWrapperState();
}

class _DisposingOverlayWrapperState extends State<_DisposingOverlayWrapper> {
  @override
  void dispose() {
    // This simulates what Route.dispose() does - removes overlay entries
    // during the unmount phase
    widget.entry.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [widget.entry],
    );
  }
}
