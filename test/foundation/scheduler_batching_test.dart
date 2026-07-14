import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  group('SchedulerBinding Frame Batching', () {
    test('multiple setState calls batch into single frame', () async {
      int buildCount = 0;
      late TestBatchingWidgetState state;

      await testCinder(
        'batching test',
        (tester) async {
          await tester.pumpWidget(
            TestBatchingWidget(
              onBuild: () => buildCount++,
              onStateCreated: (s) => state = s,
            ),
          );

          // Initial build
          expect(buildCount, 1);
          buildCount = 0;

          // Call setState 10 times rapidly
          for (int i = 0; i < 10; i++) {
            state.triggerSetState();
          }

          // Should only schedule ONE frame (not 10)
          expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);

          // Pump the frame
          await tester.pump();

          // Should have only rebuilt ONCE (not 10 times)
          expect(buildCount, 1);
        },
      );
    });

    test('rapid events batch into single frame', () async {
      int renderCount = 0;
      late TestEventWidgetState state;

      await testCinder(
        'rapid events test',
        (tester) async {
          await tester.pumpWidget(
            TestEventWidget(
              onRender: () => renderCount++,
              onStateCreated: (s) => state = s,
            ),
          );

          // Initial render
          expect(renderCount, 1);
          renderCount = 0;

          // Simulate 100 rapid scroll events
          for (int i = 0; i < 100; i++) {
            state.handleEvent(i);
          }

          // All events processed, state updated 100 times
          expect(state.value, 99);

          // But only ONE frame scheduled
          expect(SchedulerBinding.instance.hasScheduledFrame, isTrue);

          // Pump once
          await tester.pump();

          // Should have rendered only ONCE (not 100 times)
          expect(renderCount, 1);
        },
      );
    });

    test('post-frame callbacks execute after frame', () async {
      final executionOrder = <String>[];

      await testCinder(
        'post-frame callback test',
        (tester) async {
          await tester.pumpWidget(
            TestCallbackWidget(
              onBuild: () => executionOrder.add('build'),
              onPostFrame: () => executionOrder.add('post-frame'),
            ),
          );

          // Check execution order
          expect(executionOrder, ['build', 'post-frame']);
        },
      );
    });

    test('frame phases execute in correct order', () async {
      final phases = <SchedulerPhase>[];

      await testCinder(
        'frame phase test',
        (tester) async {
          // Register callbacks in different phases
          SchedulerBinding.instance.scheduleFrameCallback((timeStamp) {
            phases.add(SchedulerPhase.transientCallbacks);
          });

          SchedulerBinding.instance.addPersistentFrameCallback((timeStamp) {
            phases.add(SchedulerPhase.persistentCallbacks);
          });

          SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
            phases.add(SchedulerPhase.postFrameCallbacks);
          });

          // Trigger a frame
          SchedulerBinding.instance.scheduleFrame();
          await tester.pump();

          // Check phases executed in order
          expect(phases, [
            SchedulerPhase.transientCallbacks,
            SchedulerPhase.persistentCallbacks,
            SchedulerPhase.postFrameCallbacks,
          ]);
        },
      );
    });
  });
}

// Test widget that counts builds
class TestBatchingWidget extends StatefulWidget {
  const TestBatchingWidget({
    super.key,
    required this.onBuild,
    required this.onStateCreated,
  });

  final VoidCallback onBuild;
  final void Function(TestBatchingWidgetState) onStateCreated;

  @override
  State<TestBatchingWidget> createState() => TestBatchingWidgetState();
}

class TestBatchingWidgetState extends State<TestBatchingWidget> {
  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);
  }

  void triggerSetState() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const Text('Test');
  }
}

// Test widget for rapid events
class TestEventWidget extends StatefulWidget {
  const TestEventWidget({
    super.key,
    required this.onRender,
    required this.onStateCreated,
  });

  final VoidCallback onRender;
  final void Function(TestEventWidgetState) onStateCreated;

  @override
  State<TestEventWidget> createState() => TestEventWidgetState();
}

class TestEventWidgetState extends State<TestEventWidget> {
  int _value = 0;
  int get value => _value;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);
  }

  void handleEvent(int value) {
    setState(() {
      _value = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.onRender();
    return Text('Value: $_value');
  }
}

// Test widget for post-frame callbacks
class TestCallbackWidget extends StatefulWidget {
  const TestCallbackWidget({
    super.key,
    required this.onBuild,
    required this.onPostFrame,
  });

  final VoidCallback onBuild;
  final VoidCallback onPostFrame;

  @override
  State<TestCallbackWidget> createState() => TestCallbackWidgetState();
}

class TestCallbackWidgetState extends State<TestCallbackWidget> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      widget.onPostFrame();
    });
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return const Text('Test');
  }
}
