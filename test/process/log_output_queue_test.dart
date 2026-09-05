import 'dart:async';

import 'package:cinder/src/utils/log_output_queue.dart';
import 'package:test/test.dart';

void main() {
  test('a blocked consumer has one send and bounded pending storage', () async {
    final blocked = Completer<void>();
    final sent = <String>[];
    var closes = 0;
    final queue = LogOutputQueue(
      maxBytes: 12,
      maxMessages: 3,
      send: (message) {
        sent.add(message);
        return blocked.future;
      },
      onClose: () => closes++,
    );
    queue.add('one');
    queue.add('two');
    expect(sent, ['one']);
    expect(queue.pendingBytes, 12);
    queue.add('x');
    expect(queue.isClosed, isTrue);
    expect(queue.pendingBytes, 0);
    expect(closes, 1);
    blocked.complete();
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['one']);
    expect(queue.pendingBytes, 0);
  });

  test('replay is lazy and precedes live messages', () async {
    final gates = <Completer<void>>[];
    final sent = <String>[];
    var encoded = 0;
    final queue = LogOutputQueue(
      maxBytes: 100,
      maxMessages: 10,
      replay: ['a', 'b', 'c'].map((value) {
        encoded++;
        return value;
      }),
      send: (message) {
        sent.add(message);
        final gate = Completer<void>();
        gates.add(gate);
        return gate.future;
      },
      onClose: () {},
    );
    queue.start();
    queue.add('live');
    expect(encoded, 1);
    for (var index = 0; index < 4; index++) {
      gates[index].complete();
      await Future<void>.delayed(Duration.zero);
    }
    expect(sent, ['a', 'b', 'c', 'live']);
    expect(queue.pendingBytes, 0);
    queue.close();
  });

  test('an entry count cap also bounds empty messages', () {
    final gate = Completer<void>();
    final queue = LogOutputQueue(
      maxBytes: 10,
      maxMessages: 2,
      send: (_) => gate.future,
      onClose: () {},
    );
    queue.add('');
    queue.add('');
    queue.add('');
    expect(queue.isClosed, isTrue);
    gate.complete();
  });

  test('send errors close the queue and discard queued references', () async {
    var closed = false;
    final queue = LogOutputQueue(
      maxBytes: 100,
      maxMessages: 10,
      send: (_) async => throw StateError('disconnected'),
      onClose: () => closed = true,
    );
    queue.add('message');
    await Future<void>.delayed(Duration.zero);
    expect(closed, isTrue);
    expect(queue.pendingBytes, 0);
  });
}
