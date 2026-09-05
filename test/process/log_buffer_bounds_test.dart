import 'package:cinder/src/utils/log_server.dart';
import 'package:test/test.dart';

void main() {
  test('default log history bounds retained message storage', () {
    final server = LogServer();
    final message = 'x' * (400 * 1024);
    server.log('first: $message');
    server.log('second: $message');

    final retainedBytes = server.buffer.fold<int>(
      0,
      (total, entry) => total + entry.message.length * 2,
    );
    expect(retainedBytes, lessThanOrEqualTo(1024 * 1024));
    expect(server.buffer.last.message, startsWith('second:'));
  });

  test('rejects a negative history entry limit at construction', () {
    expect(() => LogServer(maxBufferSize: -1), throwsArgumentError);
  });

  test('zero history entries retains no messages', () {
    final server = LogServer(maxBufferSize: 0);
    server.log('not retained');
    expect(server.buffer, isEmpty);
  });

  test(
    'enforces byte and entry limits while retaining the newest messages',
    () {
      final server = LogServer(maxBufferSize: 2, maxBufferBytes: 12);
      server.log('one');
      server.log('two');
      server.log('three');
      expect(server.buffer.map((entry) => entry.message), ['three']);
      server.log('x');
      expect(server.buffer.map((entry) => entry.message), ['three', 'x']);
      server.log('y');
      expect(server.buffer.map((entry) => entry.message), ['x', 'y']);
    },
  );

  test('oversized messages preserve existing bounded history', () {
    final server = LogServer(maxBufferBytes: 8);
    server.log('keep');
    server.log('too large');
    expect(server.buffer.single.message, 'keep');
  });

  test('counts UTF-16 storage for non-ASCII history', () {
    final server = LogServer(maxBufferBytes: 8);
    server.log('😀😀');
    server.log('界');
    expect(server.buffer.single.message, '界');
  });

  test('zero byte budget retains no messages including empty messages', () {
    final server = LogServer(maxBufferBytes: 0);
    server.log('');
    server.log('not retained');
    expect(server.buffer, isEmpty);
  });

  test('rejects a negative byte budget at construction', () {
    expect(() => LogServer(maxBufferBytes: -1), throwsArgumentError);
  });
}
