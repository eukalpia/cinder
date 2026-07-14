import 'dart:typed_data';

import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('terminal capabilities prefer native protocols deterministically', () {
    expect(
      TerminalCapabilities.fromEnvironment(<String, String>{
        'TERM': 'xterm-kitty',
        'KITTY_WINDOW_ID': '1',
      }).preferredImageProtocol,
      ImageProtocol.kitty,
    );
    expect(
      TerminalCapabilities.fromEnvironment(<String, String>{
        'TERM_PROGRAM': 'iTerm.app',
      }).preferredImageProtocol,
      ImageProtocol.iterm2,
    );
    expect(
      TerminalCapabilities.fromEnvironment(<String, String>{
        'TERM': 'xterm-sixel',
      }).preferredImageProtocol,
      ImageProtocol.sixel,
    );
    expect(
      TerminalCapabilities.fromEnvironment(const <String, String>{})
          .preferredImageProtocol,
      ImageProtocol.unicodeBlocks,
    );
  });

  test('CINDER_IMAGE_PROTOCOL overrides auto-detection', () {
    final capabilities = TerminalCapabilities.fromEnvironment(
      const <String, String>{
        'TERM': 'xterm-kitty',
        'CINDER_IMAGE_PROTOCOL': 'unicode',
      },
    );
    expect(capabilities.preferredImageProtocol, ImageProtocol.unicodeBlocks);
  });

  test('cached layer blit preserves inline image metadata and offsets', () {
    final layer = Buffer(4, 2);
    layer.markImageRegion(
      0,
      0,
      2,
      1,
      'encoded',
      protocol: ImageProtocol.kitty,
      imageId: 42,
    );
    final target = Buffer(10, 5);
    target.blit(layer, destinationX: 3, destinationY: 2);

    expect(target.pendingImages, hasLength(1));
    final image = target.pendingImages.single;
    expect((image.x, image.y), (3, 2));
    expect(image.protocol, ImageProtocol.kitty);
    expect(image.imageId, 42);
    expect(target.getCell(3, 2).isImagePlaceholder, isTrue);
  });

  test('Image.rgba accepts decoded pixels without a codec round trip', () {
    final pixels = Uint8List(2 * 2 * 4);
    final image = Image.rgba(pixels, pixelWidth: 2, pixelHeight: 2);
    expect(image.image, isA<ImageDataProvider>());
  });
}
