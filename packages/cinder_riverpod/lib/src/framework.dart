// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:collection';

import 'package:cinder/cinder.dart';
import 'package:riverpod/src/internals.dart';

import 'provider_dependencies.dart';

/// A widget that stores the state of providers.
///
/// Place this at the root of the Cinder widget tree.
class ProviderScope extends StatefulWidget {
  const ProviderScope({
    super.key,
    this.parent,
    this.overrides = const [],
    this.observers,
    this.retry,
    required this.child,
  });

  /// Optional explicit parent container.
  ///
  /// When omitted, Cinder uses the nearest ancestor [ProviderScope].
  final ProviderContainer? parent;
  final List<Override> overrides;
  final List<ProviderObserver>? observers;
  final Retry? retry;
  final Widget child;

  @override
  State<ProviderScope> createState() => _ProviderScopeState();

  static ProviderContainer containerOf(
    BuildContext context, {
    bool listen = true,
  }) {
    _InheritedProviderScope? scope;

    if (listen) {
      scope =
          context.dependOnInheritedWidgetOfExactType<_InheritedProviderScope>();
    } else {
      scope = context
          .getElementForInheritedWidgetOfExactType<_InheritedProviderScope>()
          ?.widget as _InheritedProviderScope?;
    }

    if (scope == null) {
      throw StateError(
        'ProviderScope not found. Wrap the Cinder app with ProviderScope.',
      );
    }

    return scope.container;
  }

  static _InheritedProviderScopeElement scopeElementOf(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      context.dependOnInheritedWidgetOfExactType<_InheritedProviderScope>();
    }

    final element = context
        .getElementForInheritedWidgetOfExactType<_InheritedProviderScope>();

    if (element is! _InheritedProviderScopeElement) {
      throw StateError(
        'ProviderScope not found. Wrap the Cinder app with ProviderScope.',
      );
    }

    return element;
  }
}

class _ProviderScopeState extends State<ProviderScope> {
  late final ProviderContainer _container;
  late final ProviderContainer? _parent;
  var _overridesDirty = false;

  ProviderContainer? _nearestParent() {
    final inherited = context
        .getElementForInheritedWidgetOfExactType<_InheritedProviderScope>()
        ?.widget as _InheritedProviderScope?;
    return inherited?.container;
  }

  @override
  void initState() {
    super.initState();
    _parent = widget.parent ?? _nearestParent();
    _container = ProviderContainer(
      parent: _parent,
      overrides: widget.overrides,
      observers: widget.observers,
      retry: widget.retry,
    );
  }

  @override
  void didUpdateWidget(ProviderScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    final nextParent = widget.parent ?? _nearestParent();
    if (!identical(nextParent, _parent)) {
      throw UnsupportedError(
        'ProviderScope cannot change its parent container after mounting.',
      );
    }

    if (!identical(widget.overrides, oldWidget.overrides)) {
      _overridesDirty = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_overridesDirty) {
      _overridesDirty = false;
      _container.updateOverrides(widget.overrides);
    }

    return UncontrolledProviderScope(
      container: _container,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }
}

/// Exposes an existing [ProviderContainer] to a Cinder widget subtree.
///
/// Unlike [ProviderScope], this widget does not dispose [container].
class UncontrolledProviderScope extends StatefulWidget {
  const UncontrolledProviderScope({
    super.key,
    required this.container,
    required this.child,
  });

  final ProviderContainer container;
  final Widget child;

  @override
  State<UncontrolledProviderScope> createState() =>
      _UncontrolledProviderScopeState();
}

/// Synchronizes Riverpod's deferred refresh work with Cinder frames.
class _UncontrolledProviderScopeState extends State<UncontrolledProviderScope>
    implements Vsync {
  Timer? _disposeTimer;

  @override
  void initState() {
    super.initState();
    widget.container.scheduler.flutterVsyncs.add(this);
  }

  @override
  void didUpdateWidget(UncontrolledProviderScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.container, widget.container)) {
      oldWidget.container.scheduler.flutterVsyncs.remove(this);
      widget.container.scheduler.flutterVsyncs.add(this);
    }
  }

  @override
  void Function()? scheduleRefresh(Task task) {
    // Cinder does not revisit descendants dirtied midway through the same
    // build traversal. Flush Riverpod first so listeners mark their elements
    // dirty before the next Cinder frame starts.
    task.call();
    if (mounted) {
      setState(() {});
    }
    return null;
  }

  @override
  void Function()? scheduleDispose(Task task) {
    _disposeTimer?.cancel();
    final timer = Timer(Duration.zero, task.call);
    _disposeTimer = timer;
    return timer.cancel;
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedProviderScope(
      container: widget.container,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _disposeTimer?.cancel();
    _disposeTimer = null;
    widget.container.scheduler.flutterVsyncs.remove(this);
    super.dispose();
  }
}

class _InheritedProviderScope extends InheritedWidget {
  const _InheritedProviderScope({
    required this.container,
    required super.child,
  });

  final ProviderContainer container;

  @override
  bool updateShouldNotify(_InheritedProviderScope oldWidget) {
    return !identical(container, oldWidget.container);
  }

  @override
  _InheritedProviderScopeElement createElement() {
    return _InheritedProviderScopeElement(this);
  }
}

class _InheritedProviderScopeElement extends InheritedElement {
  _InheritedProviderScopeElement(_InheritedProviderScope super.widget);

  @override
  _InheritedProviderScope get widget => super.widget as _InheritedProviderScope;

  ProviderContainer get container => widget.container;

  final _dependents = HashMap<Element, ProviderDependencies>();

  ProviderDependencies getDependencies(Element dependent) {
    return _dependents.putIfAbsent(
      dependent,
      () => ProviderDependencies(dependent),
    );
  }

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    super.updateDependencies(dependent, aspect);
    getDependencies(dependent);
  }

  @override
  void notifyDependent(InheritedWidget oldWidget, Element dependent) {
    _dependents[dependent]?.didRebuildDependent();
    super.notifyDependent(oldWidget, dependent);
  }

  void removeDependencies(Element dependent) {
    _dependents.remove(dependent)?.deactivateDependent();
  }

  @override
  void unmount() {
    for (final dependencies in _dependents.values) {
      dependencies.deactivateDependent();
    }
    _dependents.clear();
    super.unmount();
  }
}
