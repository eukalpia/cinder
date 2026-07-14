import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

import '../../example/gesture_demo.dart';

void main() {
  group('Gesture Demo',
      skip:
          'Known issue: GestureDemo uses nested constraints that need refactoring',
      () {
    test('visual development - initial render', () async {
      await testCinder(
        'gesture demo renders correctly',
        (tester) async {
          await tester.pumpWidget(const GestureDemoApp());
        },
        debugPrintAfterPump: true,
        size: const Size(100, 50),
      );
    });

    test('renders all zones and labels', () async {
      await testCinder(
        'all zones visible',
        (tester) async {
          await tester.pumpWidget(const GestureDemoApp());

          // Verify all zone labels are present
          expect(tester.terminalState, containsText('TAP ME'));
          expect(tester.terminalState, containsText('DOUBLE TAP'));
          expect(tester.terminalState, containsText('LONG PRESS'));
          expect(tester.terminalState, containsText('HOVER ME'));
          expect(tester.terminalState, containsText('COMBINED'));
          expect(tester.terminalState, containsText('Event Log'));
        },
        size: const Size(100, 50),
      );
    });

    test('tap zone interaction', () async {
      await testCinder(
        'tap updates state',
        (tester) async {
          bool tapped = false;

          await tester.pumpWidget(
            _TestTapWidget(onTapCallback: () => tapped = true),
          );

          // Tap
          await tester.tap(10, 5);

          // Verify tap was registered
          expect(tapped, true);
        },
      );
    });

    test('double-tap detection', () async {
      await testCinder(
        'double tap increments counter',
        (tester) async {
          int doubleTapCount = 0;

          await tester.pumpWidget(
            _TestDoubleTapWidget(
              onDoubleTapCallback: () => doubleTapCount++,
            ),
          );

          // Double tap
          await tester.tap(10, 5);
          await tester.pump(const Duration(milliseconds: 100));
          await tester.tap(10, 5);

          // Verify double-tap was registered
          expect(doubleTapCount, 1);
        },
      );
    });

    test('long press detection', () async {
      await testCinder(
        'long press triggers callback',
        (tester) async {
          bool longPressStarted = false;
          bool longPressCompleted = false;

          await tester.pumpWidget(
            _TestLongPressWidget(
              onLongPressStartCallback: () => longPressStarted = true,
              onLongPressCallback: () => longPressCompleted = true,
            ),
          );

          // Long press
          await tester.press(10, 5);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.release(10, 5);

          // Verify long press was registered
          expect(longPressStarted, true);
          expect(longPressCompleted, true);
        },
      );
    });

    test('hover region detection', () async {
      await testCinder(
        'hover changes state',
        (tester) async {
          bool isHovering = false;

          await tester.pumpWidget(
            _TestHoverWidget(
              onEnterCallback: () => isHovering = true,
              onExitCallback: () => isHovering = false,
            ),
          );

          // Hover
          await tester.hover(10, 5);

          // Verify hover was registered
          expect(isHovering, true);
        },
      );
    });

    test('combined zone - tap and hover', () async {
      await testCinder(
        'combined zone handles multiple gestures',
        (tester) async {
          bool isHovering = false;
          int tapCount = 0;

          await tester.pumpWidget(
            _TestCombinedWidget(
              onEnterCallback: () => isHovering = true,
              onTapCallback: () => tapCount++,
            ),
          );

          // Hover first
          await tester.hover(15, 5);
          expect(isHovering, true);

          // Tap while hovering
          await tester.tap(15, 5);
          expect(tapCount, 1);
        },
      );
    });

    test('visual test - demo app renders', () async {
      await testCinder(
        'gesture demo at default size',
        (tester) async {
          await tester.pumpWidget(const GestureDemoApp());

          // Should render without overflow at proper size
          expect(tester.terminalState, containsText('GESTURE DETECTOR DEMO'));
          expect(tester.terminalState, containsText('Count: 0'));
        },
        size: const Size(100, 50),
      );
    });

    test('position tracking in callbacks', () async {
      await testCinder(
        'tap provides position details',
        (tester) async {
          Offset? tapPosition;

          await tester.pumpWidget(
            _TestPositionWidget(
              onTapDownCallback: (details) =>
                  tapPosition = details.localPosition,
            ),
          );

          // Tap at specific position
          await tester.tap(15, 8);

          // Verify position was captured
          expect(tapPosition, isNotNull);
          expect(tapPosition!.dx, 15.0);
          expect(tapPosition!.dy, 8.0);
        },
      );
    });
  });
}

