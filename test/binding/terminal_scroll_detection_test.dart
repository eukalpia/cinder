import 'package:cinder/cinder.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';
import 'package:test/test.dart';

const _width = 24;
const _height = 20;

void main() {
  tearDown(CinderBinding.resetInstance);

  for (final partial in [false, true]) {
    test(
      'detects styled wide rows with ${partial ? 'partial' : 'full'} damage',
      () {
        final harness = _Harness(partial: partial);
        addTearDown(harness.binding.shutdown);
        final original = _frame();
        harness.pump(original);

        for (final amount in [1, 3, 8]) {
          final shifted = _rotate(original, amount);
          final up = harness.pump(shifted);
          expect(up, contains(EscapeCodes.scrollUp(amount)));
          expect(up, contains(EscapeCodes.setScrollRegion(0, _height)));
          expect(up, contains(EscapeCodes.resetScrollRegion));
          expect(harness.binding.lastWrittenCells, _width * amount);
          if (partial) expect(harness.binding.lastPartialPaintBoundaries, 1);

          final down = harness.pump(original);
          expect(down, contains(EscapeCodes.scrollDown(amount)));
          expect(harness.binding.lastWrittenCells, _width * amount);
          if (partial) expect(harness.binding.lastPartialPaintBoundaries, 1);
        }

        // Alternating front/back storage must remain synchronized after scrolling.
        final unchanged = harness.pump(_frame());
        expect(_hasScroll(unchanged), isFalse);
        expect(harness.binding.lastWrittenCells, 0);
        final changed = _frame()..writeCell(8, 10, char: '!');
        final sparse = harness.pump(changed);
        expect(_hasScroll(sparse), isFalse);
        expect(harness.binding.lastWrittenCells, 1);
      },
    );
  }

  test('hardware scroll opt-out keeps differential redraws', () {
    final harness = _Harness();
    addTearDown(harness.binding.shutdown);
    harness.binding.enableHardwareScrollRegions = false;
    final original = _frame();
    harness.pump(original);

    expect(_hasScroll(harness.pump(_rotate(original, 1))), isFalse);
    expect(harness.binding.lastWrittenCells, greaterThan(_width));
  });

  test('inferred scroll damages exposed rows outside a partial repaint', () {
    final harness = _Harness();
    addTearDown(harness.binding.shutdown);
    final body = Buffer(_width, _height - 1);
    for (var y = 0; y < body.height; y++) {
      body.setString(0, y, 'B' * _width);
    }
    final unchangedBody = _BufferWidget(body);

    String paintTop(String char) {
      final top = Buffer(_width, 1)..setString(0, 0, char * _width);
      final root = Column(
        children: [
          SizedBox(
            height: 1,
            child: RepaintBoundary(child: _BufferWidget(top)),
          ),
          unchangedBody,
        ],
      );
      harness.backend.output.clear();
      if (harness.binding.rootElement == null) {
        harness.binding.attachRootWidget(root);
      } else {
        harness.binding.rootElement!.update(root);
      }
      harness.binding.pump();
      return harness.backend.output.toString();
    }

    paintTop('A');
    paintTop('D');
    expect(harness.binding.lastWrittenCells, _width);
    paintTop('A');
    // Both reusable buffers now record damage on only their first row.
    final output = paintTop('B');
    expect(harness.binding.lastPartialPaintBoundaries, 1);
    expect(output, contains(EscapeCodes.scrollUp(1)));
    expect(output, contains('\x1b[20;1H${'B' * _width}'));
    expect(harness.binding.lastWrittenCells, _width);

    // A later partial repaint must synchronize the shifted reusable buffer.
    paintTop('C');
    final unchanged = paintTop('C');
    expect(_hasScroll(unchanged), isFalse);
    expect(harness.binding.lastWrittenCells, 0);
  });

  for (final change in ['character', 'style', 'wide marker']) {
    test('rejects shifted rows with a mismatched $change', () {
      final harness = _Harness();
      addTearDown(harness.binding.shutdown);
      final original = _frame();
      harness.pump(original);
      final shifted = _rotate(original, 1);
      final x = change == 'wide marker' ? 3 : 8;
      final cell = shifted.getCell(x, 10);
      shifted.writeCell(
        x,
        10,
        char: change == 'style' ? cell.char : '!',
        style: change == 'style' ? const TextStyle(reverse: true) : cell.style,
      );

      expect(_hasScroll(harness.pump(shifted)), isFalse);
    });
  }

  for (final imageFrame in ['previous', 'current']) {
    for (final row in [0, 10, _height - 1]) {
      test('rejects $imageFrame image placeholders at row $row', () {
        final harness = _Harness();
        addTearDown(harness.binding.shutdown);
        final original = _frame();
        final shifted = _rotate(original, 1);
        final imageBuffer = imageFrame == 'previous' ? original : shifted;
        imageBuffer.getCell(8, row).isImagePlaceholder = true;
        harness.pump(original);

        expect(_hasScroll(harness.pump(shifted)), isFalse);
      });
    }
  }

  for (final imageFrame in ['previous', 'current']) {
    test('rejects $imageFrame pending image placements', () {
      final harness = _Harness();
      addTearDown(harness.binding.shutdown);
      final original = _frame();
      final shifted = _rotate(original, 1);
      final imageBuffer = imageFrame == 'previous' ? original : shifted;
      imageBuffer.pendingImages.add(
        const PendingImage(
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          protocol: ImageProtocol.kitty,
          encodedData: '',
          imageId: 1,
        ),
      );
      harness.pump(original);

      expect(_hasScroll(harness.pump(shifted)), isFalse);
    });
  }

  test(
    'preserves explicit scroll regions without a second inferred scroll',
    () {
      final harness = _Harness();
      addTearDown(harness.binding.shutdown);
      harness.pump(_frame());
      final changed = _frame()..scrollRegion(4, 16, 1, markDirty: true);
      harness.binding.pipelineOwner.requestTerminalScroll(
        const TerminalScrollRequest(
          left: 0,
          top: 4,
          width: _width,
          height: 12,
          lines: 1,
        ),
      );

      final output = harness.pump(changed);
      expect(output, contains(EscapeCodes.setScrollRegion(4, 16)));
      expect(output, isNot(contains(EscapeCodes.setScrollRegion(0, _height))));
      expect(RegExp(r'\x1b\[1S').allMatches(output), hasLength(1));
      expect(harness.binding.lastWrittenCells, 0);
    },
  );

  test('bounded search leaves larger jumps to the differential renderer', () {
    final harness = _Harness();
    addTearDown(harness.binding.shutdown);
    final original = _frame();
    harness.pump(original);

    expect(_hasScroll(harness.pump(_rotate(original, 9))), isFalse);
  });
}

