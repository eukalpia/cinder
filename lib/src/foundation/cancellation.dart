import 'dart:async';
import 'dart:collection';

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

  void _releaseListeners() {
    _listeners.clear();
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

  void _close() {
    if (_disposed) return;
    token._releaseListeners();
    _disposed = true;
  }

  /// Cancels outstanding work and releases the source.
  void dispose([Object? reason]) {
    if (_disposed) return;
    token._cancel(reason ?? 'source disposed');
    _disposed = true;
  }
}

/// Lifecycle state of a task owned by [CinderTaskScope].
enum CinderTaskState { running, succeeded, failed, cancelled }

/// Immutable diagnostics retained after a task completes.
final class CinderTaskSnapshot {
  const CinderTaskSnapshot({
    required this.id,
    required this.label,
    required this.state,
    required this.startedAt,
    required this.completedAt,
    this.error,
  });

  final int id;
  final String label;
  final CinderTaskState state;
  final DateTime startedAt;
  final DateTime completedAt;
  final Object? error;

  Duration get elapsed => completedAt.difference(startedAt);
}

/// A cancellable asynchronous operation.
final class CinderTask<T> {
  CinderTask._({
    required this.id,
    required this.label,
    required this.startedAt,
    required CancellationTokenSource source,
    required this.future,
  }) : _source = source;

  final CancellationTokenSource _source;

  /// Monotonic identifier unique within the owning scope.
  final int id;

  /// Human-readable diagnostics label.
  final String label;

  /// When the operation was started.
  final DateTime startedAt;

  /// The result of the operation.
  final Future<T> future;

  CinderTaskState _state = CinderTaskState.running;
  DateTime? _completedAt;
  Object? _error;

  /// The token observed by the operation.
  CancellationToken get token => _source.token;

  /// Whether cancellation has been requested.
  bool get isCancelled => token.isCancelled;

  /// Whether the operation has completed with either a value or an error.
  bool get isCompleted => _state != CinderTaskState.running;

  CinderTaskState get state => _state;
  DateTime? get completedAt => _completedAt;
  Object? get error => _error;

  /// Requests cooperative cancellation while the task is still running.
  void cancel([Object? reason]) {
    if (!isCompleted) _source.cancel(reason);
  }

  void _complete(CinderTaskState state, [Object? error]) {
    if (isCompleted) return;
    _state = state;
    _error = error;
    _completedAt = DateTime.now();
    if (state == CinderTaskState.cancelled) {
      _source.dispose(error);
    } else {
      _source._close();
    }
  }

  CinderTaskSnapshot _snapshot() => CinderTaskSnapshot(
        id: id,
        label: label,
        state: state,
        startedAt: startedAt,
        completedAt: completedAt ?? DateTime.now(),
        error: error,
      );
}

/// Owns cancellable work for a widget, controller, session, or application.
///
/// The scope retains only a bounded diagnostics history. Completed task objects
/// and their futures are released immediately, preventing long-lived widgets
/// from accumulating every operation they have ever started.
final class CinderTaskScope {
  CinderTaskScope({this.historyLimit = 64})
      : assert(historyLimit >= 0, 'historyLimit must be non-negative');

  final int historyLimit;
  final Map<int, CinderTask<dynamic>> _active = <int, CinderTask<dynamic>>{};
  final Set<Future<void>> _pending = <Future<void>>{};
  final Queue<CinderTaskSnapshot> _history = Queue<CinderTaskSnapshot>();

  bool _disposed = false;
  int _nextTaskId = 1;
  int _startedTaskCount = 0;
  int _completedTaskCount = 0;

  /// Whether the scope has been disposed.
  bool get isDisposed => _disposed;

  /// Number of operations that have not completed yet.
  int get pendingTaskCount => _active.length;

  int get startedTaskCount => _startedTaskCount;
  int get completedTaskCount => _completedTaskCount;

  Iterable<CinderTask<dynamic>> get activeTasks =>
      List<CinderTask<dynamic>>.unmodifiable(_active.values);

  List<CinderTaskSnapshot> get history =>
      List<CinderTaskSnapshot>.unmodifiable(_history);

  /// Starts an operation owned by this scope.
  CinderTask<T> run<T>(
    FutureOr<T> Function(CancellationToken token) operation, {
    String? label,
  }) {
    if (_disposed) {
      throw StateError('Cannot start work in a disposed CinderTaskScope.');
    }

    final id = _nextTaskId++;
    final source = CancellationTokenSource();
    final future = Future<T>.sync(() => operation(source.token));
    final task = CinderTask<T>._(
      id: id,
      label: label ?? 'task-$id',
      startedAt: DateTime.now(),
      source: source,
      future: future,
    );

    _startedTaskCount++;
    _active[id] = task;

    late final Future<void> completion;
    completion = future.then<void>(
      (_) => task._complete(
        task.token.isCancelled
            ? CinderTaskState.cancelled
            : CinderTaskState.succeeded,
        task.token.reason,
      ),
      onError: (Object error, StackTrace _) {
        task._complete(
          task.token.isCancelled || error is CancellationException
              ? CinderTaskState.cancelled
              : CinderTaskState.failed,
          error,
        );
      },
    ).whenComplete(() {
      _active.remove(id);
      _pending.remove(completion);
      _completedTaskCount++;
      _remember(task._snapshot());
    });
    _pending.add(completion);

    return task;
  }

  void _remember(CinderTaskSnapshot snapshot) {
    if (historyLimit == 0) return;
    _history.addLast(snapshot);
    while (_history.length > historyLimit) {
      _history.removeFirst();
    }
  }

  /// Requests cancellation for every task currently owned by the scope.
  void cancelAll([Object? reason]) {
    for (final task in List<CinderTask<dynamic>>.of(_active.values)) {
      task.cancel(reason);
    }
  }

  /// Cancels all work and waits for owned operations to finish unwinding.
  Future<void> dispose([Object? reason]) async {
    if (_disposed) return;
    _disposed = true;
    cancelAll(reason ?? 'task scope disposed');

    final pending = List<Future<void>>.of(_pending);
    if (pending.isNotEmpty) await Future.wait(pending);

    _active.clear();
    _pending.clear();
  }

  /// Begins disposal without blocking a synchronous owner lifecycle.
  ///
  /// Cleanup errors are routed to the current zone instead of becoming
  /// unhandled asynchronous errors.
  void disposeDetached([Object? reason]) {
    final zone = Zone.current;
    unawaited(dispose(reason).catchError((Object error, StackTrace stackTrace) {
      zone.handleUncaughtError(error, stackTrace);
    }));
  }
}
