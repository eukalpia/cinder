// Riverpod 3 keeps the listenable type hierarchy internal.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:cinder/cinder.dart';
import 'package:riverpod/src/internals.dart';

import 'framework.dart';

/// Extension methods on [BuildContext] for interacting with Riverpod.
extension ProviderContext on BuildContext {
  /// Read a provider value without listening to changes.
  T read<T>(ProviderListenable<T> provider) {
    final container = ProviderScope.containerOf(this, listen: false);
    return container.read(provider);
  }

  /// Watch a provider and rebuild this widget when it changes.
  ///
  /// Call this only while building a widget.
  T watch<T>(ProviderListenable<T> provider) {
    final element = this as Element;
    assert(element.mounted, 'watch called on an unmounted widget');

    final scopeElement = ProviderScope.scopeElementOf(this);
    final dependencies = scopeElement.getDependencies(element);
    return dependencies.watch(provider, scopeElement.container);
  }

  /// Listen to a provider without implicitly rebuilding this widget.
  ///
  /// The subscription is owned by the element and disposed automatically.
  void listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    bool fireImmediately = false,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final element = this as Element;
    final scopeElement = ProviderScope.scopeElementOf(this, listen: false);
    final dependencies = scopeElement.getDependencies(element);

    dependencies.listen(
      provider,
      listener,
      scopeElement.container,
      fireImmediately: fireImmediately,
      onError: onError,
    );
  }

  /// Create a manually managed provider subscription.
  ProviderSubscription<T> subscribe<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener, {
    bool fireImmediately = false,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    final container = ProviderScope.containerOf(this, listen: false);
    return container.listen<T>(
      provider,
      listener,
      fireImmediately: fireImmediately,
      onError: onError,
    );
  }

  /// Refresh a provider and return its refreshed value.
  T refresh<T>(Refreshable<T> provider) {
    final container = ProviderScope.containerOf(this, listen: false);
    return container.refresh(provider);
  }

  /// Invalidate a provider or family.
  void invalidate(ProviderOrFamily provider) {
    final container = ProviderScope.containerOf(this, listen: false);
    container.invalidate(provider);
  }
}
