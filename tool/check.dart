import 'dart:io';

/// Runs the same checks locally and in CI. Flutter's optional browser wrapper
/// and the documentation site have their own validation workflows.
Future<void> main(List<String> arguments) async {
  const allowed = {'format', 'core', 'packages', 'benchmarks', 'package'};
  final checks = arguments.isEmpty ? allowed.toList() : arguments;
  if (checks.any((check) => !allowed.contains(check))) {
    stderr.writeln('Usage: dart tool/check.dart [${allowed.join('|')}]');
    exitCode = 64;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.path;
  final packages =
      Directory('$root/packages').listSync().whereType<Directory>().where((
        directory,
      ) {
        final manifest = File('${directory.path}/pubspec.yaml');
        return manifest.existsSync() &&
            !RegExp(
              r'^publish_to: ["\x27]?none',
              multiLine: true,
            ).hasMatch(manifest.readAsStringSync());
      }).toList()..sort((a, b) => a.path.compareTo(b.path));

  Future<void> run(List<String> args, {String? directory}) async {
    stdout.writeln('\n${directory ?? root}: dart ${args.join(' ')}');
    final process = await Process.start(
      Platform.resolvedExecutable,
      args,
      workingDirectory: directory ?? root,
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) {
      throw ProcessException('dart', args, 'Validation failed', code);
    }
  }

  try {
    for (final check in checks) {
      switch (check) {
        case 'format':
          // Pass source files explicitly so compiler scratch directories and
          // generated site exports never become formatting inputs.
          final sources = <String>[];
          for (final directory in [Directory(root), ...packages]) {
            for (final name in [
              'lib',
              'test',
              'example',
              'benchmark',
              'hooks',
              'tool',
            ]) {
              final source = Directory('${directory.path}/$name');
              if (!source.existsSync()) continue;
              sources.addAll(
                source
                    .listSync(recursive: true, followLinks: false)
                    .whereType<File>()
                    .where(
                      (file) =>
                          file.path.endsWith('.dart') &&
                          !file.path
                              .split(Platform.pathSeparator)
                              .any((part) => part.startsWith('.')),
                    )
                    .map((file) => file.path),
              );
            }
          }
          // Keep Windows process arguments below the command-line limit.
          for (var start = 0; start < sources.length; start += 50) {
            await run([
              'format',
              '--output=none',
              '--set-exit-if-changed',
              ...sources.skip(start).take(50),
            ]);
          }
        case 'core':
          await run(['pub', 'get']);
          await run(['analyze', '--fatal-infos']);
          await run(['test', '--run-skipped', '--reporter', 'expanded']);
        case 'packages':
          for (final package in packages) {
            await run(['pub', 'get'], directory: package.path);
            await run(['analyze', '--fatal-infos'], directory: package.path);
            if (Directory('${package.path}/test').existsSync()) {
              await run([
                'test',
                '--reporter',
                'expanded',
              ], directory: package.path);
            }
          }
        case 'benchmarks':
          await run(['run', 'benchmark/renderer_v2_benchmark.dart']);
          await run(['run', 'benchmark/renderer_v2_layers_benchmark.dart']);
        case 'package':
          await run(['pub', 'publish', '--dry-run']);
      }
    }
  } on ProcessException catch (error) {
    stderr.writeln(error);
    exitCode = error.errorCode == 0 ? 1 : error.errorCode;
  }
}
