import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:cinder/cinder.dart';
import 'package:riverpod/riverpod.dart';

import 'provider_dependencies.dart';

/// A widget that stores the state of providers.
///
/// This widget is necessary to use any provider-related functionality.
/// It should be placed at the root of the widget tree:
///
/// ```dart
/// runApp(
///   ProviderScope(
///     child: MyApp(),
///   ),
/// );
/// ```
class ProviderScope extends StatefulWidget {
  const ProviderScope({
    super.key,
    this.parent,
    this.overrides = const [],
    this.observers,
    required this.child,
  });

  /// The parent container if this is a nested scope
  final ProviderContainer? parent;

  /// Overrides for providers in this scope
  final List<Override> overrides;

  /// Observers for provider state changes
  final List<ProviderObserver>? observers;

  /// The child widget
  final Widget child;

  @override
  State<ProviderScope> createState() => _ProviderScopeState();

  /// Returns the [ProviderContainer] of the closest [ProviderScope] ancestor.
  static ProviderContainer containerOf(
    BuildContext context, {
    bool listen = true,
  }) {
    UncontrolledProviderScope? scope;

    if (listen) {
      scope = context
          .dependOnInheritedWidgetOfExactType<UncontrolledProviderScope>();
    } else {
      scope =
          context.findAncestorWidgetOfExactType<UncontrolledProviderScope>();
    }

    if (scope == null) {
      throw StateError(
        'ProviderScope not found. Make sure to wrap your app with a ProviderScope.',
      );
    }

    return scope.container;
  }

  /// Returns the [_UncontrolledProviderScopeElement] of the closest [ProviderScope] ancestor.
  @internal
  static _UncontrolledProviderScopeElement scopeElementOf(
      BuildContext context) {
    // Find the InheritedElement for UncontrolledProviderScope
    // Use the built-in getElementForInheritedWidgetOfExactType which uses the
    // properly maintained _inheritedElements map, rather than walking the parent chain.
    final InheritedElement? element =
        context.getElementForInheritedWidgetOfExactType<
            UncontrolledProviderScope>();

    if (element == null || element is! _UncontrolledProviderScopeElement) {
      throw StateError(
        'ProviderScope not found. Make sure to wrap your app with a ProviderScope.',
      );
    }

    return element;
  }
}

class _ProviderScopeState extends State<ProviderScope> {
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();

    _container = ProviderContainer(
      parent: widget.parent,
      overrides: widget.overrides,
      observers: widget.observers,
    );
  }

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: _container,
      child: widget.child,
    );
  }
}

/// An [InheritedWidget] that exposes a [ProviderContainer] to its descendants.
///
/// This is the internal implementation used by [ProviderScope].
@internal
class UncontrolledProviderScope extends InheritedWidget {
  const UncontrolledProviderScope({
    super.key,
    required this.container,
    required super.child,
  });

  /// The container that holds all provider state
  final ProviderContainer container;

  @override
  bool updateShouldNotify(UncontrolledProviderScope oldWidget) {
    return container != oldWidget.container;
  }

  @override
  _UncontrolledProviderScopeElement createElement() {
    return _UncontrolledProviderScopeElement(this);
  }
}

/// Element for [UncontrolledProviderScope] that manages provider dependencies.
class _UncontrolledProviderScopeElement extends InheritedElement {
  _UncontrolledProviderScopeElement(UncontrolledProviderScope super.widget);

  @override
  UncontrolledProviderScope get widget =>
      super.widget as UncontrolledProviderScope;

  ProviderContainer get container => widget.container;

  /// Map of dependent elements to their provider dependencies
  final _dependents = HashMap<Element, ProviderDependencies>();

  /// Get or create dependencies for a dependent element
  ProviderDependencies getDependencies(Element dependent) {
    return _dependents.putIfAbsent(
      dependent,
      () => ProviderDependencies(dependent),
    );
  }

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    super.updateDependencies(dependent, aspect);

    // When a dependency is registered, ensure we have a ProviderDependencies for it
    // This happens when an element calls dependOnInheritedWidgetOfExactType
    getDependencies(dependent);
  }

  @override
  void notifyDependent(InheritedWidget oldWidget, Element dependent) {
    // Called when this InheritedElement changes and needs to notify dependents
    // First, let the dependent's provider dependencies know it's about to rebuild
    final dependencies = _dependents[dependent];
    if (dependencies != null) {
      dependencies.didRebuildDependent();
    }

    super.notifyDependent(oldWidget, dependent);
  }

  /// Remove dependencies for a dependent element
  void removeDependencies(Element dependent) {
    final dependencies = _dependents.remove(dependent);
    if (dependencies != null) {
      dependencies.deactivateDependent();
    }
  }

  @override
  void unmount() {
    // Clean up all dependencies when this element is unmounted
    for (final dependencies in _dependents.values) {
      dependencies.deactivateDependent();
    }
    _dependents.clear();

    super.unmount();
  }
}
