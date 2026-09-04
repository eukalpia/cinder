import 'dart:async';
import 'dart:io';

import 'package:cinder/cinder.dart' hide isEmpty;
import 'package:test/test.dart';

void main() {
  test('clipboard operations use valid OSC 52 on the active backend', () {
    final backend = _RecordingBackend();
    final binding = TerminalBinding(
      Terminal(backend),
      capabilities: const TerminalCapabilities(
        isInteractive: true,
        supportsOsc52Clipboard: true,
      ),
    );
    addTearDown(binding.shutdown);

    expect(Clipboard.copy('hello'), isTrue);
    expect(Clipboard.copyToPrimary('hi', useStringTerminator: false), isTrue);
    expect(Clipboard.clear(), isTrue);
    expect(
      backend.output.toString(),
      '\x1b]52;c;aGVsbG8=\x1b\\\x1b]52;p;aGk=\x07\x1b]52;c;\x1b\\',
    );
  });

  test(
    'unsupported clipboard uses internal storage without terminal writes',
    () {
      final backend = _RecordingBackend();
      final binding = TerminalBinding(
        Terminal(backend),
        capabilities: const TerminalCapabilities(),
      );
      addTearDown(binding.shutdown);

      expect(Clipboard.copy('hidden'), isFalse);
      ClipboardManager.copy('local');
      ClipboardManager.copyToPrimary('primary');
      expect(ClipboardManager.paste(), 'local');
      expect(ClipboardManager.pastePrimary(), 'primary');
      ClipboardManager.clear();
      expect(backend.output.toString(), isEmpty);
    },
  );

  test(
    'redirected clipboard operations never emit terminal controls',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'cinder-clipboard-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final script = File('${directory.path}/main.dart')
        ..writeAsStringSync('''
import 'package:cinder/cinder.dart' hide isEmpty;
void main() {
  Clipboard.copy('hello');
  Clipboard.copyToPrimary('primary');
  Clipboard.clear();
  ClipboardManager.copyToPrimary('local');
  ClipboardManager.clear();
  print('finished');
}
''');
      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        script.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, 'finished\n');
    },
  );
}

class _RecordingBackend extends TerminalBackend {
  final output = StringBuffer();
  @override
  void writeRaw(String data) => output.write(data);
  @override
  Size getSize() => const Size(80, 24);
  @override
  bool get supportsSize => true;
  @override
  Stream<List<int>>? get inputStream => null;
  @override
  Stream<Size>? get resizeStream => null;
  @override
  Stream<void>? get shutdownStream => null;
  @override
  void enableRawMode() {}
  @override
  void disableRawMode() {}
  @override
  bool get isAvailable => true;
  @override
  void requestExit([int exitCode = 0]) {}
  @override
  void dispose() {}
}
