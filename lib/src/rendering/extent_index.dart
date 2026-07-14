import 'dart:collection';

/// A stable-ID variable-extent index backed by a Fenwick tree.
///
/// Known extents survive render-object eviction and item reordering. Prefix
/// sums and offset-to-index lookups are O(log n), so a lazy viewport never has
/// to walk from item zero merely because child render objects were recycled.
class ExtentIndex<T extends Object> {
  ExtentIndex({
    double estimatedExtent = 1.0,
    this.maxCachedExtents = 200000,
  }) : _estimatedExtent = estimatedExtent > 0 ? estimatedExtent : 1.0;

  final int maxCachedExtents;
  double _estimatedExtent;

  final LinkedHashMap<T, double> _extentCache = LinkedHashMap<T, double>();
  List<T> _ids = <T>[];
  final Map<T, int> _indices = <T, int>{};
  List<double> _values = <double>[];
  List<double> _tree = <double>[0.0];

  List<T> get ids => List<T>.unmodifiable(_ids);
  int get length => _ids.length;
  bool get isEmpty => _ids.isEmpty;
  bool get isNotEmpty => _ids.isNotEmpty;
  double get estimatedExtent => _estimatedExtent;
  double get totalExtent => _prefixSum(_ids.length);
  int get cachedExtentCount => _extentCache.length;

  set estimatedExtent(double value) {
    if (value <= 0 || value == _estimatedExtent) return;
    _estimatedExtent = value;
    syncItems(_ids);
  }

  bool containsId(T id) => _indices.containsKey(id);
  int? indexOf(T id) => _indices[id];
  T idAt(int index) => _ids[index];

  void syncItems(Iterable<T> itemIds) {
    final nextIds = List<T>.of(itemIds, growable: false);
    final seen = <T>{};
    for (final id in nextIds) {
      if (!seen.add(id)) {
        throw ArgumentError.value(id, 'itemIds', 'Item IDs must be unique.');
      }
    }

    _ids = nextIds;
    _indices
      ..clear()
      ..addEntries(<MapEntry<T, int>>[
        for (var index = 0; index < _ids.length; index++)
          MapEntry<T, int>(_ids[index], index),
      ]);

    _values = List<double>.generate(
      _ids.length,
      (index) => _extentCache[_ids[index]] ?? _estimatedExtent,
      growable: false,
    );
    _rebuildTree();
    _evictUnusedExtents();
  }

  double extentAt(int index) => _values[index];

  double? knownExtentForId(T id) => _extentCache[id];

  double offsetOfIndex(int index) {
    if (_ids.isEmpty || index <= 0) return 0.0;
    return _prefixSum(index.clamp(0, _ids.length).toInt());
  }

  double? offsetOfId(T id) {
    final index = _indices[id];
    return index == null ? null : offsetOfIndex(index);
  }

  /// Returns the item intersecting [offset].
  int indexAtOffset(double offset) {
    if (_ids.isEmpty) return 0;
    if (offset <= 0) return 0;
    if (offset >= totalExtent) return _ids.length - 1;

    var index = 0;
    var accumulated = 0.0;
    var bit = 1;
    while ((bit << 1) <= _ids.length) {
      bit <<= 1;
    }

    while (bit != 0) {
      final next = index + bit;
      if (next <= _ids.length && accumulated + _tree[next] <= offset) {
        index = next;
        accumulated += _tree[next];
      }
      bit >>= 1;
    }

    return index.clamp(0, _ids.length - 1).toInt();
  }

  /// Records a measured extent. Returns true when the index changed.
  bool updateExtent(T id, double extent) {
    if (!extent.isFinite || extent < 0) return false;
    final normalized = extent == 0 ? 0.000001 : extent;

    _rememberExtent(id, normalized);
    final index = _indices[id];
    if (index == null) return false;

    final old = _values[index];
    if ((old - normalized).abs() < 0.000001) return false;
    _values[index] = normalized;
    _add(index + 1, normalized - old);
    return true;
  }

  /// Drops a measurement while retaining the item at its estimated extent.
  bool invalidateExtent(T id) {
    _extentCache.remove(id);
    final index = _indices[id];
    if (index == null) return false;
    final old = _values[index];
    if ((old - _estimatedExtent).abs() < 0.000001) return false;
    _values[index] = _estimatedExtent;
    _add(index + 1, _estimatedExtent - old);
    return true;
  }

  void clearExtentCache() {
    _extentCache.clear();
    _values = List<double>.filled(_ids.length, _estimatedExtent);
    _rebuildTree();
  }

  void _rememberExtent(T id, double extent) {
    _extentCache.remove(id);
    _extentCache[id] = extent;
    _evictUnusedExtents();
  }

  void _evictUnusedExtents() {
    if (maxCachedExtents <= 0) return;
    while (_extentCache.length > maxCachedExtents) {
      T? victim;
      for (final id in _extentCache.keys) {
        if (!_indices.containsKey(id)) {
          victim = id;
          break;
        }
      }
      if (victim == null) break;
      _extentCache.remove(victim);
    }
  }

  void _rebuildTree() {
    _tree = List<double>.filled(_values.length + 1, 0.0);
    for (var i = 1; i <= _values.length; i++) {
      _tree[i] += _values[i - 1];
      final parent = i + (i & -i);
      if (parent <= _values.length) {
        _tree[parent] += _tree[i];
      }
    }
  }

  void _add(int oneBasedIndex, double delta) {
    var index = oneBasedIndex;
    while (index < _tree.length) {
      _tree[index] += delta;
      index += index & -index;
    }
  }

  double _prefixSum(int count) {
    var index = count.clamp(0, _ids.length).toInt();
    var result = 0.0;
    while (index > 0) {
      result += _tree[index];
      index -= index & -index;
    }
    return result;
  }
}
