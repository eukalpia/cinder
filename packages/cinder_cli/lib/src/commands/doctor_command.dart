import 'dart:io';

import 'package:args/command_runner.dart';

class DoctorCommand extends Command<int> {
  @override
  String get name => 'doctor';

  @override
  String get description => 'Check Dart, terminal, and optional media tools.';

  @override
  Future<int> run() async {
    var failures = 0;

    Future<void> check(
      String name,
      String executable,
      List<String> arguments, {
      bool required = false,
    }) async {
      try {
        final result = await Process.run(executable, arguments);
        if (result.exitCode != 0) {
          throw ProcessException(executable, arguments);
        }
        final output = '${result.stdout}${result.stderr}'.trim();
        final firstLine = output.isEmpty
            ? 'available'
            : output.split('\n').first;
        stdout.writeln('✓ $name: $firstLine');
      } catch (_) {
        stdout.writeln(
          '${required ? '✗' : '!'} $name: not found${required ? '' : ' (optional)'}',
        );
        if (required) failures++;
      }
    }

    await check('Dart', Platform.resolvedExecutable, const <String>[
      '--version',
    ], required: true);
    await check('FFmpeg', 'ffmpeg', const <String>['-version']);
    await check('FFprobe', 'ffprobe', const <String>['-version']);
    await check('FFplay', 'ffplay', const <String>['-version']);
    stdout.writeln(
      'Terminal: ${stdout.hasTerminal ? 'interactive' : 'non-interactive'}',
    );
    return failures == 0 ? 0 : 1;
  }
}
