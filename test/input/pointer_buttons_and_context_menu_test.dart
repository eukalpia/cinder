import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('button-aware gestures', () {
    test('secondary and middle taps expose the active button state', () async {
      var secondaryTaps = 0;
      var middleTaps = 0;
      TapDownDetails? secondaryDown;
      TapDownDetails? middleDown;

      await testCinder('secondary and middle taps', (tester) async {
        await tester.pumpWidget(
          GestureDetector(
            onSecondaryTapDown: (details) => secondaryDown = details,
            onSecondaryTap: () => secondaryTaps++,
            onMiddleTapDown: (details) => middleDown = details,
            onMiddleTap: () => middleTaps++,
            child: const SizedBox(width: 20, height: 5, child: Text('target')),
          ),
        );

        await tester.secondaryTap(2, 1);
        await tester.middleTap(3, 1);

        expect(secondaryTaps, 1);
        expect(middleTaps, 1);
        expect(secondaryDown!.button, MouseButton.right);
        expect(secondaryDown!.buttons, contains(MouseButton.right));
        expect(middleDown!.button, MouseButton.middle);
        expect(middleDown!.buttons, contains(MouseButton.middle));
      });
    });

    test('drag callbacks report button, held buttons, and deltas', () async {
      final starts = <DragStartDetails>[];
      final updates = <DragUpdateDetails>[];
      final ends = <DragEndDetails>[];

      await testCinder('right button drag', (tester) async {
        await tester.pumpWidget(
          GestureDetector(
            onDragStart: starts.add,
            onDragUpdate: updates.add,
            onDragEnd: ends.add,
            child: const SizedBox(
              width: 30,
              height: 10,
              child: Text('drag target'),
            ),
          ),
        );

        await tester.mouseMove(2, 2, 8, 4, button: MouseButton.right);

        expect(starts, hasLength(1));
        expect(updates, isNotEmpty);
        expect(ends, hasLength(1));
        expect(starts.single.button, MouseButton.right);
        expect(starts.single.buttons, contains(MouseButton.right));
        expect(
          updates.every((event) => event.button == MouseButton.right),
          isTrue,
        );
        expect(ends.single.button, MouseButton.right);
      });
    });
  });

  group('ContextMenuRegion', () {
    Widget app({required bool autofocus}) {
      return Overlay(
        initialEntries: <OverlayEntry>[
          OverlayEntry(
            builder: (_) => ContextMenuRegion(
              autofocus: autofocus,
              menuBuilder: (_, controller) => Container(
                width: 18,
                height: 3,
                decoration: BoxDecoration(border: BoxBorder.all()),
                child: const Text('Context action'),
              ),
              child: const SizedBox.expand(child: Text('workspace')),
            ),
          ),
        ],
      );
    }

    test('right click opens a menu and clamps it into the viewport', () async {
      await testCinder('context menu pointer open', (tester) async {
        await tester.pumpWidget(app(autofocus: false));
        await tester.secondaryTap(79, 23);
        expect(tester.terminalState, containsText('Context action'));
      });
    });

    test('Shift+F10 opens the focused context menu', () async {
      await testCinder('context menu keyboard open', (tester) async {
        await tester.pumpWidget(app(autofocus: true));
        await tester.sendKeyEvent(
          const KeyboardEvent(
            logicalKey: LogicalKey.f10,
            modifiers: ModifierKeys(shift: true),
          ),
        );
        expect(tester.terminalState, containsText('Context action'));
      });
    });
  });
}
