import 'package:file/file.dart';

/// Finds the SDK compiler without assuming the CLI itself is the Dart VM.
String findDartExecutable({
  required FileSystem fileSystem,
  required String resolvedExecutable,
  required Map<String, String> environment,
  required String operatingSystem,
}) {
  final path = fileSystem.path;
  final executableName = operatingSystem == 'windows' ? 'dart.exe' : 'dart';

  String? sdkCompiler(String root) {
    final compiler = fileSystem.file(path.join(root, 'bin', executableName));
    if (!fileSystem.file(path.join(root, 'version')).existsSync() ||
        !fileSystem.directory(path.join(root, 'lib')).existsSync() ||
        !compiler.existsSync()) {
      return null;
    }
    try {
      return compiler.resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
  }

  String? compilerBeside(String executable) {
    try {
      final resolved = fileSystem.file(executable).resolveSymbolicLinksSync();
      return sdkCompiler(path.dirname(path.dirname(resolved)));
    } on FileSystemException {
      return null;
    }
  }

  String? executableShim(String executable) {
    final file = fileSystem.file(executable);
    if (!file.existsSync()) return null;
    try {
      final resolved = file.resolveSymbolicLinksSync();
      final current = fileSystem.file(resolvedExecutable);
      if (current.existsSync() &&
          fileSystem.identicalSync(
            resolved,
            current.resolveSymbolicLinksSync(),
          )) {
        return null;
      }
      // Windows launches .exe shims directly. POSIX shims need an executable
      // permission bit; Process.run still reports permissions/format errors.
      if (operatingSystem != 'windows' && file.statSync().mode & 0x49 == 0) {
        return null;
      }
      // Keep the dart symlink name: some version managers dispatch using argv[0].
      // BuildCommand validates the selected launcher with dart --version.
      return file.absolute.path;
    } on FileSystemException {
      return null;
    }
  }

  // dart, dartvm, and dartaotruntime all live in the active SDK's bin folder.
  // A compiled cinder executable has no SDK layout and falls through below.
  if (compilerBeside(resolvedExecutable) case final compiler?) {
    return compiler;
  }
  final configured = environment['DART_SDK'];
  if (configured != null && configured.isNotEmpty) {
    if (sdkCompiler(configured) case final compiler?) {
      return compiler;
    }
    throw FormatException(
      'DART_SDK does not point to a complete Dart SDK: $configured',
    );
  }
  for (var directory in (environment['PATH'] ?? '').split(
    operatingSystem == 'windows' ? ';' : ':',
  )) {
    if (directory.startsWith('"') &&
        directory.endsWith('"') &&
        directory.length >= 2) {
      directory = directory.substring(1, directory.length - 1);
    }
    if (directory.isEmpty) continue;
    if (compilerBeside(path.join(directory, executableName))
        case final compiler?) {
      return compiler;
    }
    // Flutter's PATH entry contains dart/dart.bat wrappers. Invoke its actual
    // SDK executable directly, which also avoids shell handling on Windows.
    if (sdkCompiler(path.join(directory, 'cache', 'dart-sdk'))
        case final compiler?) {
      return compiler;
    }
    if (executableShim(path.join(directory, executableName)) case final shim?) {
      return shim;
    }
  }
  throw FormatException(
    'A Dart SDK is required to build apps. Install Dart and add '
    'its bin directory to PATH, or set DART_SDK to the SDK directory.',
  );
}

/// The selected compiler's platform can differ from a standalone CLI's ABI.
({String os, String arch}) parseDartPlatform(String versionOutput) {
  final match = RegExp(
    r'on "(macos|windows|linux)_([a-z0-9]+)"',
  ).firstMatch(versionOutput);
  if (match == null) {
    throw FormatException(
      'Cannot determine the Dart SDK platform from dart --version: '
      '${versionOutput.trim()}',
    );
  }
  return (os: match.group(1)!, arch: match.group(2)!);
}
