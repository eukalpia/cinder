import 'package:file/file.dart';
import 'package:yaml/yaml.dart';

/// Paths and compiler arguments for one native executable build.
class NativeBuildPlan {
  const NativeBuildPlan({
    required this.entryPoint,
    required this.output,
    required this.targetOs,
    required this.targetArch,
    this.debugInfo,
  });

  final String entryPoint;
  final String output;
  final String targetOs;
  final String targetArch;
  final String? debugInfo;

  List<String> get arguments => [
    'compile',
    'exe',
    '--target-os=$targetOs',
    '--target-arch=$targetArch',
    '--output=$output',
    if (debugInfo case final path?) '--save-debugging-info=$path',
    entryPoint,
  ];
}

/// Resolves a build without creating output files or invoking a compiler.
NativeBuildPlan resolveBuildPlan({
  required FileSystem fileSystem,
  required String hostOs,
  required String hostArch,
  String? entryPoint,
  String? targetOs,
  String? targetArch,
  String? output,
  bool splitDebugInfo = true,
}) {
  const architectures = {
    'macos': {'arm64', 'x64'},
    'windows': {'arm64', 'x64'},
    'linux': {'arm', 'arm64', 'riscv64', 'x64'},
  };
  final os = targetOs ?? hostOs;
  final arch = targetArch ?? hostArch;
  if (!architectures.containsKey(hostOs)) {
    throw FormatException(
      'Native builds require a macOS, Windows, or Linux Dart SDK.',
    );
  }
  if (!(architectures[os]?.contains(arch) ?? false)) {
    throw FormatException(
      'Unsupported target $os-$arch. Supported targets: '
      'macos/windows: arm64, x64; linux: arm, arm64, riscv64, x64.',
    );
  }
  if (os != hostOs || arch != hostArch) {
    if (os != 'linux') {
      throw FormatException(
        'Dart cannot cross-compile from $hostOs-$hostArch to $os-$arch. '
        'Use a matching native Dart SDK or a $os-$arch GitHub Actions runner. '
        'Cross-compilation is available for Linux targets.',
      );
    }
    if (!const {'arm64', 'riscv64', 'x64'}.contains(hostArch)) {
      throw FormatException(
        'Linux cross-compilation requires a 64-bit Dart SDK.',
      );
    }
  }

  String? packageName;
  final pubspec = fileSystem.file('pubspec.yaml');
  if (pubspec.existsSync()) {
    Object? document;
    try {
      document = loadYaml(pubspec.readAsStringSync());
    } on YamlException catch (error) {
      throw FormatException('Cannot read pubspec.yaml: ${error.message}');
    }
    if (document is! YamlMap) {
      throw FormatException('pubspec.yaml must contain a YAML mapping.');
    }
    final name = document['name'];
    if (name != null) {
      if (name is! String ||
          !RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(name)) {
        throw FormatException(
          'pubspec.yaml must contain a valid package name.',
        );
      }
      packageName = name;
    }
  }

  final path = fileSystem.path;
  var entry = entryPoint;
  if (entry == null) {
    final candidates = [
      if (packageName != null) path.join('bin', '$packageName.dart'),
      path.join('bin', 'main.dart'),
    ];
    for (final candidate in candidates) {
      if (fileSystem.file(candidate).existsSync()) {
        entry = candidate;
        break;
      }
    }
    if (entry == null) {
      throw FormatException(
        'No default entry point found (${candidates.join(' or ')}). '
        'Specify one with cinder build path/to/entry.dart.',
      );
    }
  }
  if (entry.isEmpty || !fileSystem.file(entry).existsSync()) {
    throw FormatException('Dart entry point does not exist: $entry');
  }
  entry = path.normalize(path.absolute(entry));
  final name = packageName ?? path.basenameWithoutExtension(entry);
  if (output != null && output.isEmpty) {
    throw FormatException('--output must name an executable file.');
  }
  final destination = path.normalize(
    path.absolute(
      output ??
          path.join(
            'build',
            'cinder',
            '$os-$arch',
            '$name${os == 'windows' ? '.exe' : ''}',
          ),
    ),
  );
  final debugInfo = splitDebugInfo
      ? path.join(
          path.dirname(destination),
          'symbols',
          '${path.basename(destination)}.debug',
        )
      : null;
  final source = fileSystem.file(entry).resolveSymbolicLinksSync();
  bool overwritesSource(String candidate) {
    final file = fileSystem.file(candidate);
    return file.existsSync() &&
        fileSystem.identicalSync(file.resolveSymbolicLinksSync(), source);
  }

  if (overwritesSource(destination) ||
      (debugInfo != null && overwritesSource(debugInfo))) {
    throw FormatException(
      'The executable and debug symbols must not overwrite the Dart entry point.',
    );
  }
  return NativeBuildPlan(
    entryPoint: entry,
    output: destination,
    targetOs: os,
    targetArch: arch,
    debugInfo: debugInfo,
  );
}
