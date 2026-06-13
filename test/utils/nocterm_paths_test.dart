import 'dart:io';

import 'package:nocterm/src/utils/nocterm_paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('getProjectDirectory', () {
    late Directory tempRoot;
    late Directory previousCwd;

    setUp(() {
      previousCwd = Directory.current;
      // Resolve symlinks up front: macOS maps /tmp -> /private/tmp (and
      // /var -> /private/var), but getProjectDirectory() reads
      // Directory.current.path, which the OS canonicalizes. Without this the
      // expected paths keep the symlink prefix and the actual paths don't,
      // so every assertion fails on macOS (Linux CI has no such symlink).
      tempRoot = Directory(Directory.systemTemp
          .createTempSync('nocterm_paths_test_')
          .resolveSymbolicLinksSync());
    });

    tearDown(() {
      Directory.current = previousCwd;
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    test('returns the closest ancestor containing pubspec.yaml', () {
      final project = Directory(p.join(tempRoot.path, 'project'))..createSync();
      File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('name: x');
      final nested = Directory(p.join(project.path, 'a', 'b'))
        ..createSync(recursive: true);
      Directory.current = nested;

      expect(getProjectDirectory(), equals(project.path));
    });

    test('returns cwd when no pubspec.yaml ancestor exists', () {
      final dir = Directory(p.join(tempRoot.path, 'a', 'b', 'c'))
        ..createSync(recursive: true);
      Directory.current = dir;

      expect(getProjectDirectory(), equals(dir.path));
    });

    test('terminates when walking past the filesystem root', () {
      final dir = Directory(p.join(tempRoot.path, 'deep', 'no', 'project'))
        ..createSync(recursive: true);
      Directory.current = dir;

      expect(getProjectDirectory(), equals(dir.path));
    });
  });
}
