import 'dart:io';

import 'package:args/command_runner.dart';

class VersionCommand extends Command<int> {
  @override
  String get name => 'version';

  @override
  String get description => 'Print the Cinder CLI version.';

  @override
  Future<int> run() async {
    stdout.writeln('cinder_cli 1.0.0-dev.3');
    return 0;
  }
}