bool _hasScroll(String output) => RegExp(r'\x1b\[\d+[ST]').hasMatch(output);

Buffer _frame() {
  final buffer = Buffer(_width, _height);
  for (var y = 0; y < _height; y++) {
    buffer.setString(
      0,
      y,
      '${y.toString().padLeft(2, '0')}界${'x' * _width}',
      style: TextStyle(
        color: Color(y * 12345),
        decoration: TextDecoration.overline,
      ),
    );
  }
  return buffer;
}

Buffer _rotate(Buffer original, int amount) {
  final result = Buffer(original.width, original.height);
  for (var y = 0; y < original.height; y++) {
    result.blit(
      original,
      destinationX: 0,
      destinationY: y,
      sourceY: (y + amount) % original.height,
      copyWidth: original.width,
      copyHeight: 1,
    );
  }
  return result;
}

class _Harness {
  _Harness({this.partial = false}) {
    binding = _FrameBinding(Terminal(backend))..initialize();
  }

  final bool partial;
  final _Backend backend = _Backend();
  late final _FrameBinding binding;

  String pump(Buffer buffer) {
    backend.output.clear();
    final widget = _BufferWidget(buffer);
    final root = partial ? RepaintBoundary(child: widget) : widget;
    if (binding.rootElement == null) {
      binding.attachRootWidget(root);
    } else {
      binding.rootElement!.update(root);
    }
    binding.pump();
    return backend.output.toString();
  }
}

class _BufferWidget extends SingleChildRenderObjectWidget {
  const _BufferWidget(this.buffer);
  final Buffer buffer;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BufferRenderObject(buffer);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _BufferRenderObject renderObject,
  ) {
    renderObject.buffer = buffer;
    renderObject.markNeedsPaint();
  }
}

class _BufferRenderObject extends RenderObject {
  _BufferRenderObject(this.buffer);
  Buffer buffer;

  @override
  void performLayout() => size = constraints.constrain(
    Size(buffer.width.toDouble(), buffer.height.toDouble()),
  );

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    canvas.drawBuffer(buffer, offset);
    super.paint(canvas, offset);
  }
}

class _FrameBinding extends TerminalBinding {
  _FrameBinding(super.terminal)
    : super(capabilities: const TerminalCapabilities());
  void pump() => executeFrame();
}

class _Backend extends TerminalBackend {
  final output = StringBuffer();
  @override
  Size getSize() => const Size(24, 20);
  @override
  bool get supportsSize => true;
  @override
  bool get isAvailable => true;
  @override
  Stream<List<int>>? get inputStream => null;
  @override
  Stream<Size>? get resizeStream => null;
  @override
  Stream<void>? get shutdownStream => null;
  @override
  void writeRaw(String data) => output.write(data);
  @override
  void enableRawMode() {}
  @override
  void disableRawMode() {}
  @override
  void requestExit([int exitCode = 0]) {}
  @override
  void dispose() {}
}