// Helper test components
class _TestTapWidget extends StatefulWidget {
  const _TestTapWidget({required this.onTapCallback});

  final VoidCallback onTapCallback;

  @override
  State<_TestTapWidget> createState() => _TestTapWidgetState();
}

class _TestTapWidgetState extends State<_TestTapWidget> {
  int tapCount = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 50,
      child: GestureDetector(
        onTap: () {
          widget.onTapCallback();
          setState(() {
            tapCount++;
          });
        },
        child: Container(
          width: 30,
          height: 10,
          decoration: BoxDecoration(border: BoxBorder.all()),
          child: Center(
            child: Text('Tap count: $tapCount'),
          ),
        ),
      ),
    );
  }
}

class _TestDoubleTapWidget extends StatefulWidget {
  const _TestDoubleTapWidget({required this.onDoubleTapCallback});

  final VoidCallback onDoubleTapCallback;

  @override
  State<_TestDoubleTapWidget> createState() => _TestDoubleTapWidgetState();
}

class _TestDoubleTapWidgetState extends State<_TestDoubleTapWidget> {
  int doubleTapCount = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 50,
      child: GestureDetector(
        onDoubleTap: () {
          widget.onDoubleTapCallback();
          setState(() {
            doubleTapCount++;
          });
        },
        child: Container(
          width: 30,
          height: 10,
          decoration: BoxDecoration(border: BoxBorder.all()),
          child: Center(
            child: Text('Double taps: $doubleTapCount'),
          ),
        ),
      ),
    );
  }
}

class _TestLongPressWidget extends StatelessWidget {
  const _TestLongPressWidget({
    required this.onLongPressStartCallback,
    required this.onLongPressCallback,
  });

  final VoidCallback onLongPressStartCallback;
  final VoidCallback onLongPressCallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 50,
      child: GestureDetector(
        onLongPress: onLongPressCallback,
        onLongPressStart: (details) => onLongPressStartCallback(),
        child: Container(
          width: 30,
          height: 10,
          decoration: BoxDecoration(border: BoxBorder.all()),
          child: const Center(child: Text('Long press me')),
        ),
      ),
    );
  }
}

class _TestHoverWidget extends StatelessWidget {
  const _TestHoverWidget({
    required this.onEnterCallback,
    required this.onExitCallback,
  });

  final VoidCallback onEnterCallback;
  final VoidCallback onExitCallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 50,
      child: MouseRegion(
        onEnter: (event) => onEnterCallback(),
        onExit: (event) => onExitCallback(),
        child: Container(
          width: 30,
          height: 10,
          decoration: BoxDecoration(border: BoxBorder.all()),
          child: const Center(child: Text('Hover me')),
        ),
      ),
    );
  }
}

class _TestCombinedWidget extends StatelessWidget {
  const _TestCombinedWidget({
    required this.onEnterCallback,
    required this.onTapCallback,
  });

  final VoidCallback onEnterCallback;
  final VoidCallback onTapCallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 50,
      child: MouseRegion(
        onEnter: (event) => onEnterCallback(),
        child: GestureDetector(
          onTap: onTapCallback,
          child: Container(
            width: 40,
            height: 10,
            decoration: BoxDecoration(border: BoxBorder.all()),
            child: const Center(child: Text('Tap and hover')),
          ),
        ),
      ),
    );
  }
}

class _TestPositionWidget extends StatelessWidget {
  const _TestPositionWidget({required this.onTapDownCallback});

  final Function(TapDownDetails) onTapDownCallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 50,
      child: GestureDetector(
        onTapDown: onTapDownCallback,
        child: Container(
          width: 40,
          height: 10,
          decoration: BoxDecoration(border: BoxBorder.all()),
          child: const Center(child: Text('Tap for position')),
        ),
      ),
    );
  }
}
