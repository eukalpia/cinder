import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Get the global cinder directory for the current working directory.
///
/// Returns a path like: `~/.cinder/<hash-of-cwd>/`
///
/// This ensures each project gets its own isolated directory in the global
/// cinder storage, avoiding pollution of the user's project directory.
String getCinderDirectory() {
  // Get home directory
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null) {
    throw StateError('Could not determine home directory');
  }

  // Get current working directory and create a hash
  final proj = getProjectDirectory();
  final projHash =
      sha256.convert(utf8.encode(proj)).toString().substring(0, 16);

  // Return path: ~/.cinder/<hash>/
  return p.join(home, '.cinder', projHash);
}

String getProjectDirectory() {
  final start = Directory.current.path;
  var parent = Directory.current;
  while (true) {
    final pubspec = File(p.join(parent.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) return parent.path;

    final newParent = parent.parent;
    // Compare paths, not Directory identity — terminates at Windows drive
    // roots where parent.parent returns the same path.
    if (newParent.path == parent.path) return start;
    parent = newParent;
  }
}

/// Get the path to the log_port file for a specific PID.
String getLogPortPathForPid(int pid) {
  return p.join(getCinderDirectory(), 'log_port.$pid');
}

/// Get the path to the log_port file for the current process.
String getLogPortPath() {
  return getLogPortPathForPid(pid);
}

/// List all log_port files in the cinder directory.
/// Returns list of (pid, path) records.
Future<List<({int pid, String path})>> listLogPortFiles() async {
  final dir = Directory(getCinderDirectory());
  if (!await dir.exists()) return [];

  final files = <({int pid, String path})>[];
  await for (final entity in dir.list()) {
    if (entity is File) {
      final name = p.basename(entity.path);
      if (name.startsWith('log_port.')) {
        final pidStr = name.substring('log_port.'.length);
        final parsedPid = int.tryParse(pidStr);
        if (parsedPid != null) {
          files.add((pid: parsedPid, path: entity.path));
        }
      }
    }
  }
  return files;
}

/// Get the path to the shell_handle file for the current directory.
String getShellHandlePath() {
  return p.join(getCinderDirectory(), 'shell_handle');
}

/// Get the path to the shell socket file for the current directory.
String getShellSocketPath() {
  return p.join(getCinderDirectory(), 'shell.sock');
}

/// Ensure the cinder directory exists for the current working directory.
Future<void> ensureCinderDirectoryExists() async {
  final dir = Directory(getCinderDirectory());
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}
