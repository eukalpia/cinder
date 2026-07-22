import 'dart:async';

/// A callback invoked when a [CancellationToken] is cancelled.
typedef CancellationCallback = void Function();

/// Thrown by [CancellationToken.throwIfCancelled] after cancellation.
final class CancellationException implements Exception {
  const CancellationException([this.reason]);

  /// Optional value supplied by the owner that requested cancellation.
  final Object? reason;

  @override
  String toString() {
    final value = reason;
    return value == null
        ? 'CancellationException: operation cancelled'
        : 'CancellationException: operation cancelled ($value)';
  }
}

/// A read-only cancellation signal passed to asynchronous work.
///
/// Cancellation is cooperative. Long-running operations should call
/// [throwIfCancelled] at natural suspension points or register a listener when
/// they own a resource that must be closed immediately.
final class CancellationToken {
  CancellationToken._();

  /// A token that is never cancelled.
  static final CancellationToken none = CancellationToken._();

  final Set<CancellationCallback> _listeners = <CancellationCallback>{};
  final Completer<void> _cancelled = Completer<void>();

  bool _isCancelled = false;
  Object? _reason;

  /// Whether cancellation has been requested.
  bool get isCancelled => _isCancelled;

  /// The optional reason supplied when cancellation was requested.
  Object? get reason => _reason;

  /// Completes once cancellation has been requested.
  Future<void> get whenCancelled => _cancelled.future;

  /// Throws [CancellationException] when cancellation has been requested.
  void throwIfCancelled() {
    if (_isCancelled) throw CancellationException(_reason);
  }

  /// Registers [listener] for synchronous cancellation notification.
  ///
  /// A listener added after cancellation is invoked immediately. Registering
  /// the same callback more than once has no additional effect.
  void addListener(CancellationCallback listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// Removes a previously registered cancellation callback.
  bool removeListener(CancellationCallback listener) {
    return _listeners.remove(listener);
  }

  void _cancel(Object? reason) {
    if (_isCancelled) return;

    _isCancelled = true;
    _reason = reason;
    _cancelled.complete();

    final listeners = List<CancellationCallback>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }
  }
}

/// Owns a [CancellationToken] and may request its cancellation.
final class CancellationTokenSource {
  CancellationTokenSource() : token = CancellationToken._();

  /// The read-only token passed to work owned by this source.
  final CancellationToken token;

  bool _disposed = false;

  /// Whether cancellation has already been requested.
  bool get isCancelled => token.isCancelled;

  /// Requests cancellation. Repeated calls are ignored.
  void cancel([Object? reason]) {
    if (_disposed) return;
    token._cancel(reason);
  }

  /// Cancels outstanding work and releases the source.
  void dispose([Object? reason]) {
    if (_disposed) return;
    token._cancel(reason ?? 'source disposed');
    _disposed = true;
  }
}

/// A cancellable asynchronous operation.
final class CinderTask<T> {
  CinderTask._(this._source, this.future);

  final CancellationTokenSource _source;

  /// The result of the operation.
  final Future<T> future;

  bool _isCompleted = false;

  /// The token observed by the operation.
  CancellationToken get token => _source.token;

  /// Whether cancellation has been requested.
  bool get isCancelled => token.isCancelled;

  /// Whether the operation has completed with either a value or an error.
  bool get isCompleted => _isCompleted;

  /// Requests cooperative cancellation while the task is still running.
  void cancel([Object? reason]) {
    if (!_isCompleted) _source.cancel(reason);
  }

  void _markCompleted() {
    _isCompleted = true;
  }
}

/// Owns cancellable work for a widget, controller, session, or application.
///
/// Call [dispose] from the owner's lifecycle method. Every operation receives a
/// token, all tokens are cancelled together, and disposal waits for cleanup
/// paths that are still unwinding.
final class CinderTaskScope {
  final Set<CancellationTokenSource> _sources = <CancellationTokenSource>{};
  final Set<Future<void>> _pending = <Future<void>>{};

  bool _disposed = false;

  /// Whether the scope has been disposed.
  bool get isDisposed => _disposed;

  /// Number of operations that have not completed yet.
  int get pendingTaskCount => _pending.length;

  /// Starts an operation owned by this scope.
  CinderTask<T> run<T>(
    FutureOr<T> Function(CancellationToken token) operation,
  ) {
    if (_disposed) {
      throw StateError('Cannot start work in a disposed CinderTaskScope.');
    }

    final source = CancellationTokenSource();
    _sources.add(source);

    final future = Future<T>.sync(() => operation(source.token));
    final task = CinderTask<T>._(source, future);

    late final Future<void> completion;
    completion = future
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() {
          task._markCompleted();
          _sources.remove(source);
          _pending.remove(completion);
        });
    _pending.add(completion);

    return task;
  }

  /// Requests cancellation for every task currently owned by the scope.
  void cancelAll([Object? reason]) {
    for (final source in List<CancellationTokenSource>.of(_sources)) {
      source.cancel(reason);
    }
  }

  /// Cancels all work and waits for owned operations to finish unwinding.
  Future<void> dispose([Object? reason]) async {
    if (_disposed) return;
    _disposed = true;
    cancelAll(reason ?? 'task scope disposed');

    final pending = List<Future<void>>.of(_pending);
    if (pending.isNotEmpty) await Future.wait(pending);

    _sources.clear();
    _pending.clear();
  }
}
