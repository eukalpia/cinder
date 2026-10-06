import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cinder/src/utils/log_server.dart';
import 'package:test/test.dart';

void main() {
  late LogServer server;

  setUp(() async {
    server = LogServer();
    await server.start();
    server.log('secret output');
  });

  // Suites share this process ID and therefore its endpoint file; these tests
  // use the in-memory endpoint. The binding signal tests check the published
  // file in a separate process.
  tearDown(() => server.close());

  Future<int> handshakeStatus({
    String path = '/logs',
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', server.port!, path);
      request.headers
        ..set(HttpHeaders.connectionHeader, 'Upgrade')
        ..set(HttpHeaders.upgradeHeader, 'websocket')
        ..set('Sec-WebSocket-Version', '13')
        ..set('Sec-WebSocket-Key', base64.encode(List.filled(16, 7)));
      headers.forEach(request.headers.set);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  String bearer(String token) => 'Bearer $token';

  test('accepts a client presenting the published token', () async {
    final socket = await server.endpoint!.connect(snapshot: true);
    final messages = await socket.toList().timeout(const Duration(seconds: 2));

    expect(messages, hasLength(1));
    expect(
      (jsonDecode(messages.single as String) as Map)['message'],
      'secret output',
    );
  });

  test('rejects clients without a token', () async {
    expect(await handshakeStatus(), HttpStatus.unauthorized);
    await expectLater(
      WebSocket.connect('ws://127.0.0.1:${server.port}/logs?mode=get'),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('rejects clients with a wrong or malformed token', () async {
    final token = server.endpoint!.token;
    final wrong = token.replaceRange(0, 1, token.startsWith('A') ? 'B' : 'A');

    for (final credentials in [
      bearer(wrong),
      bearer('$token$token'),
      'Basic $token',
      token,
      'Bearer',
    ]) {
      expect(
        await handshakeStatus(
          headers: {HttpHeaders.authorizationHeader: credentials},
        ),
        HttpStatus.unauthorized,
        reason: credentials,
      );
    }
    await expectLater(
      LogServerEndpoint(port: server.port!, token: wrong).connect(),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('rejects browser requests even with a valid token', () async {
    final authorization = bearer(server.endpoint!.token);
    for (final origin in ['https://attacker.example', 'null', '']) {
      expect(
        await handshakeStatus(
          headers: {
            'Origin': origin,
            HttpHeaders.authorizationHeader: authorization,
          },
        ),
        HttpStatus.forbidden,
        reason: 'Origin: $origin',
      );
    }
    await expectLater(
      WebSocket.connect(
        server.endpoint!.uri().toString(),
        headers: {
          'Origin': 'http://localhost:${server.port}',
          HttpHeaders.authorizationHeader: authorization,
        },
      ),
      throwsA(isA<WebSocketException>()),
    );
  });

  test('rejected requests do not occupy client slots', () async {
    await server.close();
    server = LogServer(maxClients: 1);
    await server.start();
    server.log('after rejections');

    for (var attempt = 0; attempt < 5; attempt++) {
      expect(await handshakeStatus(), HttpStatus.unauthorized);
    }
    final socket = await server.endpoint!.connect(snapshot: true);

    expect(
      await socket.toList().timeout(const Duration(seconds: 2)),
      hasLength(1),
    );
  });

  test('each server uses a distinct, unguessable token', () async {
    final other = LogServer();
    await other.start();
    addTearDown(other.close);

    final token = server.endpoint!.token;
    expect(token, hasLength(greaterThanOrEqualTo(43)));
    expect(other.endpoint!.token, isNot(token));
  });

  group('LogServerEndpoint', () {
    test('round-trips through the endpoint file format', () {
      const endpoint = LogServerEndpoint(port: 4242, token: 'abc');
      final parsed = LogServerEndpoint.tryParse(endpoint.encode());

      expect(parsed?.port, 4242);
      expect(parsed?.token, 'abc');
    });

    test('rejects legacy port-only and malformed files', () {
      for (final contents in [
        '4242',
        '',
        'not json',
        '[]',
        '{"port": 4242}',
        '{"port": 4242, "token": ""}',
        '{"port": 0, "token": "abc"}',
        '{"port": 70000, "token": "abc"}',
        '{"port": "4242", "token": "abc"}',
      ]) {
        expect(LogServerEndpoint.tryParse(contents), isNull, reason: contents);
      }
    });

    test('keeps the token out of diagnostics and URLs', () {
      const endpoint = LogServerEndpoint(port: 4242, token: 'secret-token');

      expect('$endpoint', isNot(contains('secret-token')));
      expect('${endpoint.uri()}', isNot(contains('secret-token')));
      expect('${endpoint.uri(snapshot: true)}', endsWith('/logs?mode=get'));
    });
  });
}
