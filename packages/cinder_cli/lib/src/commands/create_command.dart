import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

class CreateCommand extends Command<int> {
  CreateCommand() {
    argParser
      ..addOption(
        'description',
        abbr: 'd',
        defaultsTo: 'A Cinder terminal application.',
      )
      ..addFlag('force', abbr: 'f', negatable: false);
  }

  @override
  String get name => 'create';

  @override
  String get description => 'Create a new Cinder application.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.length != 1) {
      usageException('Provide exactly one project name or path.');
    }

    final directory = Directory(rest.single).absolute;
    final force = argResults?['force'] as bool;
    if (directory.existsSync() && directory.listSync().isNotEmpty && !force) {
      throw UsageException(
        'Directory ${directory.path} is not empty. Use --force to overwrite generated files.',
        usage,
      );
    }

    directory.createSync(recursive: true);
    final packageName = p
        .basename(directory.path)
        .replaceAll(RegExp('[^a-zA-Z0-9_]'), '_')
        .toLowerCase();
    final projectDescription = argResults?['description'] as String;

    void write(String relative, String content) {
      final file = File(p.join(directory.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', '''name: $packageName
description: $projectDescription
version: 0.1.0
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  cinder: ^1.0.0-dev.3

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
''');
    write('analysis_options.yaml', 'include: package:lints/recommended.yaml\n');
    write('.gitignore', '.dart_tool/\nbuild/\ncoverage/\n');
    write('bin/$packageName.dart', '''import 'package:cinder/cinder.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const CinderApp(
      home: Center(
        child: Text('Hello from Cinder'),
      ),
    );
  }
}
''');
    write('test/app_test.dart', '''import 'package:test/test.dart';

void main() {
  test('project scaffold is ready', () {
    expect(true, isTrue);
  });
}
''');

    stdout.writeln('Created $packageName in ${directory.path}');
    stdout.writeln('Next: cd ${directory.path} && dart pub get && dart run');
    return 0;
  }
}
