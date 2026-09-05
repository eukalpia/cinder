import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cinder/src/utils/log_server.dart';
import 'package:test/test.dart';

void main() {
  test('concurrent start rejects a second listener', () async {
    final server = LogServer();
    final first = server.start();
    try {
      await expectLater(server.start(), throwsStateError);
      await first;
    } finally {
      await first;
      await server.close();
    }
  });

  test('closing during startup cannot leave a listening server', () async {
    final server = LogServer();
    final start = server.start().catchError((Object _) {});
    await server.close();
    await start;
    expect(server.port, isNull);
  });

  test(
    'client limit rejects connections and permits reconnect after close',
    () async {
      final server = LogServer(maxClients: 1);
      await server.start();
      server.log('ready');
      final url = 'ws://127.0.0.1:${server.port}/logs';
      try {
        final first = await WebSocket.connect(url);
        final messages = StreamIterator(first);
        expect(await messages.moveNext(), isTrue);
        expect(
          (jsonDecode(messages.current as String) as Map)['message'],
          'ready',
        );
        await expectLater(
          WebSocket.connect(url),
          throwsA(isA<WebSocketException>()),
        );
        await messages.cancel();
        await first.close();
        // Receipt of snapshot completion proves the replacement connection closed.
        final retry = await WebSocket.connect('$url?mode=get');
        expect(await retry.toList(), hasLength(1));
      } finally {
        await server.close();
      }
    },
  );

  test('a log flood cannot indefinitely delay server shutdown', () async {
    final server = LogServer(maxPendingClientBytes: 4096);
    await server.start();
    server.log('ready');
    final client = await WebSocket.connect(
      'ws://127.0.0.1:${server.port}/logs',
    );
    final messages = StreamIterator(client);
    await messages.moveNext();
    for (var index = 0; index < 10000; index++) {
      server.log('message $index ${'x' * 1000}');
    }
    await server.close().timeout(const Duration(seconds: 3));
    await messages.cancel();
    await client.close();
    expect(server.buffer, isEmpty);
  });
}
