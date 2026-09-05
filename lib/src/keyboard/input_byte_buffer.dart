import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Bounded parser storage with constant-time prefix consumption.
///
/// The List interface supplies read operations used by the protocol decoders.
/// Mutation is restricted to appending bytes, consuming a prefix, and clearing.
@internal
final class InputByteBuffer extends ListBase<int> {
  InputByteBuffer(this.maxBytes) {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  }

  final int maxBytes;
  Uint8List _bytes = Uint8List(0);
  int _head = 0;
  int _tail = 0;
  int _copiedBytes = 0;

  @visibleForTesting
  int get copiedBytes => _copiedBytes;
  @visibleForTesting
  int get storageBytes => _bytes.length;

  @override
  int get length => _tail - _head;
  @override
  set length(int value) => throw UnsupportedError('Use append or consume');
  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this);
    return _bytes[_head + index];
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Pending input is immutable');

  @override
  void addAll(Iterable<int> iterable) {
    final incoming = iterable is List<int> ? iterable : iterable.toList();
    if (incoming.isEmpty) return;
    final required = length + incoming.length;
    if (required > maxBytes) throw StateError('Input buffer limit exceeded');
    if (_tail + incoming.length > _bytes.length) {
      final pending = length;
      if (required > _bytes.length) {
        final capacity = math.min(
          maxBytes,
          math.max(required, math.max(256, _bytes.length * 2)),
        );
        final replacement = Uint8List(capacity);
        replacement.setRange(0, pending, _bytes, _head);
        _bytes = replacement;
      } else {
        _bytes.setRange(0, pending, _bytes, _head);
      }
      _copiedBytes += pending;
      _head = 0;
      _tail = pending;
    }
    _bytes.setRange(_tail, _tail + incoming.length, incoming);
    _tail += incoming.length;
    _copiedBytes += incoming.length;
  }

  @override
  void removeRange(int start, int end) {
    RangeError.checkValidRange(start, end, length);
    if (start != 0) throw UnsupportedError('Only prefixes can be consumed');
    _head += end;
    if (_head == _tail) clear();
  }

  @override
  void clear() {
    _head = 0;
    _tail = 0;
    // Do not retain a large paste allocation throughout an otherwise idle app.
    if (_bytes.length > 65536) _bytes = Uint8List(0);
  }
}
