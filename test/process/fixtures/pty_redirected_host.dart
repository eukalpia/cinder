import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cinder/src/process/pty_controller.dart';

/// Run with redirected standard streams to check that the child uses its PTY.
Future<void> main(List<String> arguments) async {
  final exited = Completer<int>();
  final output = StringBuffer();
  final controller = PtyController(
    command: Platform.resolvedExecutable,
    arguments: [arguments.single, 'stdio'],
    onOutput: output.write,
    onExit: exited.complete,
  );
  try {
    await controller.start(columns: 160, rows: 24);
    final code = await exited.future.timeout(const Duration(seconds: 10));
    stdout.writeln(jsonEncode({'code': code, 'output': output.toString()}));
    await stdout.flush();
  } finally {
    await controller.dispose();
  }
}
