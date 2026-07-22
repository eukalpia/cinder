import '../binding/scheduler_binding.dart';
import '../buffer.dart';
import '../framework/framework.dart';
import '../framework/terminal_canvas.dart';
import '../rectangle.dart';
import '../semantics/semantics.dart';
import '../size.dart';

/// Result of rendering a widget without entering an interactive terminal mode.
class PlainOutputResult {
  const PlainOutputResult({required this.buffer, required this.size});

  final Buffer buffer;
  final Size size;

  List<String> get lines {
    final output = <String>[];
    for (var y = 0; y < size.height.toInt(); y++) {
      final line = StringBuffer();
      for (var x = 0; x < size.width.toInt(); x++) {
        final char = buffer.getCell(x, y).char;
        if (char != '\u200b') line.write(char);
      }
      output.add(line.toString().replaceFirst(RegExp(r'\s+$'), ''));
    }
    while (output.isNotEmpty && output.last.isEmpty) {
      output.removeLast();
    }
    return output;
  }

  String get text => lines.join('\n');

  Map<String, Object?> toJson() => <String, Object?>{
        'width': size.width.toInt(),
        'height': size.height.toInt(),
        'lines': lines,
      };
}

/// Renders [widget] in memory without raw mode, alternate screen, or ANSI I/O.
///
/// This is intended for shell pipelines, generated reports, CI, and applications
/// that expose `--plain` or `--json` modes. It must be called before an
/// interactive Cinder binding is created.
Future<PlainOutputResult> renderPlainWidget(
  Widget widget, {
  Size size = const Size(80, 24),
}) async {
  if (CinderBinding.hasInstance) {
    throw StateError(
      'renderPlainWidget cannot run while another Cinder binding is active.',
    );
  }
  final binding = _PlainOutputBinding(size);
  try {
    binding.attachRootWidget(
      OutputConfiguration(
        mode: OutputMode.plainText,
        color: false,
        alternateScreen: false,
        child: widget,
      ),
    );
    await binding.pump();
    final buffer = binding.lastBuffer;
    if (buffer == null) {
      throw StateError('The widget did not produce a terminal frame.');
    }
    return PlainOutputResult(buffer: buffer, size: size);
  } finally {
    binding.shutdown();
  }
}

class _PlainOutputBinding extends CinderBinding with SchedulerBinding {
  _PlainOutputBinding(this.size) {
    _initializePipelineOwner();
  }

  final Size size;
  PipelineOwner? _pipelineOwner;
  PipelineOwner get pipelineOwner => _pipelineOwner!;
  Buffer? lastBuffer;

  void _initializePipelineOwner() {
    _pipelineOwner = PipelineOwner()..onNeedsVisualUpdate = scheduleFrame;
  }

  @override
  void initializeBinding() {
    super.initializeBinding();
    addPersistentFrameCallback(_drawFrame);
  }

  @override
  void scheduleFrameImpl() {
    // Frames are driven explicitly by pump().
  }

  Future<void> pump() async {
    final timestamp =
        Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    handleBeginFrame(timestamp);
    await Future<void>.delayed(Duration.zero);
  }

  void _drawFrame(Duration timestamp) {
    final root = rootElement;
    if (root == null) return;
    super.drawFrame();

    final buffer = Buffer(size.width.toInt(), size.height.toInt());
    final renderObject = _findRenderObject(root);
    if (renderObject != null) {
      if (renderObject.owner != pipelineOwner) {
        renderObject.attach(pipelineOwner);
      }
      renderObject.layout(BoxConstraints.tight(size));
      pipelineOwner.flushLayout();
      pipelineOwner.flushPaint();
      final canvas = TerminalCanvas(
        buffer,
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
      renderObject.paintWithContext(canvas, Offset.zero);
    }
    lastBuffer = buffer;
  }

  RenderObject? _findRenderObject(Element element) {
    if (element is RenderObjectElement) return element.renderObject;
    RenderObject? result;
    element.visitChildren((child) => result ??= _findRenderObject(child));
    return result;
  }

  void shutdown() {
    rootElement?.deactivate();
    rootElement?.unmount();
    disposeBinding();
  }
}
