import 'dart:io';

import 'package:cinder_cli/src/deps/fs.dart';
import 'package:cinder_cli/src/deps/log.dart';
import 'package:cinder_cli/src/runner.dart';
import 'package:cinder_cli/utils/restore_terminal.dart';
import 'package:scoped_deps/scoped_deps.dart';

void main(List<String> arguments) async {
  runScoped(() => _run(arguments), values: {logProvider, fsProvider});
}

Future<void> _run(List<String> arguments) async {
  try {
    exitCode = await Runner().run(arguments);
  } finally {
    restoreTerminal();
  }

  exit(exitCode);
}
