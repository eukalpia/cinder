import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cinder/src/process/pty_controller.dart';
import 'package:test/test.dart';

void main() {
  final fixture = File('test/process/fixtures/pty_process.dart').absolute.path;
  const deadline = Duration(seconds: 10);

  PtyController controllerFor(
    String mode, {
    List<String> arguments = const [],
    int maxBufferLines = 10000,
    int maxBufferBytes = 8 * 1024 * 1024,
    void Function(String)? onOutput,
    void Function(int)? onExit,
  }) {
    final controller = PtyController(
      command: Platform.resolvedExecutable,
      arguments: [fixture, mode, ...arguments],
      maxBufferLines: maxBufferLines,
      maxBufferBytes: maxBufferBytes,
      onOutput: onOutput,
      onExit: onExit,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> startInteractive(PtyController controller) async {
    final ready = Completer<void>();
    var output = '';
    void capture(String chunk) {
      output += chunk;
      if (output.contains('READY:') && !ready.isCompleted) ready.complete();
    }

    controller.addOutputCallback(capture);
    try {
      await controller.start(columns: 80, rows: 24);
      await ready.future.timeout(deadline);
    } finally {
      controller.removeOutputCallback(capture);
    }
  }

  test('default controller has a platform shell and no process', () async {
    final controller = PtyController();
    expect(controller.command, isNotEmpty);
    expect(controller.status, PtyStatus.notStarted);
    expect(controller.pid, isNull);
    await controller.dispose();
  });

  test(
    'child sees a native terminal with startup and resized dimensions',
    () async {
      final initial = Completer<void>();
      final resized = Completer<void>();
      var output = '';
      final controller = controllerFor(
        'dimensions',
        onOutput: (chunk) {
          output += chunk;
          if (output.contains('SIZE:93:27') && !initial.isCompleted) {
            initial.complete();
          }
          if (output.contains('SIZE:111:39') && !resized.isCompleted) {
            resized.complete();
          }
        },
      );
      await controller.start(columns: 93, rows: 27);
      await initial.future.timeout(deadline, onTimeout: () => fail(output));
      expect(output, contains('TTY:true:true:true'));
      controller.resize(111, 39);
      controller.write(Platform.isWindows ? 'size\r' : 'size\n');
      await resized.future.timeout(deadline, onTimeout: () => fail(output));
      expect(controller.columns, 111);
      expect(controller.rows, 39);
    },
  );

  test('preserves literal arguments and child exit code', () async {
    final exited = Completer<int>();
    var output = '';
    final arguments = [
      'hello world',
      "single'quote",
      r'$CINDER_MUST_NOT_EXPAND',
      'x; printf injected',
      'double"quote',
      'trailing\\',
      '🙂 café',
      '',
    ];
    final controller = controllerFor(
      'arguments',
      arguments: arguments,
      onOutput: (data) => output += data,
      onExit: exited.complete,
    );

    await controller.start(columns: 512, rows: 24);
    expect(await exited.future.timeout(deadline), 7);
    expect(output, contains(jsonEncode(arguments)));
    expect(controller.exitCode, 7);
    expect(controller.status, PtyStatus.exited);
  });

  test(
    'writes to the process without resize injecting application input',
    () async {
      final received = Completer<void>();
      var output = '';
      final controller = controllerFor(
        'interactive',
        onOutput: (data) {
          output += data;
          if (output.contains('INPUT:hello') && !received.isCompleted) {
            received.complete();
          }
        },
      );
      await startInteractive(controller);
      controller.resize(100, 30);
      expect(controller.columns, 100);
      expect(controller.rows, 30);
      controller.write(Platform.isWindows ? 'hello\r' : 'hello\n');
      await received.future.timeout(deadline);
      expect(output, contains('INPUT:hello'));
    },
  );

  test('buffers complete lines and applies the line limit', () async {
    final exited = Completer<int>();
    final controller = controllerFor(
      'lines',
      maxBufferLines: 2,
      onExit: exited.complete,
    );
    await controller.start(columns: 80, rows: 24);
    await exited.future.timeout(deadline);
    expect(controller.outputBuffer, ['second', 'third']);
    controller.clearBuffer();
    expect(controller.outputBuffer, isEmpty);
  });

  test('byte-limited history still delivers all output callbacks', () async {
    final exited = Completer<int>();
    var output = '';
    final controller = controllerFor(
      'lines',
      maxBufferBytes: 8,
      onOutput: (chunk) => output += chunk,
      onExit: exited.complete,
    );
    await controller.start(columns: 80, rows: 24);
    await exited.future.timeout(deadline);
    expect(controller.outputBuffer, ['third']);
    expect(output, contains('first'));
    expect(output, contains('second'));
  });

  test(
    'native children keep exit status while dart:io reaps other processes',
    () async {
      final unrelated = await Process.start(Platform.resolvedExecutable, [
        fixture,
        'interactive',
      ]);
      addTearDown(() async {
        unrelated.kill();
        await unrelated.exitCode;
      });
      final subscription = unrelated.stdout.listen((_) {});
      final stderrSubscription = unrelated.stderr.listen((_) {});
      addTearDown(subscription.cancel);
      addTearDown(stderrSubscription.cancel);
      for (final code in [0, 7, 127, 143, 255]) {
        final exited = Completer<int>();
        final controller = controllerFor(
          'exit',
          arguments: ['$code'],
          onExit: exited.complete,
        );
        await controller.start(columns: 80, rows: 24);
        expect(await exited.future.timeout(deadline), code);
        await controller.dispose();
      }
    },
  );

  test('kill terminates the native process and drains output', () async {
    final exited = Completer<int>();
    final controller = controllerFor('interactive', onExit: exited.complete);
    await startInteractive(controller);
    expect(controller.kill(ProcessSignal.sigkill), isTrue);
    expect(await exited.future.timeout(deadline), isNonZero);
    expect(controller.status, PtyStatus.exited);
  });

  test('kill also terminates an interactive shell foreground job', () async {
    final job = Completer<int>();
    final exited = Completer<int>();
    var output = '';
    final controller = PtyController(
      command: '/bin/bash',
      arguments: ['--noprofile', '--norc', '-i'],
      onOutput: (chunk) {
        output += chunk;
        final match = RegExp(r'JOB:(\d+)').firstMatch(output);
        if (match != null && !job.isCompleted) {
          job.complete(int.parse(match[1]!));
        }
      },
      onExit: exited.complete,
    );
    addTearDown(controller.dispose);
    await controller.start(columns: 120, rows: 24);
    controller.write(
      r'''sh -c 'trap "" HUP; echo JOB:$$; sleep 60' '''
      '\n',
    );
    final jobPid = await job.future.timeout(
      deadline,
      onTimeout: () => fail(output),
    );
    addTearDown(() => Process.killPid(jobPid, ProcessSignal.sigkill));
    expect(controller.kill(ProcessSignal.sigkill), isTrue);
    await exited.future.timeout(deadline, onTimeout: () => fail(output));
    final result = await Process.run('/bin/kill', ['-0', '$jobPid']);
    expect(result.exitCode, isNot(0), reason: 'Foreground job survived kill');
  }, skip: Platform.isWindows);

  test(
    'a child terminated by a signal reports the system transport status',
    () async {
      final exited = Completer<int>();
      final controller = controllerFor('signal', onExit: exited.complete);
      await controller.start(columns: 80, rows: 24);
      expect(
        await exited.future.timeout(deadline),
        Platform.isMacOS ? 15 : 143,
      );
    },
    skip: Platform.isWindows,
  );

  test('native child retains the default SIGINT disposition', () async {
    final exited = Completer<int>();
    var output = '';
    final controller = PtyController(
      command: '/bin/sh',
      arguments: ['-c', r'kill -INT $$; echo SURVIVED'],
      onOutput: (chunk) => output += chunk,
      onExit: exited.complete,
    );
    addTearDown(controller.dispose);
    await controller.start(columns: 80, rows: 24);
    expect(await exited.future.timeout(deadline), isNonZero);
    expect(output, isNot(contains('SURVIVED')));
  }, skip: Platform.isWindows);

  test('caller SHELL does not control the Unix transport bootstrap', () async {
    final exited = Completer<int>();
    var output = '';
    final controller = PtyController(
      command: Platform.resolvedExecutable,
      arguments: [fixture, 'environment'],
      environment: {'SHELL': '/bin/false', 'CINDER_PTY_TEST': 'literal value'},
      onOutput: (chunk) => output += chunk,
      onExit: exited.complete,
    );
    addTearDown(controller.dispose);
    await controller.start(columns: 120, rows: 24);
    expect(await exited.future.timeout(deadline), 0);
    expect(output, contains('SHELL:/bin/false'));
    expect(output, contains('VALUE:literal value'));
  }, skip: Platform.isWindows);

  test('natural exit also releases surviving background terminal jobs', () async {
    final exited = Completer<int>();
    final job = Completer<int>();
    var output = '';
    final controller = PtyController(
      command: '/bin/sh',
      arguments: [
        '-c',
        r'''sh -c 'trap "" HUP TERM; echo JOB:$$; while :; do sleep 1; done' & read release; exit 7''',
      ],
      onOutput: (chunk) {
        output += chunk;
        final match = RegExp(r'JOB:(\d+)').firstMatch(output);
        if (match != null && !job.isCompleted) {
          job.complete(int.parse(match[1]!));
        }
      },
      onExit: exited.complete,
    );
    addTearDown(controller.dispose);
    await controller.start(columns: 80, rows: 24);
    final child = await job.future.timeout(deadline);
    addTearDown(() => Process.killPid(child, ProcessSignal.sigkill));
    controller.write('release\n');
    expect(await exited.future.timeout(deadline), 7);
    final result = await Process.run('/bin/kill', ['-0', '$child']);
    expect(
      result.exitCode,
      isNot(0),
      reason: 'Background job survived natural exit',
    );
  }, skip: Platform.isWindows);

  test(
    'bounds concurrent signal requests while retaining kill escalation',
    () async {
      final controller = controllerFor('stalled');
      await startInteractive(controller);
      expect(controller.kill(), isTrue);
      for (var i = 0; i < 1000; i++) {
        expect(controller.kill(), isFalse);
      }
      expect(controller.kill(ProcessSignal.sigkill), isTrue);
      await controller.dispose().timeout(deadline);
    },
    skip: Platform.isWindows,
  );

  test('native launch rejects NULs instead of truncating arguments', () async {
    final controller = controllerFor(
      'arguments',
      arguments: ['before\x00after'],
    );
    await expectLater(
      controller.start(columns: 80, rows: 24),
      throwsArgumentError,
    );
    expect(controller.pid, isNull);
  });

  test(
    'rejects overflowing pending input and disposes a stalled writer',
    () async {
      final alive = Completer<void>();
      var waiting = false;
      final controller = controllerFor(
        'stalled',
        onOutput: (chunk) {
          if (waiting && chunk.contains('ALIVE') && !alive.isCompleted) {
            alive.complete();
          }
        },
      );
      await startInteractive(controller);
      controller.writeBytes(Uint8List(1024 * 1024));
      expect(() => controller.write('overflow'), throwsStateError);
      waiting = true;
      await alive.future.timeout(deadline);
      expect(controller.isRunning, isTrue);
      await controller.dispose().timeout(deadline);
      expect(controller.pid, isNull);
    },
  );

  test('bounds pending input messages even for tiny writes', () async {
    final controller = controllerFor('stalled');
    await startInteractive(controller);
    for (var i = 0; i < 256; i++) {
      controller.write('x');
    }
    expect(() => controller.write('overflow'), throwsStateError);
    await controller.dispose().timeout(deadline);
  });

  test('disposal kills descendants that ignore terminal hangup', () async {
    final child = Completer<int>();
    var output = '';
    final controller = controllerFor(
      'descendant',
      onOutput: (chunk) {
        output += chunk;
        final match = RegExp(r'GRANDCHILD:(\d+)').firstMatch(output);
        if (match != null && !child.isCompleted) {
          child.complete(int.parse(match[1]!));
        }
      },
    );
    await controller.start(columns: 80, rows: 24);
    final descendant = await child.future.timeout(
      deadline,
      onTimeout: () => fail(output),
    );
    addTearDown(() => Process.killPid(descendant, ProcessSignal.sigkill));
    await controller.dispose().timeout(deadline);
    final result = await Process.run('/bin/kill', ['-0', '$descendant']);
    expect(
      result.exitCode,
      isNot(0),
      reason: 'PTY descendant survived disposal',
    );
  }, skip: Platform.isWindows);

  test(
    'combines partial output chunks into lines and preserves blank lines',
    () async {
      final partial = Completer<void>();
      final exited = Completer<int>();
      final controller = controllerFor(
        'fragmented',
        onOutput: (data) {
          if (data.contains('hel') && !partial.isCompleted) partial.complete();
        },
        onExit: exited.complete,
      );
      await controller.start(columns: 80, rows: 24);
      await partial.future.timeout(deadline);
      controller.write(Platform.isWindows ? 'continue\r' : 'continue\n');
      await exited.future.timeout(deadline);
      expect(controller.outputBuffer, ['hello', 'second', '', 'third']);
    },
  );

  test(
    'rejects overlapping starts without replacing the running process',
    () async {
      final controller = controllerFor('interactive');
      final firstStart = controller.start(columns: 80, rows: 24);
      await expectLater(
        controller.start(columns: 90, rows: 30),
        throwsStateError,
      );
      await firstStart;
      expect(controller.columns, 80);
      expect(controller.rows, 24);
    },
  );

  test('rejects writes while not running', () async {
    final controller = controllerFor('interactive');
    expect(() => controller.write('text'), throwsStateError);
    expect(() => controller.writeBytes([1, 2]), throwsStateError);
  });

  test(
    'restart preserves listeners and dimensions with a new process',
    () async {
      final controller = controllerFor('interactive');
      final states = <PtyStatus>[];
      controller.addListener(() => states.add(controller.status));
      await startInteractive(controller);
      final firstPid = controller.pid;
      controller.resize(100, 30);
      states.clear();

      await controller.restart();

      expect(controller.isRunning, isTrue);
      expect(controller.pid, isNot(firstPid));
      expect(controller.columns, 100);
      expect(controller.rows, 30);
      expect(
        states,
        containsAllInOrder([PtyStatus.starting, PtyStatus.running]),
      );
    },
  );

  test('dispose during start never leaves a running process', () async {
    final controller = controllerFor('interactive');
    final starting = controller.start(columns: 80, rows: 24);
    await controller.dispose();
    await starting;
    expect(controller.status, PtyStatus.disposed);
    expect(controller.pid, isNull);
  });

  test('disposed controllers reject new starts', () async {
    final controller = controllerFor('interactive');
    await controller.dispose();
    await expectLater(
      controller.start(columns: 80, rows: 24),
      throwsStateError,
    );
  });
  test('invalid dimensions and negative buffer sizes are rejected', () async {
    expect(() => PtyController(maxBufferLines: -1), throwsArgumentError);
    expect(() => PtyController(maxBufferBytes: -1), throwsArgumentError);
    final controller = controllerFor('interactive');
    await expectLater(
      controller.start(columns: 0, rows: 24),
      throwsArgumentError,
    );
    expect(controller.status, PtyStatus.notStarted);
  });

  test('invalid live resize leaves native dimensions unchanged', () async {
    final controller = controllerFor('interactive');
    await startInteractive(controller);
    expect(() => controller.resize(0, 20), throwsArgumentError);
    expect(() => controller.resize(40000, 20), throwsArgumentError);
    expect(controller.columns, 80);
    expect(controller.rows, 24);
  });

  test('launch errors notify the caller and leave no process', () async {
    final errors = <Object>[];
    final controller = PtyController(
      command: Platform.resolvedExecutable,
      arguments: [fixture, 'interactive'],
      workingDirectory: '$fixture.missing-directory',
      onError: errors.add,
    );
    addTearDown(controller.dispose);

    await expectLater(
      controller.start(columns: 80, rows: 24),
      throwsA(isA<ProcessException>()),
    );

    expect(errors, hasLength(1));
    expect(controller.status, PtyStatus.error);
    expect(controller.pid, isNull);
  });
}
