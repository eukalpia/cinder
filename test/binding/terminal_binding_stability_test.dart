import 'dart:async';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  tearDown(CinderBinding.resetInstance);

  for (final (name, decoration, ansi) in [
    ('line-through', TextDecoration.lineThrough, '\x1b[9m'),
    ('overline', TextDecoration.overline, '\x1b[53m'),
  ]) {
    test('first frame preserves standalone $name decoration', () {
      final backend = _RecordingBackend(hasInput: false);
      final binding = _FrameTestBinding(
        Terminal(backend),
        capabilities: const TerminalCapabilities(),
      );
      try {
        binding.initialize();
        binding.attachRootWidget(
          Text('X', style: TextStyle(decoration: decoration)),
        );
        binding.pumpFrame();

        expect(backend.output.toString(), contains('${ansi}X'));
      } finally {
        binding.shutdown();
      }
    });
  }

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

  test(
    'shutdown disposes the backend exactly once after restoring terminal',
    () {
      final backend = _RecordingBackend();
      final binding = TerminalBinding(
        Terminal(backend),
        capabilities: const TerminalCapabilities(
          isInteractive: true,
          supportsRawMode: true,
          supportsAlternateScreen: true,
        ),
      );

      binding
        ..initialize()
        ..shutdown()
        ..shutdown();

      expect(backend.disposals, 1);
      expect(backend.rawModeAtInputCancellation, isFalse);
      expect(backend.rawModeAtDisposal, isFalse);
      expect(backend.outputAtDisposal, contains(EscapeCodes.mainBuffer));
    },
  );

  test('shutdown continues restoring protocols when a write fails', () {
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
    binding.initialize();
    backend.failOnWrite = EscapeCodes.disable.motionTracking;

    binding.shutdown();

    final output = backend.output.toString();
    expect(output, contains(EscapeCodes.disable.bracketedPasteMode));
    expect(output, contains(EscapeCodes.disable.focusReporting));
    expect(output, contains(EscapeCodes.disable.kittyKeyboard));
    expect(output, contains(EscapeCodes.endSynchronizedOutput));
    expect(output, contains(EscapeCodes.mainBuffer));
    expect(backend.rawModeEnabled, isFalse);
    expect(backend.disposals, 1);
    expect(CinderBinding.hasInstance, isFalse);
  });

  test('shutdown releases the binding when backend disposal fails', () {
    final backend = _RecordingBackend()..failOnDispose = true;
    final binding = TerminalBinding(
      Terminal(backend),
      capabilities: const TerminalCapabilities(),
    );
    final errors = <Object>[];

    runZonedGuarded(binding.shutdown, (error, _) => errors.add(error));

    expect(errors, hasLength(1));
    expect(errors.single, isStateError);
    expect(CinderBinding.hasInstance, isFalse);
  });
}

final class _FrameTestBinding extends TerminalBinding {
  _FrameTestBinding(super.terminal, {required super.capabilities});

  void pumpFrame() => executeFrame();
}

final class _RecordingBackend extends TerminalBackend {
  _RecordingBackend({this.hasInput = true}) {
    _input.onCancel = () {
      rawModeAtInputCancellation = rawModeEnabled;
    };
  }

  final bool hasInput;
  final StringBuffer output = StringBuffer();
  final StreamController<List<int>> _input = StreamController<List<int>>();
  bool rawModeEnabled = false;
  String? failOnWrite;
  bool failOnDispose = false;
  int disposals = 0;
  bool? rawModeAtDisposal;
  bool? rawModeAtInputCancellation;
  String? outputAtDisposal;

  @override
  void writeRaw(String data) {
    if (data == failOnWrite) throw StateError('write failed');
    output.write(data);
  }

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
    disposals++;
    rawModeAtDisposal = rawModeEnabled;
    outputAtDisposal = output.toString();
    unawaited(_input.close());
    if (failOnDispose) throw StateError('dispose failed');
  }
}
