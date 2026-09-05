import 'package:cinder_cli/src/native_build/dart_sdk.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  late FileSystem fs;

  setUp(() => fs = MemoryFileSystem.test());

  void sdk(String root) {
    fs.directory('$root/bin').createSync(recursive: true);
    fs.directory('$root/lib').createSync();
    fs.file('$root/version').writeAsStringSync('3.13.3');
    fs.file('$root/bin/dart').writeAsStringSync('compiler fixture');
    fs.file('$root/bin/dartaotruntime').writeAsStringSync('runtime fixture');
  }

  String locate(String executable, Map<String, String> environment) =>
      findDartExecutable(
        fileSystem: fs,
        resolvedExecutable: executable,
        environment: environment,
        operatingSystem: 'macos',
      );

  test('uses the running SDK even if PATH points to another one', () {
    sdk('/current');
    sdk('/other');
    expect(
      locate('/current/bin/dartaotruntime', {'PATH': '/other/bin'}),
      '/current/bin/dart',
    );
  });

  test('standalone AOT CLI uses an explicitly configured SDK', () {
    sdk('/configured');
    fs.directory('/apps').createSync();
    fs.file('/apps/cinder').writeAsStringSync('native CLI');
    expect(
      locate('/apps/cinder', {'DART_SDK': '/configured'}),
      '/configured/bin/dart',
    );
  });

  test('follows a PATH symlink to a full SDK', () {
    sdk('/sdk');
    fs.directory('/tools').createSync();
    fs.link('/tools/dart').createSync('/sdk/bin/dart');
    expect(locate('/apps/cinder', {'PATH': '/tools'}), '/sdk/bin/dart');
  });

  test('finds the SDK behind Flutter PATH wrappers', () {
    sdk('/flutter/bin/cache/dart-sdk');
    expect(
      locate('/apps/cinder', {'PATH': '/flutter/bin'}),
      '/flutter/bin/cache/dart-sdk/bin/dart',
    );
  });

  test('standalone CLI accepts a POSIX PATH shim for version validation', () {
    fs.directory('/shims').createSync();
    fs
        .file('/shims/dart')
        .writeAsStringSync('#!/bin/sh\nexec /sdk/bin/dart "\$@"\n');
    expect(locate('/apps/cinder', {'PATH': '/shims'}), '/shims/dart');
  });

  test('preserves a shim symlink name used to dispatch the Dart command', () {
    fs.directory('/shims').createSync();
    fs
        .file('/shims/manager')
        .writeAsStringSync('native version-manager fixture');
    fs.link('/shims/dart').createSync('/shims/manager');
    expect(locate('/apps/cinder', {'PATH': '/shims'}), '/shims/dart');
  });

  test('an invalid explicit SDK does not silently fall back to a shim', () {
    fs.directory('/shims').createSync();
    fs.file('/shims/dart').writeAsStringSync('#!/bin/sh\n');
    expect(
      () => locate('/apps/cinder', {'DART_SDK': '/missing', 'PATH': '/shims'}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('DART_SDK'),
        ),
      ),
    );
  });

  test('finds dart.exe through a quoted Windows PATH entry', () {
    fs = MemoryFileSystem.test(style: FileSystemStyle.windows);
    const root = r'C:\Program Files\Dart\dart-sdk';
    fs.directory('$root\\bin').createSync(recursive: true);
    fs.directory('$root\\lib').createSync();
    fs.file('$root\\version').writeAsStringSync('3.13.3');
    fs.file('$root\\bin\\dart.exe').writeAsStringSync('compiler fixture');
    expect(
      findDartExecutable(
        fileSystem: fs,
        resolvedExecutable: r'C:\Apps\cinder.exe',
        environment: {'PATH': 'C:\\Other;"$root\\bin"'},
        operatingSystem: 'windows',
      ),
      '$root\\bin\\dart.exe',
    );
  });

  test(
    'does not recursively execute the standalone CLI through a PATH alias',
    () {
      fs.directory('/apps').createSync();
      fs.file('/apps/cinder').writeAsStringSync('native CLI');
      fs.link('/apps/dart').createSync('/apps/cinder');
      expect(
        () => locate('/apps/cinder', {'PATH': '/apps'}),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('DART_SDK'),
          ),
        ),
      );
    },
  );

  test('accepts a Windows executable shim without invoking a batch shell', () {
    fs = MemoryFileSystem.test(style: FileSystemStyle.windows);
    fs.directory(r'C:\Chocolatey\bin').createSync(recursive: true);
    fs
        .file(r'C:\Chocolatey\bin\dart.exe')
        .writeAsStringSync('executable shim fixture');
    expect(
      findDartExecutable(
        fileSystem: fs,
        resolvedExecutable: r'C:\Apps\cinder.exe',
        environment: {'PATH': r'C:\Chocolatey\bin'},
        operatingSystem: 'windows',
      ),
      r'C:\Chocolatey\bin\dart.exe',
    );
  });

  test(
    'reads the selected SDK architecture instead of the CLI architecture',
    () {
      final host = parseDartPlatform(
        'Dart SDK version: 3.13.3 (stable) on "windows_x64"',
      );
      expect(host.os, 'windows');
      expect(host.arch, 'x64');
      expect(
        () => parseDartPlatform('unrecognized compiler output'),
        throwsFormatException,
      );
    },
  );
}
