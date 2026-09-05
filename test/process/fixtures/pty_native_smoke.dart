import 'dart:async';
import 'dart:io';

import 'package:cinder/src/process/pty_controller.dart';

/// Compile this file and pty_process.dart to executables, then pass the child
/// executable path here to exercise native PTY startup/resize under Dart AOT.
Future<void> main(List<String> arguments) async {
  final ready = Completer<void>();
  final resized = Completer<void>();
  final exited = Completer<int>();
  var output = '';
  final controller = PtyController(
    command: arguments.single,
    arguments: ['dimensions'],
    onOutput: (chunk) {
      output += chunk;
      stdout.write(chunk);
      if (output.contains('SIZE:93:27') && !ready.isCompleted) ready.complete();
      if (output.contains('SIZE:111:39') && !resized.isCompleted) {
        resized.complete();
      }
    },
    onExit: exited.complete,
  );
  const deadline = Duration(seconds: 10);
  try {
    await controller.start(columns: 93, rows: 27);
    await ready.future.timeout(deadline);
    if (!output.contains('TTY:true:true:true')) {
      throw StateError('Child has no native terminal');
    }
    controller.resize(111, 39);
    controller.write(Platform.isWindows ? 'size\r' : 'size\n');
    await resized.future.timeout(deadline);
    controller.write(Platform.isWindows ? 'exit\r' : 'exit\n');
    if (await exited.future.timeout(deadline) != 0) {
      throw StateError('Child exit failed');
    }
  } finally {
    await controller.dispose();
  }
  stdout.writeln('PTY_AOT_OK');
}
