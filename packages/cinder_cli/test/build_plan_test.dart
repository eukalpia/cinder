import 'package:cinder_cli/src/native_build/build_plan.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  late FileSystem fs;

  setUp(() {
    fs = MemoryFileSystem.test();
    fs.directory('/project/bin').createSync(recursive: true);
    fs.currentDirectory = '/project';
    fs.file('pubspec.yaml').writeAsStringSync('name: sample_app\n');
  });

  NativeBuildPlan plan({
    String? entry,
    String? os,
    String? arch,
    String? output,
    bool split = true,
    String hostOs = 'macos',
    String hostArch = 'arm64',
  }) => resolveBuildPlan(
    fileSystem: fs,
    hostOs: hostOs,
    hostArch: hostArch,
    entryPoint: entry,
    targetOs: os,
    targetArch: arch,
    output: output,
    splitDebugInfo: split,
  );

  test('prefers the package entry and separates debug symbols', () {
    fs.file('bin/sample_app.dart').writeAsStringSync('void main() {}');
    fs.file('bin/main.dart').writeAsStringSync('void main() {}');

    final build = plan();

    expect(build.entryPoint, '/project/bin/sample_app.dart');
    expect(build.output, '/project/build/cinder/macos-arm64/sample_app');
    expect(
      build.debugInfo,
      '/project/build/cinder/macos-arm64/symbols/sample_app.debug',
    );
    expect(build.arguments, contains('--target-os=macos'));
    expect(build.arguments, contains('--target-arch=arm64'));
    expect(
      build.arguments,
      contains('--save-debugging-info=${build.debugInfo}'),
    );
  });

  test('falls back to bin/main.dart and parses quoted YAML names', () {
    fs.file('pubspec.yaml').writeAsStringSync('name: "sample_app" # comment\n');
    fs.file('bin/main.dart').writeAsStringSync('void main() {}');

    expect(plan().entryPoint, '/project/bin/main.dart');
    expect(plan().output, endsWith('/sample_app'));
  });

  test('missing inferred entry asks for an explicit Dart entry point', () {
    expect(
      plan,
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('cinder build path/to/entry.dart'),
        ),
      ),
    );
  });

  test(
    'explicit entry works without a pubspec and preserves argument boundaries',
    () {
      fs.file('pubspec.yaml').deleteSync();
      fs.file('bin/hello world.dart').writeAsStringSync('void main() {}');

      final build = plan(
        entry: 'bin/hello world.dart',
        output: 'output with spaces/app;literal',
      );

      expect(build.arguments.last, '/project/bin/hello world.dart');
      expect(
        build.arguments,
        contains('--output=/project/output with spaces/app;literal'),
      );
      expect(
        build.debugInfo,
        '/project/output with spaces/symbols/app;literal.debug',
      );
    },
  );

  test('native Windows output has an exe suffix', () {
    fs.file('bin/main.dart').writeAsStringSync('void main() {}');

    final build = plan(hostOs: 'windows', hostArch: 'x64');

    expect(build.output, '/project/build/cinder/windows-x64/sample_app.exe');
    expect(build.debugInfo, endsWith('/symbols/sample_app.exe.debug'));
  });

  test('custom output is exact and debug splitting can be disabled', () {
    fs.file('bin/main.dart').writeAsStringSync('void main() {}');

    final build = plan(output: 'artifacts/custom', split: false);

    expect(build.output, '/project/artifacts/custom');
    expect(build.debugInfo, isNull);
    expect(
      build.arguments.any((arg) => arg.startsWith('--save-debugging-info')),
      isFalse,
    );
  });

  for (final arch in ['arm', 'arm64', 'riscv64', 'x64']) {
    test('permits the supported Linux $arch cross target', () {
      fs.file('bin/main.dart').writeAsStringSync('void main() {}');
      final build = plan(os: 'linux', arch: arch);
      expect(build.arguments, contains('--target-os=linux'));
      expect(build.arguments, contains('--target-arch=$arch'));
    });
  }

  test('rejects another macOS architecture with native runner guidance', () {
    fs.file('bin/main.dart').writeAsStringSync('void main() {}');
    expect(
      () => plan(arch: 'x64'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('GitHub Actions runner'),
        ),
      ),
    );
  });

  test('rejects a Windows cross build and unsupported architecture', () {
    fs.file('bin/main.dart').writeAsStringSync('void main() {}');
    expect(() => plan(os: 'windows', arch: 'x64'), throwsFormatException);
    expect(() => plan(os: 'macos', arch: 'arm'), throwsFormatException);
    expect(() => plan(os: 'linux', arch: 'ia32'), throwsFormatException);
  });

  test(
    'rejects missing input, malformed pubspec, and overwriting the source',
    () {
      expect(() => plan(entry: 'missing.dart'), throwsFormatException);
      fs.file('bin/main.dart').writeAsStringSync('void main() {}');
      expect(() => plan(output: 'bin/main.dart'), throwsFormatException);
      fs.file('pubspec.yaml').writeAsStringSync('name: [unterminated');
      expect(plan, throwsFormatException);
    },
  );

  test('source overwrite protection follows file and directory aliases', () {
    fs.file('bin/main.dart').writeAsStringSync('void main() {}');
    fs.link('bin/output').createSync('main.dart');
    fs.link('bin/source.dart').createSync('main.dart');
    fs.link('alias').createSync('bin');
    expect(() => plan(output: 'bin/output'), throwsFormatException);
    expect(
      () => plan(entry: 'bin/source.dart', output: 'bin/main.dart'),
      throwsFormatException,
    );
    expect(() => plan(output: 'alias/main.dart'), throwsFormatException);
  });

  test('automatically selected debug output must not overwrite source', () {
    fs.directory('symbols').createSync();
    fs.file('symbols/program.debug').writeAsStringSync('void main() {}');
    expect(
      () => plan(entry: 'symbols/program.debug', output: 'program'),
      throwsFormatException,
    );
    fs.file('bin/main.dart').writeAsStringSync('void main() {}');
    fs.link('symbols/app.debug').createSync('../bin/main.dart');
    expect(() => plan(output: 'app'), throwsFormatException);
  });
}
