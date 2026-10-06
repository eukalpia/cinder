@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cinder/cinder.dart' hide isEmpty;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Exercises `runApp` in a separate process with real signals, environment
/// and a private HOME, so defaults reflect how applications are launched.
void main() {
  final packageConfig = File('.dart_tool/package_config.json').absolute.path;
  late Directory sandbox;
  late String kernel;
  late String backendKernel;

  setUpAll(() async {
    sandbox = await Directory.systemTemp.createTemp('cinder_run_app_');
    Future<String> compile(String fixture) async {
      final output = p.join(
        sandbox.path,
        '${p.basenameWithoutExtension(fixture)}.dill',
      );
      final result = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        '--packages=$packageConfig',
        'test/binding/fixtures/$fixture',
        '--output=$output',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      return output;
    }

    kernel = await compile('run_app_defaults.dart');
    backendKernel = await compile('stdio_backend_signals.dart');
  });

  tearDownAll(() => sandbox.delete(recursive: true));

  Future<_App> launch({
    bool assertions = false,
    Map<String, String> environment = const {},
    List<String> arguments = const [],
  }) async {
    final home = await sandbox.createTemp('home_');
    final project = await sandbox.createTemp('project_');
    await File(
      p.join(project.path, 'pubspec.yaml'),
    ).writeAsString('name: fixture_project\n');
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        if (assertions) '--enable-asserts',
        '--packages=$packageConfig',
        kernel,
        ...arguments,
      ],
      workingDirectory: project.path,
      includeParentEnvironment: false,
      environment: {
        'HOME': home.path,
        'PATH': Platform.environment['PATH'] ?? '',
        ...environment,
      },
    );
    final app = _App(process);
    addTearDown(app.kill);
    await app.waitFor('ready');
    return app;
  }

  test('StdioBackend keeps SIGTERM apart from SIGINT and retains it '
      'until the binding listens', () async {
    final process = await Process.start(Platform.resolvedExecutable, [
      '--packages=$packageConfig',
      backendKernel,
    ]);
    final app = _App(process);
    addTearDown(app.kill);
    await app.waitFor('ready');

    process.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    process.kill(ProcessSignal.sigint);
    await app.waitFor('interrupt');
    process.stdin.writeln('listen');
    await process.stdin.flush();

    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
    expect(app.lines, ['ready', 'interrupt', 'terminated']);
  });

  test('release builds leave development tools off', () async {
    final app = await launch();

    expect(app.report['overlay-shortcut'], 'false');
    expect(app.report['overlay-installed'], 'false');
    expect(app.report['log-endpoint'], '');
    await app.expectTerminatesCleanly();
  });

  test('debug builds enable development tools', () async {
    final app = await launch(assertions: true);

    expect(app.report['overlay-shortcut'], 'true');
    expect(app.report['overlay-installed'], 'true');
    expect(app.report['log-endpoint'], isNot(''));
    await app.expectTerminatesCleanly();
  });

  test('the published log endpoint is private and authenticated', () async {
    final app = await launch(assertions: true);
    final file = File(app.report['log-endpoint']!);
    final endpoint = LogServerEndpoint.tryParse(await file.readAsString())!;

    expect(file.statSync().mode & 0x1ff, 0x180, reason: 'mode 0600');
    expect(file.parent.statSync().mode & 0x1ff, 0x1c0, reason: 'mode 0700');

    final socket = await endpoint.connect(snapshot: true);
    final messages = await socket.toList().timeout(const Duration(seconds: 5));
    expect(
      messages.map((message) => jsonDecode(message as String)['message']),
      [endsWith('captured print output')],
    );
    await expectLater(
      WebSocket.connect('${endpoint.uri(snapshot: true)}'),
      throwsA(isA<WebSocketException>()),
    );
    await expectLater(
      WebSocket.connect(
        '${endpoint.uri(snapshot: true)}',
        headers: {
          'Origin': 'https://attacker.example',
          HttpHeaders.authorizationHeader: 'Bearer ${endpoint.token}',
        },
      ),
      throwsA(isA<WebSocketException>()),
    );
    await app.expectTerminatesCleanly();
  });

  test('environment variables enable tools without assertions', () async {
    final app = await launch(
      environment: {'CINDER_DEBUG_OVERLAY': '1', 'CINDER_LOG_SERVER': '1'},
    );

    expect(app.report['overlay-shortcut'], 'true');
    expect(app.report['overlay-installed'], 'true');
    expect(app.report['log-endpoint'], isNot(''));
    await app.expectTerminatesCleanly();
  });

  test('environment variables disable debug-build tools', () async {
    final app = await launch(
      assertions: true,
      environment: {'CINDER_DEBUG_OVERLAY': '0', 'CINDER_LOG_SERVER': '0'},
    );

    expect(app.report['overlay-shortcut'], 'false');
    expect(app.report['overlay-installed'], 'false');
    expect(app.report['log-endpoint'], '');
    await app.expectTerminatesCleanly();
  });

  test('runApp arguments override the environment', () async {
    final app = await launch(
      assertions: true,
      environment: {'CINDER_DEBUG_OVERLAY': '1', 'CINDER_LOG_SERVER': '1'},
      arguments: ['overlay=false', 'logs=false'],
    );

    expect(app.report['overlay-shortcut'], 'false');
    expect(app.report['overlay-installed'], 'false');
    expect(app.report['log-endpoint'], '');
    await app.expectTerminatesCleanly();
  });
}

final class _App {
  _App(this.process) {
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          lines.add(line);
          _updates.add(null);
        });
    unawaited(process.stdout.drain<void>());
  }

  final Process process;
  final lines = <String>[];
  final _updates = StreamController<void>.broadcast();

  Map<String, String> get report => {
    for (final line in lines)
      if (line.indexOf('=') case final index when index > 0)
        line.substring(0, index): line.substring(index + 1),
  };

  Future<void> waitFor(String line, {int count = 1}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (lines.where((candidate) => candidate == line).length < count) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        fail('Timed out waiting for "$line". stderr:\n${lines.join('\n')}');
      }
      await _updates.stream.first.timeout(remaining, onTimeout: () {});
    }
  }

  /// An interrupt is cancelled by the application's exit request handler,
  /// while a termination request exits regardless.
  Future<void> expectTerminatesCleanly() async {
    process.kill(ProcessSignal.sigint);
    await waitFor('exit-request');
    final vetoed = await process.exitCode
        .then<bool>((_) => false)
        .timeout(const Duration(milliseconds: 300), onTimeout: () => true);
    expect(vetoed, isTrue, reason: 'SIGINT should be cancelable');

    process.kill(ProcessSignal.sigterm);
    final code = await process.exitCode.timeout(const Duration(seconds: 10));
    expect(code, 0, reason: lines.join('\n'));
    expect(lines.where((line) => line == 'exit-request'), hasLength(1));
  }

  void kill() => process.kill(ProcessSignal.sigkill);
}
