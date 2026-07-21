import 'package:args/command_runner.dart';
import 'package:cinder_cli/src/commands/create_command.dart';
import 'package:cinder_cli/src/commands/doctor_command.dart';
import 'package:cinder_cli/src/commands/logs_command.dart';
import 'package:cinder_cli/src/commands/run_command.dart';
import 'package:cinder_cli/src/commands/shell_command.dart';
import 'package:cinder_cli/src/commands/version_command.dart';
import 'package:cinder_cli/src/deps/log.dart';

class Runner extends CommandRunner<int> {
  Runner() : super('cinder', 'CLI tools for the Cinder TUI framework') {
    addCommand(CreateCommand());
    addCommand(DoctorCommand());
    addCommand(VersionCommand());
    addCommand(ShellCommand());
    addCommand(LogsCommand());
    addCommand(RunCommand());
  }

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      if (args.isEmpty) {
        log(usage);
        return 1;
      }
    } on FormatException catch (error) {
      log('Error: ${error.message}');
      log('');
      log(usage);
      return 1;
    }

    return (await super.run(args)) ?? 0;
  }
}
