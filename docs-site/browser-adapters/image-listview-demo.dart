import 'dart:typed_data';

import 'package:cinder/cinder.dart';

/// Browser adapter for the file-backed image ListView example.
void main() {
  runApp(const BrowserImageListDemo());
}

class BrowserImageListDemo extends StatefulWidget {
  const BrowserImageListDemo({super.key});

  @override
  State<BrowserImageListDemo> createState() => _BrowserImageListDemoState();
}

class _BrowserImageListDemoState extends State<BrowserImageListDemo> {
  final ScrollController _scrollController = ScrollController();
  final List<Uint8List> _images = List<Uint8List>.generate(
    10,
    (index) => _makePixels(48, 24, index),
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  'IMAGE LISTVIEW / WEB ADAPTER',
                  style: TextStyle(
                    color: Colors.magenta,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '10 GENERATED RGBA SOURCES',
                  style: TextStyle(color: Colors.green),
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _images.length,
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      border: BoxBorder(
                        bottom: BorderSide(
                          color: Colors.gray.withOpacity(0.45),
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 7,
                          decoration: BoxDecoration(
                            border: BoxBorder.all(color: Colors.cyan),
                          ),
                          child: Image.rgba(
                            _images[index],
                            pixelWidth: 48,
                            pixelHeight: 24,
                            height: 7,
                            fit: BoxFit.contain,
                            protocol: ImageProtocol.unicodeBlocks,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Generated scene ${(index + 1).toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 1),
                              const Text(
                                'Memory RGBA → decode → RenderImage → terminal cells',
                                style: TextStyle(color: Colors.gray),
                              ),
                              Text(
                                'Seed: $index · 48×24 RGBA',
                                style: const TextStyle(color: Colors.cyan),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const Text(
            'Arrow keys / wheel scroll the real Cinder ListView. No local file access is claimed.',
            style: TextStyle(color: Colors.gray),
          ),
        ],
      ),
    );
  }
}

Uint8List _makePixels(int width, int height, int seed) {
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = (y * width + x) * 4;
      final wave = ((x * (seed + 2) + y * 3) % 48) / 47;
      final stripe = ((x + y + seed * 5) % 11) < 2;
      pixels[index] = (30 + wave * 210).round();
      pixels[index + 1] = (18 + (1 - wave) * 90).round();
      pixels[index + 2] = (70 + seed * 13 + y * 2).clamp(0, 255).toInt();
      pixels[index + 3] = stripe ? 220 : 255;
    }
  }
  return pixels;
}
