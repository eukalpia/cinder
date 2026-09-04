import 'dart:convert';
import 'dart:io';

/// Verifies installation as an external application, where dependency
/// overrides from the libraries themselves do not apply.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart tool/verify_git_installation.dart <git-ref>');
    exitCode = 64;
    return;
  }
  final project = await Directory.systemTemp.createTemp('cinder_git_consumer_');
  final reference = arguments.single;
  const packages = [
    'cinder',
    'cinder_bloc',
    'cinder_cli',
    'cinder_lucide',
    'cinder_material_icons',
    'cinder_nested',
    'cinder_provider',
    'cinder_riverpod',
  ];
  Map<String, Object> dependency(String name) => {
    'git': {
      'url': 'https://github.com/eukalpia/cinder.git',
      'ref': reference,
      if (name != 'cinder') 'path': 'packages/$name',
    },
  };
  Future<ProcessResult> run(List<String> command) async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      command,
      workingDirectory: project.path,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      throw ProcessException(
        'dart',
        command,
        'Consumer check failed',
        result.exitCode,
      );
    }
    return result;
  }

  try {
    // JSON is valid YAML and keeps Git refs and paths correctly escaped.
    await File('${project.path}/pubspec.yaml').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'name': 'cinder_external_smoke',
        'publish_to': 'none',
        'environment': {'sdk': '>=3.9.0 <4.0.0'},
        'dependencies': {for (final name in packages) name: dependency(name)},
        'dependency_overrides': {
          for (final name in ['cinder', 'cinder_nested', 'cinder_provider'])
            name: dependency(name),
        },
      }),
    );
    await File('${project.path}/main.dart').writeAsString('''
import 'package:cinder/cinder.dart';
import 'package:cinder_bloc/cinder_bloc.dart';
import 'package:cinder_riverpod/cinder_riverpod.dart';
import 'package:cinder_lucide/cinder_lucide.dart';
import 'package:cinder_material_icons/cinder_material_icons.dart' as material;

class Count extends Cubit<int> { Count() : super(1); }

Future<void> main() async {
  final count = Count();
  final value = Provider<int>((ref) => 2);
  final container = ProviderContainer();
  final text = Text('\${count.state + container.read(value)}');
  print('\${text.runtimeType}: \${LucideIcons.activity.codePoint}, \${material.Icons.home.codePoint}');
  container.dispose();
  await count.close();
}
''');
    await run(['pub', 'get']);
    final binary = '${project.path}/consumer.exe';
    await run(['compile', 'exe', 'main.dart', '-o', binary]);
    final application = await Process.run(binary, const <String>[]);
    if (application.exitCode != 0 ||
        !application.stdout.toString().startsWith('Text: ')) {
      throw StateError(
        'Consumer failed: ${application.stdout}${application.stderr}',
      );
    }
    final cli = await run(['run', 'cinder_cli:cinder_cli', '--help']);
    if (!cli.stdout.toString().contains('Usage: cinder')) {
      throw StateError('The installed CLI did not display its command help');
    }
    stdout.writeln(
      'All eight Git packages install; native application and CLI run.',
    );
  } finally {
    await project.delete(recursive: true);
  }
}
