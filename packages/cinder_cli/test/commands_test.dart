import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cinder/cinder.dart' hide isEmpty;
import 'package:test/test.dart';

void main() {
  final packageDirectory = Directory.current.absolute;
  late Directory project;
  late Directory originalDirectory;
  late Directory compilationDirectory;
  late String cliKernel;

  Future<String> compileKernel(String entrypoint, String outputPath) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'compile',
      'kernel',
      '--packages=${packageDirectory.path}/.dart_tool/package_config.json',
      entrypoint,
      '--output=$outputPath',
    ], workingDirectory: packageDirectory.path);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 30));
      expect(
        code,
        0,
        reason: 'Dart compilation failed: ${await output}\n${await errors}',
      );
      return outputPath;
    } finally {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }

  setUpAll(() async {
    compilationDirectory = await Directory.systemTemp.createTemp(
      'cinder_cli_kernel_',
    );
    // Compile before measuring command completion so cold SDK startup does not
    // consume the deadline that detects hanging commands.
    cliKernel = await compileKernel(
      '${packageDirectory.path}/bin/cinder_cli.dart',
      '${compilationDirectory.path}/cinder_cli.dill',
    );
  });

  tearDownAll(() => compilationDirectory.delete(recursive: true));

  setUp(() async {
    originalDirectory = Directory.current;
    project = await Directory.systemTemp.createTemp('cinder_cli_test_');
    await File(
      '${project.path}/pubspec.yaml',
    ).writeAsString('name: cli_test_project\n');
    Directory.current = project;
  });

  tearDown(() async {
    final cinderDirectory = Directory(getCinderDirectory());
    if (await cinderDirectory.exists()) {
      await cinderDirectory.delete(recursive: true);
    }
    Directory.current = originalDirectory;
    await project.delete(recursive: true);
  });

  Future<({int exitCode, String output, String errors})> runCli(
    List<String> arguments, {
    String? entrypoint,
  }) async {
    final kernel = entrypoint == null
        ? cliKernel
        : await compileKernel(entrypoint, '${project.path}/runner.dill');
    final process = await Process.start(Platform.resolvedExecutable, [
      '--packages=${packageDirectory.path}/.dart_tool/package_config.json',
      kernel,
      ...arguments,
    ], workingDirectory: project.path);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(const Duration(seconds: 5));
      return (exitCode: code, output: await output, errors: await errors);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      fail(
        'CLI did not exit. Output: ${await output}; errors: ${await errors}',
      );
    } finally {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }

  test('logs get exits when the server has no buffered messages', () async {
    final server = LogServer();
    await server.start();
    addTearDown(server.close);

    final result = await runCli(['logs', '--mode', 'get', '--pid', '$pid']);

    expect(result.exitCode, 0, reason: result.errors);
    expect(result.output, isEmpty);
    expect(result.errors, isEmpty);
  });

  test('logs get prints buffered messages in order', () async {
    final server = LogServer();
    await server.start();
    addTearDown(server.close);
    server.log('first message');
    server.log('second message');

    final result = await runCli(['logs', '--mode', 'get', '--pid', '$pid']);

    expect(result.exitCode, 0, reason: result.errors);
    expect(result.output, 'first message\nsecond message\n');
  });

  test('logs get exits while the application keeps logging', () async {
    final server = LogServer();
    await server.start();
    addTearDown(server.close);
    server.log('ongoing message');
    final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      server.log('ongoing message');
    });
    addTearDown(timer.cancel);

    final result = await runCli(['logs', '--mode', 'get', '--pid', '$pid']);

    expect(result.exitCode, 0, reason: result.errors);
    expect(result.output, contains('ongoing message'));
  });

  test('unknown commands return a usage error without a stack trace', () async {
    final result = await runCli(['unknown-command']);

    expect(result.exitCode, 1);
    expect('${result.output}${result.errors}', contains('Usage:'));
    expect(result.errors, isNot(contains('Unhandled exception')));
  });

  test(
    'run forwards script options and preserves the child exit code',
    () async {
      final script = File('${project.path}/script.dart');
      await script.writeAsString('''
import 'dart:io';
void main(List<String> args) {
  print('script arguments: \${args.join(',')}');
  exitCode = 7;
}
''');

      final result = await runCli([
        'run',
        'dart',
        script.path,
        '--color',
        'blue',
      ]);

      expect(result.exitCode, 7, reason: result.errors);
      expect(result.output, contains('script arguments: --color,blue'));
    },
  );

  test('run returns to its caller after the child exits', () async {
    final script = File('${project.path}/exit_script.dart');
    await script.writeAsString(
      "import 'dart:io'; void main() { exitCode = 7; }",
    );
    final harness = File('${project.path}/runner.dart');
    await harness.writeAsString('''import 'package:cinder_cli/src/runner.dart';
import 'package:cinder_cli/src/deps/log.dart';
import 'package:scoped_deps/scoped_deps.dart';
Future<void> main() async {
  final code = await runScoped(
    () => Runner().run(['run', 'dart', 'exit_script.dart']),
    values: {logProvider},
  );
  print('runner-result: \$code');
}
''');

    final result = await runCli([], entrypoint: harness.path);

    expect(result.exitCode, 0, reason: result.errors);
    expect(result.output, contains('runner-result: 7'));
  });

  test(
    'shell stops after one termination signal and removes its files',
    () async {
      final process = await Process.start(Platform.resolvedExecutable, [
        '--packages=${packageDirectory.path}/.dart_tool/package_config.json',
        cliKernel,
        'shell',
      ], workingDirectory: project.path);
      final ready = Completer<void>();
      final output = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((text) {
            if (text.contains('Press Ctrl+C') && !ready.isCompleted) {
              ready.complete();
            }
          });
      final errors = process.stderr.transform(utf8.decoder).join();
      try {
        await ready.future.timeout(const Duration(seconds: 5));
        process.kill(ProcessSignal.sigterm);
        final code = await process.exitCode.timeout(const Duration(seconds: 3));

        expect(code, 0, reason: await errors);
        expect(File(getShellHandlePath()).existsSync(), isFalse);
        expect(
          FileSystemEntity.typeSync(getShellSocketPath()),
          FileSystemEntityType.notFound,
        );
      } finally {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        await output.cancel();
      }
    },
    skip: Platform.isWindows ? 'Unix domain shell requires POSIX' : false,
  );

  test(
    'log discovery does not resume stopped processes',
    () async {
      final server = LogServer();
      await server.start();
      addTearDown(server.close);
      server.log('buffered message');
      final worker = await Process.start('sleep', ['60']);
      try {
        worker.kill(ProcessSignal.sigstop);
        final metadata = File(getLogPortPathForPid(worker.pid));
        await metadata.writeAsString('${server.port}');

        final result = await runCli([
          'logs',
          '--mode',
          'get',
          '--pid',
          '${worker.pid}',
        ]);
        final status = await Process.run('ps', [
          '-o',
          'stat=',
          '-p',
          '${worker.pid}',
        ]);

        expect(result.exitCode, 0, reason: result.errors);
        expect(status.stdout.toString(), contains('T'));
      } finally {
        worker.kill(ProcessSignal.sigkill);
        await worker.exitCode;
      }
    },
    skip: Platform.isWindows ? 'Process suspension requires POSIX' : false,
  );
}
