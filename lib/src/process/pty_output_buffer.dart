import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Recent output bounded by both line count and encoded UTF-8 bytes.
///
/// Each newline costs one byte, including empty lines. Oversized lines retain
/// their newest complete UTF-8 characters. Chunks avoid repeatedly copying a
/// growing unterminated line, and queues make history eviction amortized O(1).
@internal
class PtyOutputBuffer {
  final int maxLines;
  final int maxBytes;
  final _lines = ListQueue<_OutputLine>();
  int _byteLength = 0;

  PtyOutputBuffer({required this.maxLines, required this.maxBytes});

  List<String> get lines => List.unmodifiable(_lines.map((line) => line.text));
  int get byteLength => _byteLength;

  void add(String data) {
    if (maxLines == 0 || maxBytes == 0 || data.isEmpty) return;
    var start = 0;
    while (start < data.length) {
      final newline = data.indexOf('\n', start);
      final end = newline < 0 ? data.length : newline;
      if (_lines.isEmpty || _lines.last.complete) {
        _lines.add(_OutputLine());
      }
      final line = _lines.last;
      if (end > start) {
        final bytes = utf8.encode(data.substring(start, end));
        line.chunks.add(_OutputChunk(bytes));
        line.bytes += bytes.length;
        _byteLength += bytes.length;
      }
      if (newline >= 0) {
        if (line.chunks.isNotEmpty && line.chunks.last.data.last == 13) {
          final tail = line.chunks.removeLast();
          if (tail.length > 1) {
            tail.data = Uint8List.sublistView(
              tail.data,
              0,
              tail.data.length - 1,
            );
            line.chunks.add(tail);
          }
          line.bytes--;
          _byteLength--;
        }
        line.complete = true;
        line.bytes++;
        _byteLength++;
      }
      _trim();
      start = end + 1;
    }
  }

  void _trim() {
    while (_lines.length > maxLines ||
        (_byteLength > maxBytes && _lines.length > 1)) {
      _byteLength -= _lines.removeFirst().bytes;
    }
    if (_lines.isEmpty) return;
    final line = _lines.first;
    while (_byteLength > maxBytes && line.chunks.isNotEmpty) {
      final chunk = line.chunks.first;
      var count = _byteLength - maxBytes;
      if (count >= chunk.length) {
        count = chunk.length;
        line.chunks.removeFirst();
      } else {
        // Skip continuation bytes so the retained prefix is a full code point.
        while (count < chunk.length &&
            (chunk.data[chunk.start + count] & 0xc0) == 0x80) {
          count++;
        }
        chunk.start += count;
        if (chunk.length == 0) {
          line.chunks.removeFirst();
        } else if (chunk.data.length > maxBytes ||
            chunk.start >= chunk.data.length ~/ 2) {
          // Compact geometrically rather than copying a full retained line on
          // every one-byte append. Never retain an oversized discarded chunk.
          chunk.data = Uint8List.fromList(chunk.data.sublist(chunk.start));
          chunk.start = 0;
        }
      }
      line.bytes -= count;
      _byteLength -= count;
    }
    if (line.bytes == 0 && !line.complete) _lines.removeFirst();
  }

  void clear() {
    _lines.clear();
    _byteLength = 0;
  }
}

class _OutputLine {
  final chunks = ListQueue<_OutputChunk>();
  int bytes = 0;
  bool complete = false;

  String get text {
    final builder = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      builder.add(Uint8List.sublistView(chunk.data, chunk.start));
    }
    return utf8.decode(builder.takeBytes());
  }
}

class _OutputChunk {
  Uint8List data;
  int start = 0;
  _OutputChunk(this.data);
  int get length => data.length - start;
}
