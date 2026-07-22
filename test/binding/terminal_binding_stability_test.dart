import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  tearDown(CinderBinding.resetInstance);

  test('non-interactive binding emits no terminal control sequences', () {
    final backend = _RecordingBackend(hasInput: false);
    final binding = TerminalBinding(
      Terminal(backend),
      capabilities: const TerminalCapabilities(),
    );

    binding
      ..initialize()
      ..shutdown();

    expect(backend.output.toString(), equals(''));
    expect(backend.rawModeEnabled, isFalse);
  });

  test('interactive binding restores every enabled protocol', () {
    final backend = _RecordingBackend();
    final binding = TerminalBinding(
      Terminal(backend),
      capabilities: const TerminalCapabilities(
        isInteractive: true,
        supportsRawMode: true,
        supportsAlternateScreen: true,
        supportsMouse: true,
        supportsBracketedPaste: true,
        supportsFocusEvents: true,
        supportsKittyKeyboard: true,
      ),
    );

    binding
      ..initialize()
      ..shutdown();

    final output = backend.output.toString();
    expect(output, contains(EscapeCodes.alternateBuffer));
    expect(output, contains(EscapeCodes.enable.focusReporting));
    expect(output, contains(EscapeCodes.disable.focusReporting));
    expect(output, contains(EscapeCodes.mainBuffer));
    expect(backend.rawModeEnabled, isFalse);
    expect(CinderBinding.hasInstance, isFalse);
  });

  test('binding can be recreated after a complete shutdown', () {
    for (var index = 0; index < 3; index++) {
      final binding = TerminalBinding(
        Terminal(_RecordingBackend(hasInput: false)),
        capabilities: const TerminalCapabilities(),
      );
      binding
        ..initialize()
        ..shutdown();
    }

    expect(CinderBinding.hasInstance, isFalse);
  });
}

final class _RecordingBackend extends TerminalBackend {
  _RecordingBackend({this.hasInput = true});

  final bool hasInput;
  final StringBuffer output = StringBuffer();
  final StreamController<List<int>> _input = StreamController<List<int>>();
  bool rawModeEnabled = false;

  @override
  void writeRaw(String data) => output.write(data);

  @override
  Size getSize() => const Size(80, 24);

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream => hasInput ? _input.stream : null;

  @override
  Stream<Size>? get resizeStream => null;

  @override
  Stream<void>? get shutdownStream => null;

  @override
  void enableRawMode() => rawModeEnabled = true;

  @override
  void disableRawMode() => rawModeEnabled = false;

  @override
  bool get isAvailable => true;

  @override
  void requestExit([int exitCode = 0]) {}

  @override
  void dispose() {
    unawaited(_input.close());
  }
}
