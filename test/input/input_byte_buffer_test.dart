import 'package:cinder/src/keyboard/input_byte_buffer.dart';
import 'package:test/test.dart';

void main() {
  test('consuming a large burst never shifts the remaining bytes', () {
    final buffer = InputByteBuffer(1024 * 1024);
    final bytes = List<int>.generate(100000, (index) => index & 255);
    buffer.addAll(bytes);
    final copies = buffer.copiedBytes;
    for (var index = 0; index < bytes.length; index++) {
      expect(buffer.first, bytes[index]);
      buffer.removeRange(0, 1);
    }
    expect(buffer, isEmpty);
    expect(buffer.copiedBytes, copies);
    expect(buffer.storageBytes, lessThanOrEqualTo(65536));
  });

  test('interleaved append and consume stay bounded and preserve order', () {
    final buffer = InputByteBuffer(32);
    for (var round = 0; round < 100; round++) {
      buffer.addAll(List<int>.generate(16, (index) => round + index));
      expect(buffer.toList(), List<int>.generate(16, (index) => round + index));
      buffer.removeRange(0, 12);
      buffer.addAll([200, 201, 202, 203]);
      expect(buffer, [
        round + 12,
        round + 13,
        round + 14,
        round + 15,
        200,
        201,
        202,
        203,
      ]);
      expect(buffer.storageBytes, lessThanOrEqualTo(32));
      buffer.clear();
    }
  });

  test('overflow rejects before appending or changing pending bytes', () {
    final buffer = InputByteBuffer(4)..addAll([1, 2, 3]);
    expect(() => buffer.addAll([4, 5]), throwsStateError);
    expect(buffer, [1, 2, 3]);
  });
}
