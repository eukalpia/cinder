import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  tearDown(CinderBinding.resetInstance);

  for (final initializeScopes in [false, true]) {
    test('unmounted State rejects new work (scopes: $initializeScopes)', () {
      final binding = _LifecycleBinding();
      final widget = _OwnedWidget();
      binding.attachRootWidget(widget);
      final state = widget.state;
      if (initializeScopes) {
        state.startWork();
        state.ownResource();
      }

      binding.detachRootWidget();

      expect(state.startWork, throwsStateError);
      expect(state.ownResource, throwsStateError);
      expect(state.updateValue, throwsStateError);
    });
  }

  test('State disposal prevents new work in user dispose callbacks', () {
    final binding = _LifecycleBinding();
    final widget = _OwnedWidget(
      onDispose: (state) {
        expect(state.startWork, throwsStateError);
        expect(state.ownResource, throwsStateError);
      },
    );
    binding.attachRootWidget(widget);

    binding.detachRootWidget();
  });

  test(
    'detaching the root disposes descendant States and unregisters keys',
    () async {
      final binding = _LifecycleBinding();
      final key = GlobalKey<_OwnedState>();
      final widget = _OwnedWidget(key: key);
      binding.attachRootWidget(SizedBox(child: widget));
      final state = widget.state;
      final task = state.startCancellableWork();
      final timer = state.startTimer();
      addTearDown(timer.cancel);

      binding.detachRootWidget();

      expect(state.mounted, isFalse);
      expect(state.disposals, 1);
      expect(task.isCancelled, isTrue);
      expect(timer.isActive, isFalse);
      expect(key.currentState, isNull);
      await task.future;
    },
  );

  test('a throwing dispose cannot prevent sibling States from unmounting', () {
    final binding = _LifecycleBinding();
    final failed = _OwnedWidget(onDispose: (_) => throw StateError('dispose'));
    final sibling = _OwnedWidget();
    binding.attachRootWidget(Column(children: [failed, sibling]));

    expect(binding.detachRootWidget, throwsStateError);

    expect(failed.state.mounted, isFalse);
    expect(sibling.state.mounted, isFalse);
    expect(failed.state.disposals, 1);
    expect(sibling.state.disposals, 1);
    expect(binding.rootElement, isNull);
  });

  test('a throwing deactivate cannot prevent tree cleanup', () {
    final binding = _LifecycleBinding();
    final failed = _OwnedWidget(
      onDeactivate: () => throw StateError('deactivate'),
    );
    final sibling = _OwnedWidget();
    binding.attachRootWidget(Column(children: [failed, sibling]));

    expect(binding.detachRootWidget, throwsStateError);

    expect(failed.state.mounted, isFalse);
    expect(sibling.state.mounted, isFalse);
    expect(failed.state.disposals, 1);
    expect(sibling.state.disposals, 1);
  });

  test('replacing the root cleans up the previous descendant tree', () {
    final binding = _LifecycleBinding();
    final previous = _OwnedWidget();
    binding.attachRootWidget(SizedBox(child: previous));

    binding.attachRootWidget(const SizedBox());

    expect(previous.state.mounted, isFalse);
    expect(previous.state.disposals, 1);
    binding.detachRootWidget();
  });

  test('plain rendering unmounts the complete widget tree', () async {
    final widget = _OwnedWidget();

    await renderPlainWidget(widget);

    expect(widget.state.mounted, isFalse);
    expect(widget.state.disposals, 1);
    expect(CinderBinding.hasInstance, isFalse);
  });

  test(
    'plain rendering releases the binding after user dispose fails',
    () async {
      final widget = _OwnedWidget(
        onDispose: (_) => throw StateError('dispose'),
      );

      await expectLater(renderPlainWidget(widget), throwsStateError);

      expect(widget.state.mounted, isFalse);
      expect(CinderBinding.hasInstance, isFalse);
    },
  );
  test('disposing a tester cleans up the current State tree', () async {
    final tester = await CinderTester.create();
    final widget = _OwnedWidget();
    await tester.pumpWidget(SizedBox(child: widget));

    tester.dispose();

    expect(widget.state.mounted, isFalse);
    expect(widget.state.disposals, 1);
    expect(CinderBinding.hasInstance, isFalse);
  });

  test('unmounted render objects cannot receive queued layout work', () {
    final binding = _LifecycleBinding();
    final pipeline = PipelineOwner();
    final renderObject = _TrackedRenderObject();
    binding.attachRootWidget(_TrackedRenderWidget(renderObject));
    renderObject.attach(pipeline);
    renderObject.layout(BoxConstraints.tight(const Size(10, 5)));
    renderObject.markNeedsLayout();
    pipeline.requestLayout(renderObject);

    binding.detachRootWidget();
    pipeline.flushLayout();

    expect(renderObject.layoutsAfterDispose, 0);
    expect(renderObject.owner, isNull);
  });

  test(
    'focused TextField teardown permits inactive parent notifications',
    () async {
      final tester = await CinderTester.create();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final focusChanges = <bool>[];
      await tester.pumpWidget(
        TextField(
          focusNode: focusNode,
          autofocus: true,
          onFocusChange: focusChanges.add,
        ),
      );
      expect(focusNode.hasFocus, isTrue);

      tester.dispose();

      expect(focusNode.hasFocus, isFalse);
      expect(focusChanges.last, isFalse);
      expect(CinderBinding.hasInstance, isFalse);
    },
  );
}

final class _LifecycleBinding extends CinderBinding {
  @override
  void scheduleFrame() {}
}

// The retained State lets the tests exercise late asynchronous callbacks.
// ignore: must_be_immutable
final class _OwnedWidget extends StatefulWidget {
  _OwnedWidget({super.key, this.onDispose, this.onDeactivate});

  final void Function(_OwnedState)? onDispose;
  final void Function()? onDeactivate;
  late _OwnedState state;

  @override
  State createState() => state = _OwnedState();
}

final class _OwnedState extends State<_OwnedWidget> {
  int disposals = 0;

  void startWork() => runTask<void>((_) {});

  void ownResource() => resources.add(() {});

  void updateValue() => setState(() {});

  CinderTask<void> startCancellableWork() => runTask<void>((token) async {
    await token.whenCancelled;
  });

  Timer startTimer() => trackTimer(Timer(const Duration(minutes: 1), () {}));

  @override
  Widget build(BuildContext context) => const SizedBox();

  @override
  void deactivate() {
    widget.onDeactivate?.call();
    super.deactivate();
  }

  @override
  void dispose() {
    disposals++;
    widget.onDispose?.call(this);
    super.dispose();
  }
}

final class _TrackedRenderWidget extends SingleChildRenderObjectWidget {
  const _TrackedRenderWidget(this.renderObject);

  final _TrackedRenderObject renderObject;

  @override
  RenderObject createRenderObject(BuildContext context) => renderObject;
}

final class _TrackedRenderObject extends RenderObject {
  bool disposed = false;
  int layoutsAfterDispose = 0;

  @override
  void performLayout() {
    if (disposed) layoutsAfterDispose++;
    size = constraints.constrain(const Size(10, 5));
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
