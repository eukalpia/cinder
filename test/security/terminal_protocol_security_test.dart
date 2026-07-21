import 'dart:async';
import 'dart:typed_data';

import 'package:cinder/cinder.dart';
import 'package:cinder/src/image/iterm2_encoder.dart';
import 'package:cinder/src/image/kitty_encoder.dart';
import 'package:cinder/src/image/sixel_encoder.dart';
import 'package:test/test.dart';

void main() {
  group('terminal metadata', () {
    test('title and icon payloads cannot terminate their OSC sequence', () {
      final backend = _RecordingBackend();
      final terminal = Terminal(backend, size: const Size(80, 24));

      terminal.setWindowTitle('safe\x07\x1b]52;c;attack\x07\nnext');
      terminal.setIconName('icon\x1b[2J');
      terminal.setTitleAndIcon('both\u202Etxt');
      terminal.flush();

      final output = backend.output.toString();
      expect(_count(output, '\x1b]2;'), 1);
      expect(_count(output, '\x1b]1;'), 1);
      expect(_count(output, '\x1b]0;'), 1);
      expect(output, contains('safe␇␛]52;c;attack␇ next'));
      expect(output, contains('icon␛[2J'));
      expect(output, contains('both⟦RLO⟧txt'));
      // Only Cinder's three OSC terminators remain executable.
      expect(_count(output, '\x07'), 3);
    });
  });

  group('terminal image payload validation', () {
    test('accepts payloads produced by first-party encoders', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final kitty = KittyEncoder.encodePng(
        imageBytes: bytes,
        displayColumns: 2,
        displayRows: 1,
      );
      final iterm = ITerm2Encoder.encode(
        imageBytes: bytes,
        width: '2',
        height: '1',
      );
      final sixel = SixelEncoder.encode(
        pixels: Uint8List.fromList(<int>[255, 0, 0, 255]),
        width: 1,
        height: 1,
        palette: const <Color>[Color.fromRGB(255, 0, 0)],
        indexedPixels: Uint8List.fromList(<int>[0]),
      );

      expect(
        TerminalImagePayloadValidator.isValid(kitty, ImageProtocol.kitty),
        isTrue,
      );
      expect(
        TerminalImagePayloadValidator.isValid(iterm, ImageProtocol.iterm2),
        isTrue,
      );
      expect(
        TerminalImagePayloadValidator.isValid(sixel, ImageProtocol.sixel),
        isTrue,
      );
    });

    test('rejects appended commands and protocol confusion', () {
      final kitty = KittyEncoder.encodePng(
        imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      expect(
        TerminalImagePayloadValidator.isValid(
          '$kitty\x1b[2J',
          ImageProtocol.kitty,
        ),
        isFalse,
      );
      expect(
        TerminalImagePayloadValidator.isValid(kitty, ImageProtocol.sixel),
        isFalse,
      );
      expect(
        TerminalImagePayloadValidator.isValid(
          '\x1bPq~\x1b\\\x1b]52;c;AAAA\x07',
          ImageProtocol.sixel,
        ),
        isFalse,
      );
    });

    test('Terminal refuses unvalidated native image output', () {
      final backend = _RecordingBackend();
      final terminal = Terminal(backend, size: const Size(80, 24));
      final valid = KittyEncoder.encodePng(
        imageBytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      terminal.writeInlineImage(valid, 2, 3, protocol: ImageProtocol.kitty);
      terminal.flush();
      expect(backend.output.toString(), contains(valid));

      expect(
        () => terminal.writeInlineImage(
          '$valid\x1b[?1049h',
          0,
          0,
          protocol: ImageProtocol.kitty,
        ),
        throwsArgumentError,
      );
    });
  });
}

int _count(String value, String pattern) {
  var count = 0;
  var offset = 0;
  while (true) {
    final next = value.indexOf(pattern, offset);
    if (next < 0) return count;
    count++;
    offset = next + pattern.length;
  }
}

class _RecordingBackend implements TerminalBackend {
  final StringBuffer output = StringBuffer();

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
  void notifySizeChanged(Size newSize) {}

  @override
  void dispose() {}
}
