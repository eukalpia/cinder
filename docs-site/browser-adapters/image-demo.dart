import 'dart:typed_data';

import 'package:cinder/cinder.dart';

/// Browser adapter for the native file-based image demo.
///
/// The adapter keeps Cinder's image renderer and protocol selector, but uses
/// deterministic in-memory RGBA pixels instead of arbitrary local file access.
void main() {
  runApp(const BrowserImageDemo());
}

class BrowserImageDemo extends StatefulWidget {
  const BrowserImageDemo({super.key});

  @override
  State<BrowserImageDemo> createState() => _BrowserImageDemoState();
}

class _BrowserImageDemoState extends State<BrowserImageDemo> {
  final Uint8List _pixels = _makeCinderPixels(96, 48);
  int _selected = 0;

  final List<ImageProtocol> _protocols = const <ImageProtocol>[
    ImageProtocol.unicodeBlocks,
    ImageProtocol.kitty,
    ImageProtocol.iterm2,
    ImageProtocol.sixel,
  ];

  void _move(int delta) {
    setState(() {
      _selected = (_selected + delta + _protocols.length) % _protocols.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final protocol = _protocols[_selected];
    return Focus(
      autofocus: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.tab ||
            event.logicalKey == LogicalKey.arrowRight) {
          _move(1);
          return true;
        }
        if (event.logicalKey == LogicalKey.arrowLeft) {
          _move(-1);
          return true;
        }
        return false;
      },
      child: Container(
        color: const Color.fromRGB(10, 10, 16),
        child: Column(
          children: [
            Container(
              color: const Color.fromRGB(28, 22, 40),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'IMAGE RENDERER / WEB ADAPTER',
                    style: TextStyle(
                      color: Colors.magenta,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'RGBA MEMORY SOURCE',
                    style: TextStyle(color: Colors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 1),
            Row(
              children: _protocols.asMap().entries.map((entry) {
                final selected = entry.key == _selected;
                return Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Text(
                    '[${entry.key + 1}] ${_name(entry.value)}',
                    style: TextStyle(
                      color: selected ? Colors.yellow : Colors.gray,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 1),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  border: BoxBorder.all(color: Colors.magenta),
                ),
                child: Image.rgba(
                  _pixels,
                  pixelWidth: 96,
                  pixelHeight: 48,
                  fit: BoxFit.contain,
                  protocol: protocol,
                  placeholder: const Center(child: Text('Decoding RGBA…')),
                  errorWidget: const Center(
                    child: Text(
                      'Image adapter failed',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tab / ← / → switch protocol',
                    style: TextStyle(color: Colors.gray),
                  ),
                  Text(
                    'Current: ${_name(protocol)}',
                    style: const TextStyle(color: Colors.cyan),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _name(ImageProtocol protocol) {
    switch (protocol) {
      case ImageProtocol.kitty:
        return 'Kitty';
      case ImageProtocol.iterm2:
        return 'iTerm2';
      case ImageProtocol.sixel:
        return 'Sixel';
      case ImageProtocol.unicodeBlocks:
        return 'Unicode';
    }
  }
}

Uint8List _makeCinderPixels(int width, int height) {
  final pixels = Uint8List(width * height * 4);
  final centerX = width / 2;
  final centerY = height / 2;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = (y * width + x) * 4;
      final dx = (x - centerX).abs() / centerX;
      final dy = (y - centerY).abs() / centerY;
      final ember = (1 - (dx * 0.7 + dy)).clamp(0.0, 1.0);
      final grid = x % 12 == 0 || y % 8 == 0;

      pixels[index] = (40 + ember * 215).round();
      pixels[index + 1] = (14 + ember * 105).round();
      pixels[index + 2] = (58 + (1 - dx) * 130).round();
      pixels[index + 3] = grid ? 210 : 255;
    }
  }

  return pixels;
}
