import 'package:cinder/cinder.dart';

/// A widget that simplify the writing of deeply nested widget trees.
///
/// It relies on the new kind of widget [SingleChildComponent], which has two
/// concrete implementations:
/// - [SingleChildStatelessComponent]
/// - [SingleChildStatefulComponent]
///
/// They are both respectively a [SingleChildComponent] variant of [StatelessWidget]
/// and [StatefulWidget].
///
/// The difference between a widget and its single-child variant is that they have
/// a custom `build` method that takes an extra parameter.
///
/// As such, a `StatelessWidget` would be:
///
/// ```dart
/// class MyComponent extends StatelessWidget {
///   MyComponent({Key key, this.child}): super(key: key);
///
///   final Widget child;
///
///   @override
///   Widget build(BuildContext context) {
///     return SomethingComponent(child: child);
///   }
/// }
/// ```
///
/// Whereas a [SingleChildStatelessComponent] would be:
///
/// ```dart
/// class MyComponent extends SingleChildStatelessComponent {
///   MyComponent({Key key, Widget child}): super(key: key, child: child);
///
///   @override
///   Widget buildWithChild(BuildContext context, Widget child) {
///     return SomethingComponent(child: child);
///   }
/// }
/// ```
///
/// This allows our new `MyComponent` to be used both with:
///
/// ```dart
/// MyComponent(
///   child: AnotherComponent(),
/// )
/// ```
///
/// and to be placed inside `children` of [Nested] like so:
///
/// ```dart
/// Nested(
///   children: [
///     MyComponent(),
///     ...
///   ],
///   child: AnotherComponent(),
/// )
/// ```
class Nested extends StatelessWidget implements SingleChildComponent {
  /// Allows configuring key, children and child
  Nested({
    Key? key,
    required List<SingleChildComponent> children,
    Widget? child,
  })  : assert(children.isNotEmpty),
        _children = children,
        _child = child,
        super(key: key);

  final List<SingleChildComponent> _children;
  final Widget? _child;

  @override
  Widget build(BuildContext context) {
    throw StateError('implemented internally');
  }

  @override
  _NestedElement createElement() => _NestedElement(this);
}

class _NestedElement extends StatelessElement
    with SingleChildComponentElementMixin {
  _NestedElement(Nested widget) : super(widget);

  @override
  Nested get widget => super.widget as Nested;

  final nodes = <_NestedHookElement>{};

  @override
  Widget build() {
    _NestedHook? nestedHook;
    var nextNode = _parent?.injectedChild ?? widget._child;

    for (final child in widget._children.reversed) {
      nextNode = nestedHook = _NestedHook(
        owner: this,
        wrappedComponent: child,
        injectedChild: nextNode,
      );
    }

    if (nestedHook != null) {
      // We manually update _NestedHookElement instead of letter components do their thing
      // because an item N may be constant but N+1 not. So, if we used components
      // then N+1 wouldn't rebuild because N didn't change
      for (final node in nodes) {
        node
          ..wrappedChild = nestedHook!.wrappedComponent
          ..injectedChild = nestedHook.injectedChild;

        final next = nestedHook.injectedChild;
        if (next is _NestedHook) {
          nestedHook = next;
        } else {
          break;
        }
      }
    }

    return nextNode!;
  }
}

class _NestedHook extends StatelessWidget {
  _NestedHook({
    this.injectedChild,
    required this.wrappedComponent,
    required this.owner,
  });

  final SingleChildComponent wrappedComponent;
  final Widget? injectedChild;
  final _NestedElement owner;

  @override
  _NestedHookElement createElement() => _NestedHookElement(this);

  @override
  Widget build(BuildContext context) =>
      throw StateError('handled internally');
}

class _NestedHookElement extends StatelessElement {
  _NestedHookElement(_NestedHook widget) : super(widget);

  @override
  _NestedHook get widget => super.widget as _NestedHook;

