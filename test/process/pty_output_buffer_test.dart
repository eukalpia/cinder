import 'dart:convert';

import 'package:cinder/src/process/pty_output_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('retains the newest bytes of an unterminated line', () {
    final buffer = PtyOutputBuffer(maxLines: 100, maxBytes: 12);
    buffer.add('older\n');
    for (var i = 0; i < 1000; i++) {
      buffer.add('abcdefgh');
    }
    expect(buffer.lines, ['efghabcdefgh']);
    expect(buffer.byteLength, 12);
  });

  test(
    'trims at UTF-8 boundaries without splitting supplementary characters',
    () {
      final buffer = PtyOutputBuffer(maxLines: 100, maxBytes: 7);
      buffer.add('old\n🙂é🙂');
      expect(buffer.lines, ['é🙂']);
      expect(buffer.byteLength, 6);
      expect(utf8.encode(buffer.lines.single), [195, 169, 240, 159, 153, 130]);
    },
  );

  test('evicts old lines while preserving fragmented CRLF and blank lines', () {
    final buffer = PtyOutputBuffer(maxLines: 3, maxBytes: 100);
    buffer.add('discard\nhel');
    buffer.add('lo\r');
    buffer.add('\n\nthird');
    expect(buffer.lines, ['hello', '', 'third']);
    expect(buffer.byteLength, 12);
    buffer.add('\nlast\n');
    expect(buffer.lines, ['', 'third', 'last']);
    expect(buffer.byteLength, 12);
  });

  test('a single giant chunk retains only the bounded suffix', () {
    final buffer = PtyOutputBuffer(maxLines: 3, maxBytes: 10);
    buffer.add('${'x' * 1000000}tail');
    expect(buffer.lines, ['xxxxxxtail']);
    expect(buffer.byteLength, 10);
  });

  test('byte accounting includes line endings and resets after clear', () {
    final buffer = PtyOutputBuffer(maxLines: 10, maxBytes: 3);
    buffer.add('\n\n\n\n');
    expect(buffer.lines, ['', '', '']);
    expect(buffer.byteLength, 3);
    buffer.clear();
    buffer.add('é');
    expect(buffer.lines, ['é']);
    expect(buffer.byteLength, 2);
  });

  test('zero budgets disable retention', () {
    for (final buffer in [
      PtyOutputBuffer(maxLines: 0, maxBytes: 100),
      PtyOutputBuffer(maxLines: 100, maxBytes: 0),
    ]) {
      buffer.add('hello\nworld');
      expect(buffer.lines, isEmpty);
      expect(buffer.byteLength, 0);
    }
  });
}
