import 'dart:async';

/// A synchronous or asynchronous cleanup callback.
typedef ResourceDisposer = FutureOr<void> Function();

/// Owns disposable resources for a widget, controller, or terminal session.
///
/// Resources are released in reverse registration order. Disposal continues
/// after an individual cleanup failure so terminal state, subscriptions, and
/// timers do not leak because an earlier disposer threw.
final class CinderResourceScope {
  final List<ResourceDisposer> _disposers = <ResourceDisposer>[];

  bool _disposed = false;

  /// Whether [dispose] has already been called.
  bool get isDisposed => _disposed;

  /// Number of cleanup callbacks currently registered.
  int get resourceCount => _disposers.length;

  /// Registers a cleanup callback.
  void add(ResourceDisposer disposer) {
    if (_disposed) {
      throw StateError(
        'Cannot add resources to a disposed CinderResourceScope.',
      );
    }
    _disposers.add(disposer);
  }

  /// Registers [resource] with its cleanup function and returns the resource.
  T own<T>(T resource, FutureOr<void> Function(T resource) dispose) {
    add(() => dispose(resource));
    return resource;
  }

  /// Registers a [Timer] for automatic cancellation.
  Timer trackTimer(Timer timer) => own(timer, (value) => value.cancel());

  /// Registers a [StreamSubscription] for automatic cancellation.
  StreamSubscription<T> trackSubscription<T>(
    StreamSubscription<T> subscription,
  ) {
    return own(subscription, (value) => value.cancel());
  }

  /// Releases all resources in reverse registration order.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    Object? firstError;
    StackTrace? firstStackTrace;

    for (final disposer in _disposers.reversed) {
      try {
        await Future<void>.sync(disposer);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    _disposers.clear();

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  /// Begins disposal without blocking a synchronous owner lifecycle.
  void disposeDetached() {
    final zone = Zone.current;
    unawaited(dispose().catchError((Object error, StackTrace stackTrace) {
      zone.handleUncaughtError(error, stackTrace);
    }));
  }
}