  Widget? _injectedChild;
  Widget? get injectedChild => _injectedChild;
  set injectedChild(Widget? value) {
    final previous = _injectedChild;
    if (value is _NestedHook &&
        previous is _NestedHook &&
        Widget.canUpdate(
          value.wrappedComponent,
          previous.wrappedComponent,
        )) {
      // no need to rebuild the wrapped widget just for a _NestedHook.
      // The widget doesn't matter here, only its Element.
      return;
    }
    if (previous != value) {
      _injectedChild = value;
      visitChildren((e) => e.markNeedsBuild());
    }
  }

  SingleChildComponent? _wrappedChild;
  SingleChildComponent? get wrappedChild => _wrappedChild;
  set wrappedChild(SingleChildComponent? value) {
    if (_wrappedChild != value) {
      _wrappedChild = value;
      markNeedsBuild();
    }
  }

  @override
  void mount(Element? parent, dynamic newSlot) {
    widget.owner.nodes.add(this);
    _wrappedChild = widget.wrappedComponent;
    _injectedChild = widget.injectedChild;
    super.mount(parent, newSlot);
  }

  @override
  void unmount() {
    widget.owner.nodes.remove(this);
    super.unmount();
  }

  @override
  Widget build() {
    return wrappedChild!;
  }
}

/// A [Widget] that takes a single descendant.
///
/// As opposed to [ProxyComponent], it may have a "build" method.
///
/// See also:
/// - [SingleChildStatelessComponent]
/// - [SingleChildStatefulComponent]
abstract class SingleChildComponent implements Widget {
  @override
  SingleChildComponentElementMixin createElement();
}

mixin SingleChildComponentElementMixin on Element {
  _NestedHookElement? _parent;

  @override
  void mount(Element? parent, dynamic newSlot) {
    if (parent is _NestedHookElement?) {
      _parent = parent;
    }
    super.mount(parent, newSlot);
  }

  @override
  void activate() {
    super.activate();
    visitAncestorElements((parent) {
      if (parent is _NestedHookElement) {
        _parent = parent;
      }
      return false;
    });
  }
}

/// A [StatelessWidget] that implements [SingleChildComponent] and is therefore
/// compatible with [Nested].
///
/// Its [build] method must **not** be overriden. Instead use [buildWithChild].
abstract class SingleChildStatelessComponent extends StatelessWidget
    implements SingleChildComponent {
  /// Creates a widget that has exactly one child widget.
  const SingleChildStatelessComponent({Key? key, Widget? child})
      : _child = child,
        super(key: key);

  final Widget? _child;

  /// A [build] method that receives an extra `child` parameter.
  ///
  /// This method may be called with a `child` different from the parameter
  /// passed to the constructor of [SingleChildStatelessComponent].
  /// It may also be called again with a different `child`, without this widget
  /// being recreated.
  Widget buildWithChild(BuildContext context, Widget? child);

  @override
  Widget build(BuildContext context) => buildWithChild(context, _child);

  @override
  SingleChildStatelessElement createElement() {
    return SingleChildStatelessElement(this);
  }
}

/// An [Element] that uses a [SingleChildStatelessComponent] as its configuration.
class SingleChildStatelessElement extends StatelessElement
    with SingleChildComponentElementMixin {
  /// Creates an element that uses the given widget as its configuration.
  SingleChildStatelessElement(SingleChildStatelessComponent widget)
      : super(widget);

  @override
  Widget build() {
    if (_parent != null) {
      return widget.buildWithChild(this, _parent!.injectedChild);
    }
    return super.build();
  }

  @override
  SingleChildStatelessComponent get widget =>
      super.widget as SingleChildStatelessComponent;
}

/// A [StatefulWidget] that is compatible with [Nested].
abstract class SingleChildStatefulComponent extends StatefulWidget
    implements SingleChildComponent {
  /// Creates a widget that has exactly one child widget.
  const SingleChildStatefulComponent({Key? key, Widget? child})
      : _child = child,
        super(key: key);

  final Widget? _child;

  @override
  SingleChildStatefulElement createElement() {
    return SingleChildStatefulElement(this);
  }
}

