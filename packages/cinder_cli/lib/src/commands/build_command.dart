import 'dart:async';
import 'dart:io';

import 'package:cinder_cli/src/native_build/build_plan.dart';
import 'package:cinder_cli/src/native_build/dart_sdk.dart';
import 'package:cinder_cli/src/deps/fs.dart';
import 'package:cinder_cli/src/deps/log.dart';
import 'package:cinder_cli/utils/cli_command.dart';

/// Builds a self-contained native app with the installed Dart SDK.
class BuildCommand extends CliCommand {
  BuildCommand() {
    argParser
      ..addOption(
        'target-os',
        allowed: ['macos', 'windows', 'linux'],
        help: 'Target operating system (defaults to the Dart SDK host).',
      )
      ..addOption(
        'target-arch',
        allowed: ['x64', 'arm64', 'arm', 'riscv64'],
        help: 'Target architecture (defaults to the Dart SDK host).',
      )
      ..addOption(
        'output',
        abbr: 'o',
        valueHelp: 'FILE',
        help: 'Executable path (default: build/cinder/<os>-<arch>/<name>).',
      )
      ..addFlag(
        'split-debug-info',
        defaultsTo: true,
        help: 'Save debug symbols separately in a sibling symbols directory.',
      );
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      'Build a native executable. Defaults to bin/<package>.dart or bin/main.dart.';

  @override
  String get invocation => '${super.invocation} [entry.dart]';

  @override
  Future<int> run() async {
    if (argResults.rest.length > 1) {
      usageException('Specify at most one Dart entry point.');
    }
    try {
      final dart = findDartExecutable(
        fileSystem: fs,
        resolvedExecutable: Platform.resolvedExecutable,
        environment: Platform.environment,
        operatingSystem: Platform.operatingSystem,
      );
      final version = await Process.run(dart, ['--version']);
      if (version.exitCode != 0) {
        log('Cannot inspect Dart SDK: ${version.stdout}${version.stderr}');
        return version.exitCode;
      }
      final host = parseDartPlatform('${version.stdout}\n${version.stderr}');
      final build = resolveBuildPlan(
        fileSystem: fs,
        hostOs: host.os,
        hostArch: host.arch,
        entryPoint: argResults.rest.firstOrNull,
        targetOs: argResults.option('target-os'),
        targetArch: argResults.option('target-arch'),
        output: argResults.option('output'),
        splitDebugInfo: argResults.flag('split-debug-info'),
      );
      fs.file(build.output).parent.createSync(recursive: true);
      if (build.debugInfo case final symbols?) {
        fs.file(symbols).parent.createSync(recursive: true);
      }
      log(
        'Building ${build.entryPoint} for ${build.targetOs}-${build.targetArch}.',
      );
      final process = await Process.start(
        dart,
        build.arguments,
        mode: ProcessStartMode.inheritStdio,
      );
      final subscriptions = <StreamSubscription<ProcessSignal>>[
        ProcessSignal.sigint.watch().listen(
          (_) => process.kill(ProcessSignal.sigint),
        ),
        if (!Platform.isWindows)
          ProcessSignal.sigterm.watch().listen(
            (_) => process.kill(ProcessSignal.sigterm),
          ),
      ];
      try {
        final code = await process.exitCode;
        if (code == 0 && build.debugInfo != null) {
          log('Debug symbols: ${build.debugInfo}');
        }
        return code;
      } finally {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      }
    } on FormatException catch (error) {
      usageException(error.message);
    } on FileSystemException catch (error) {
      log(
        'Build failed: ${error.message}${error.path == null ? '' : ': ${error.path}'}',
      );
      return 1;
    } on ProcessException catch (error) {
      log('Unable to run the Dart compiler: ${error.message}');
      return 1;
    }
  }
}
