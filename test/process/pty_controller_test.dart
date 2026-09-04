import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cinder/src/process/pty_controller.dart';
import 'package:test/test.dart';

void main() {
  final fixture = File('test/process/fixtures/pty_process.dart').absolute.path;
  const deadline = Duration(seconds: 10);

  PtyController controllerFor(
    String mode, {
    List<String> arguments = const [],
    int maxBufferLines = 10000,
    void Function(String)? onOutput,
    void Function(int)? onExit,
  }) {
    final controller = PtyController(
      command: Platform.resolvedExecutable,
      arguments: [fixture, mode, ...arguments],
      maxBufferLines: maxBufferLines,
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

  test('preserves literal arguments and child exit code', () async {
    final exited = Completer<int>();
    var output = '';
    final arguments = [
      'hello world',
      "single'quote",
      r'$CINDER_MUST_NOT_EXPAND',
      'x; printf injected',
      '',
    ];
    final controller = controllerFor(
      'arguments',
      arguments: arguments,
      onOutput: (data) => output += data,
      onExit: exited.complete,
    );

    await controller.start(columns: 80, rows: 24);
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
      controller.write('hello\n');
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
      controller.write('continue\n');
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
    final controller = controllerFor('interactive');
    await expectLater(
      controller.start(columns: 0, rows: 24),
      throwsArgumentError,
    );
    expect(controller.status, PtyStatus.notStarted);
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
