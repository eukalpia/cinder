import 'package:cinder/cinder.dart';
import 'package:riverpod/riverpod.dart';

/// Manages provider subscriptions for a single element.
///
/// This class tracks all provider subscriptions for an element and ensures
/// proper cleanup during rebuilds and disposal.
class ProviderDependencies {
  ProviderDependencies(this.dependent);

  /// The element that owns these dependencies.
  final Element dependent;

  /// The current provider container.
  ProviderContainer? _container;

  /// Active subscriptions from the current build.
  final Map<ProviderListenable, ProviderSubscription> _watchers = {};
  final Map<ProviderListenable, ProviderSubscription> _listeners = {};

  /// Previous subscriptions from the last build, retained for reuse.
  final Map<ProviderListenable, ProviderSubscription> _oldWatchers = {};
  final Map<ProviderListenable, ProviderSubscription> _oldListeners = {};

  /// Watch a provider and rebuild when it changes.
  T watch<T>(ProviderListenable<T> provider, ProviderContainer container) {
    if (_container != null && _container != container) {
      _deactivateAll();
    }
    _container = container;

    if (!_watchers.containsKey(provider)) {
      if (_oldWatchers.containsKey(provider)) {
        _watchers[provider] = _oldWatchers.remove(provider)!;
      } else {
        final subscription = container.listen<T>(
          provider,
          (previous, next) {
            if (_watchers.containsKey(provider) ||
                _oldWatchers.containsKey(provider)) {
              if (dependent.mounted) {
                dependent.markNeedsBuild();
              }
            }
          },
          fireImmediately: false,
        );
        _watchers[provider] = subscription;
      }
    }

    return (_watchers[provider] as ProviderSubscription<T>).read();
  }

  /// Listen to a provider with a callback without rebuilding implicitly.
  void listen<T>(
    ProviderListenable<T> provider,
    void Function(T? previous, T next) listener,
    ProviderContainer container, {
    bool fireImmediately = false,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) {
    if (_container != null && _container != container) {
      _deactivateAll();
    }
    _container = container;

    _listeners.remove(provider)?.close();
    _oldListeners.remove(provider)?.close();

    _listeners[provider] = container.listen<T>(
      provider,
      listener,
      fireImmediately: fireImmediately,
      onError: onError,
    );
  }

  /// Rotate active subscriptions after a dependent rebuild.
  void didRebuildDependent() {
    for (final subscription in _oldWatchers.values) {
      subscription.close();
    }
    for (final subscription in _oldListeners.values) {
      subscription.close();
    }

    _oldWatchers
      ..clear()
      ..addAll(_watchers);
    _watchers.clear();

    _oldListeners
      ..clear()
      ..addAll(_listeners);
    _listeners.clear();
  }

  /// Release every subscription owned by this dependent.
  void deactivateDependent() {
    _deactivateAll();
  }

  void _deactivateAll() {
    for (final subscription in _watchers.values) {
      subscription.close();
    }
    for (final subscription in _oldWatchers.values) {
      subscription.close();
    }
    for (final subscription in _listeners.values) {
      subscription.close();
    }
    for (final subscription in _oldListeners.values) {
      subscription.close();
    }

    _watchers.clear();
    _oldWatchers.clear();
    _listeners.clear();
    _oldListeners.clear();
    _container = null;
  }
}
