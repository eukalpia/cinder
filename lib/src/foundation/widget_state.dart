/// Interaction states shared by production controls.
enum WidgetState {
  hovered,
  focused,
  pressed,
  dragged,
  selected,
  scrolledUnder,
  disabled,
  error,
}

/// Resolves a value from the current set of [WidgetState] values.
abstract interface class WidgetStateProperty<T> {
  const WidgetStateProperty();

  T resolve(Set<WidgetState> states);

  /// Resolves either a plain value or a state-aware value.
  static T resolveAs<T>(T value, Set<WidgetState> states) {
    if (value is WidgetStateProperty<T>) {
      return value.resolve(states);
    }
    return value;
  }

  /// Creates a state property backed by [resolver].
  static WidgetStateProperty<T> resolveWith<T>(
    WidgetStateResolver<T> resolver,
  ) {
    return _WidgetStatePropertyWith<T>(resolver);
  }

  /// Creates a property that returns [value] for every state set.
  static WidgetStateProperty<T> all<T>(T value) {
    return WidgetStatePropertyAll<T>(value);
  }
}

typedef WidgetStateResolver<T> = T Function(Set<WidgetState> states);

final class WidgetStatePropertyAll<T> implements WidgetStateProperty<T> {
  const WidgetStatePropertyAll(this.value);

  final T value;

  @override
  T resolve(Set<WidgetState> states) => value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WidgetStatePropertyAll<T> && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;
}

final class WidgetStateMapper<T> implements WidgetStateProperty<T> {
  WidgetStateMapper(Map<Set<WidgetState>, T> values, {required this.fallback})
      : _entries = List<MapEntry<Set<WidgetState>, T>>.unmodifiable(
          values.entries.map(
            (entry) => MapEntry<Set<WidgetState>, T>(
              Set<WidgetState>.unmodifiable(entry.key),
              entry.value,
            ),
          ),
        );

  final List<MapEntry<Set<WidgetState>, T>> _entries;
  final T fallback;

  @override
  T resolve(Set<WidgetState> states) {
    MapEntry<Set<WidgetState>, T>? best;
    for (final entry in _entries) {
      if (!states.containsAll(entry.key)) continue;
      if (best == null || entry.key.length > best.key.length) {
        best = entry;
      }
    }
    return best?.value ?? fallback;
  }
}

final class _WidgetStatePropertyWith<T> implements WidgetStateProperty<T> {
  const _WidgetStatePropertyWith(this._resolver);

  final WidgetStateResolver<T> _resolver;

  @override
  T resolve(Set<WidgetState> states) => _resolver(states);
}

/// Mutable helper used by stateful controls to keep state transitions coherent.
final class WidgetStatesController {
  WidgetStatesController([Iterable<WidgetState> initialStates = const []])
      : _states = <WidgetState>{...initialStates};

  final Set<WidgetState> _states;

  Set<WidgetState> get value => Set<WidgetState>.unmodifiable(_states);

  bool contains(WidgetState state) => _states.contains(state);

  bool update(WidgetState state, bool enabled) {
    return enabled ? _states.add(state) : _states.remove(state);
  }

  bool replace(Iterable<WidgetState> states) {
    final next = <WidgetState>{...states};
    if (_states.length == next.length && _states.containsAll(next)) {
      return false;
    }
    _states
      ..clear()
      ..addAll(next);
    return true;
  }
}
