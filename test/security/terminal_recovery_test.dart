import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('shutdown restores terminal modes even when one write fails', () {
    final backend = _RecoveryBackend();
    final terminal = Terminal(backend, size: const Size(80, 24));
    terminal.enterAlternateScreen();
    terminal.flush();
    backend.clear();

    final binding = TerminalBinding(terminal);
    backend.failNextWrite = true;
    binding.shutdown();

    final output = backend.output.toString();
    // The first recovery write deliberately failed; later cleanup still ran.
    expect(output, contains(EscapeCodes.resetScrollRegion));
    expect(output, contains(TextStyle.reset));
    expect(output, contains(EscapeCodes.disable.motionTracking));
    expect(output, contains(EscapeCodes.disable.sgrMouseMode));
    expect(output, contains(EscapeCodes.disable.bracketedPasteMode));
    expect(output, contains(EscapeCodes.disable.kittyKeyboard));
    expect(output, contains(EscapeCodes.disable.modifyOtherKeys));
    expect(output, contains(EscapeCodes.showCursor));
    expect(output, contains(EscapeCodes.mainBuffer));
    expect(backend.rawModeDisabled, isTrue);

    CinderBinding.resetInstance();
  });
}

class _RecoveryBackend implements TerminalBackend {
  final StringBuffer output = StringBuffer();
  bool failNextWrite = false;
  bool rawModeDisabled = false;

  void clear() => output.clear();

  @override
  void writeRaw(String data) {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('injected terminal write failure');
    }
    output.write(data);
  }

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
  void disableRawMode() => rawModeDisabled = true;

  @override
  bool get isAvailable => true;

  @override
  void requestExit([int exitCode = 0]) {}

  @override
  void notifySizeChanged(Size newSize) {}

  @override
  void dispose() {}
}
