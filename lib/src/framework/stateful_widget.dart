part of 'framework.dart';

/// A widget that has mutable state.
abstract class StatefulWidget extends Widget {
  const StatefulWidget({super.key});

  @override
  StatefulElement createElement() => StatefulElement(this);

  /// Creates the mutable state for this widget.
  @protected
  State createState();
}

/// The logic and internal state for a [StatefulWidget].
abstract class State<T extends StatefulWidget> {
  T get widget => _component!;
  T? _component;

  BuildContext get context => _element!;
  StatefulElement? _element;

  bool get mounted => _element != null;

  /// Initialize state. Called once when the State object is created.
  @protected
  void initState() {}

  /// Called whenever the widget configuration changes.
  @protected
  void didUpdateWidget(covariant T oldWidget) {}

  /// Called when dependencies of this object change.
  @protected
  void didChangeDependencies() {}

  /// Called when this State is temporarily removed from the tree.
  ///
  /// The framework calls this method when this [State] object is removed from
  /// the tree temporarily. It may be reinserted into another part of the tree
  /// (e.g., if the subtree containing this [State] object is grafted from one
  /// location to another due to the use of a [GlobalKey]).
  ///
  /// If the State is reinserted into the tree, [activate] will be called.
  /// Otherwise, [dispose] will be called.
  ///
  /// Subclasses should override this method to release any resources that will
  /// be reallocated if the State is reactivated (via [activate]).
  @protected
  void deactivate() {}

  /// Called when this State is reinserted into the tree after being removed
  /// via [deactivate].
  ///
  /// In most cases, after a [State] object has been deactivated, it is not
  /// reinserted into the tree, and its [dispose] method will be called.
  ///
  /// In some cases, however, after a [State] object has been deactivated, the
  /// framework will reinsert it into another part of the tree (e.g., if the
  /// subtree containing this [State] object is grafted from one location in
  /// the tree to another due to the use of a [GlobalKey]). If that happens,
  /// the framework will call [activate] to give the [State] object a chance to
  /// reacquire any resources that it released in [deactivate].
  @protected
  void activate() {}

  /// Clean up resources. Called when the State object is removed permanently.
  @protected
  void dispose() {}

  /// Called whenever the application is reassembled during debugging, for
  /// example during hot reload.
  ///
  /// This provides an opportunity to reinitialize any data that was computed
  /// in the initState method or to reset any state.
  @protected
  @mustCallSuper
  void reassemble() {}

  /// Describes the part of the user interface represented by this widget.
  @protected
  Widget build(BuildContext context);

  /// Notify the framework that the internal state has changed.
  @protected
  void setState(VoidCallback fn) {
    assert(_element != null);
    assert(_element!._lifecycleState == _ElementLifecycle.active,
        'Element is not active but ${_element!._lifecycleState} instead');

    fn();
    _element!.markNeedsBuild();
  }
}

/// Element for StatefulWidget
class StatefulElement extends BuildableElement {
  StatefulElement(super.widget) {
    _state = widget.createState();
    assert(_state._element == null, 'State object was already used');
    _state._element = this;
    assert(_state._component == null, 'State object was already initialized');
    _state._component = widget;
  }

  @override
  StatefulWidget get widget => super.widget as StatefulWidget;

  late final State _state;
  State get state => _state;

  @override
  Widget build() => _state.build(this);

  @override
  void _firstBuild() {
    final Object? debugCheckForReturnedFuture = state.initState() as dynamic;
    assert(() {
      if (debugCheckForReturnedFuture is Future) {
        throw FlutterError([
          '${state.runtimeType}.initState() returned a Future.',
          'State.initState() must be a void method without an `async` keyword.',
          'Rather than awaiting on asynchronous work directly inside of initState, '
              'call a separate method to do this work without awaiting it.',
        ].join('\n'));
      }
      return true;
    }());

    state.didChangeDependencies();
    super._firstBuild();
  }

  @override
  void update(Widget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    final StatefulWidget oldWidget = _state._component!;
    _state._component = widget;
    final Object? debugCheckForReturnedFuture =
        _state.didUpdateWidget(oldWidget) as dynamic;
    assert(() {
      if (debugCheckForReturnedFuture is Future) {
        throw FlutterError(
            '${_state.runtimeType}.didUpdateWidget() returned a Future.');
      }
      return true;
    }());
    rebuild();
  }

  @override
  void activate() {
    super.activate();
    _state.activate();
    // Since the State could have observed the deactivate() and thus disposed of
    // resources allocated in the build method, we have to rebuild the widget
    // so that its State can reallocate its resources.
    markNeedsBuild();
  }

  @override
  void deactivate() {
    _state.deactivate();
    super.deactivate();
  }

  @override
  void unmount() {
    super.unmount();
    _state.dispose();
    _state._element = null;
    // Release resources to reduce the severity of memory leaks caused by
    // defunct, but accidentally retained Elements.
    _state._component = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state.didChangeDependencies();
  }

  @override
  void reassemble() {
    _state.reassemble();
    super.reassemble();
  }
}

/// Error thrown by the framework
class FlutterError extends Error {
  FlutterError(this.message);
  final String message;
  @override
  String toString() => message;
}