/// A [State] for [SingleChildStatefulComponent].
///
/// Do not override [build] and instead override [buildWithChild].
abstract class SingleChildState<T extends SingleChildStatefulComponent>
    extends State<T> {
  /// A [build] method that receives an extra `child` parameter.
  ///
  /// This method may be called with a `child` different from the parameter
  /// passed to the constructor of [SingleChildStatelessComponent].
  /// It may also be called again with a different `child`, without this widget
  /// being recreated.
  Widget buildWithChild(BuildContext context, Widget? child);

  @override
  Widget build(BuildContext context) =>
      buildWithChild(context, widget._child);
}

/// An [Element] that uses a [SingleChildStatefulComponent] as its configuration.
class SingleChildStatefulElement extends StatefulElement
    with SingleChildComponentElementMixin {
  /// Creates an element that uses the given widget as its configuration.
  SingleChildStatefulElement(SingleChildStatefulComponent widget)
      : super(widget);

  @override
  SingleChildStatefulComponent get widget =>
      super.widget as SingleChildStatefulComponent;

  @override
  SingleChildState<SingleChildStatefulComponent> get state =>
      super.state as SingleChildState<SingleChildStatefulComponent>;

  @override
  Widget build() {
    if (_parent != null) {
      return state.buildWithChild(this, _parent!.injectedChild!);
    }
    return super.build();
  }
}

/// A [SingleChildComponent] that delegates its implementation to a callback.
///
/// It works like [Builder], but is compatible with [Nested].
class SingleChildBuilder extends SingleChildStatelessComponent {
  /// Creates a widget that delegates its build to a callback.
  ///
  /// The [builder] argument must not be null.
  const SingleChildBuilder({Key? key, required this.builder, Widget? child})
      : super(key: key, child: child);

  /// Called to obtain the child widget.
  ///
  /// The `child` parameter may be different from the one parameter passed to
  /// the constructor of [SingleChildBuilder].
  final Widget Function(BuildContext context, Widget? child) builder;

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    return builder(context, child);
  }
}

mixin SingleChildStatelessComponentMixin
    implements StatelessWidget, SingleChildStatelessComponent {
  Widget? get child;

  @override
  Widget? get _child => child;

  @override
  SingleChildStatelessElement createElement() {
    return SingleChildStatelessElement(this);
  }

  @override
  Widget build(BuildContext context) {
    return buildWithChild(context, child);
  }
}

mixin SingleChildStatefulComponentMixin on StatefulWidget
    implements SingleChildComponent {
  Widget? get child;

  @override
  _SingleChildStatefulMixinElement createElement() =>
      _SingleChildStatefulMixinElement(this);
}

mixin SingleChildStateMixin<T extends StatefulWidget> on State<T> {
  Widget buildWithChild(BuildContext context, Widget child);

  @override
  Widget build(BuildContext context) {
    return buildWithChild(
      context,
      (widget as SingleChildStatefulComponentMixin).child!,
    );
  }
}

class _SingleChildStatefulMixinElement extends StatefulElement
    with SingleChildComponentElementMixin {
  _SingleChildStatefulMixinElement(SingleChildStatefulComponentMixin widget)
      : super(widget);

  @override
  SingleChildStatefulComponentMixin get widget =>
      super.widget as SingleChildStatefulComponentMixin;

  @override
  SingleChildStateMixin<StatefulWidget> get state =>
      super.state as SingleChildStateMixin<StatefulWidget>;

  @override
  Widget build() {
    if (_parent != null) {
      return state.buildWithChild(this, _parent!.injectedChild!);
    }
    return super.build();
  }
}

mixin SingleChildInheritedElementMixin
    on InheritedElement, SingleChildComponentElementMixin {
  @override
  Widget build() {
    if (_parent != null) {
      return _parent!.injectedChild!;
    }
    return super.build();
  }
}
