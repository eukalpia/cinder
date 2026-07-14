import 'dart:io';

import 'package:cinder_cli/src/deps/log.dart';
import 'package:cinder_cli/utils/cli_command.dart';

/// Run a dart command with --enable-vm-service automatically added
class RunCommand extends CliCommand {
  RunCommand();

  @override
  String get description => '''
Run a Dart script with --enable-vm-service automatically added.
This enables VM service for debugging and profiling.

Example: cinder run dart lib/main.dart''';

  @override
  String get name => 'run';

  @override
  Future<int> run() async {
    final args = argResults.rest;

    if (args.isEmpty) {
      log('''
Error: No command provided

Usage: cinder run dart <script.dart> [arguments]

Example: cinder run dart lib/main.dart
''');

      return 1;
    }

    // Verify first argument is 'dart'
    if (args[0] != 'dart') {
      log('''
Error: Command must start with "dart"

Usage: cinder run dart <script.dart> [arguments]
''');

      return 1;
    }

    // Build the modified command: dart --enable-vm-service <rest of args>
    final modifiedArgs = [
      'dart',
      '--enable-vm-service',
      ...args.sublist(1), // All arguments after 'dart'
    ];

    log('Running: ${modifiedArgs.join(' ')}');
    log('');

    // Execute the command
    final process = await Process.start(
      modifiedArgs[0],
      modifiedArgs.sublist(1),
      mode: ProcessStartMode.inheritStdio,
    );

    // Forward signals to child process
    ProcessSignal.sigint.watch().listen((_) {
      process.kill(ProcessSignal.sigint);
    });

    if (Platform.isMacOS || Platform.isLinux) {
      ProcessSignal.sigterm.watch().listen((_) {
        process.kill(ProcessSignal.sigterm);
      });
    }

    // Wait for process to complete
    final exitCode = await process.exitCode;
    exit(exitCode);
  }
}
