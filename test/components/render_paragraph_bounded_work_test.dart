import 'package:cinder/cinder.dart';
import 'package:cinder/src/components/render_paragraph.dart';
import 'package:cinder/src/framework/terminal_canvas.dart';
import 'package:test/test.dart';

void main() {
  test('maxLines does not map styles for hidden graphemes', () {
    final hidden = _CountingSegment(
      'hidden ' * 2000,
      const TextStyle(color: Colors.blue),
    );
    final span = _InstrumentedSpan([
      const StyledTextSegment('abc\n', TextStyle(color: Colors.red)),
      hidden,
    ]);
    final paragraph = RenderParagraph(text: span, maxLines: 1)
      ..layout(BoxConstraints.tight(const Size(8, 1)));
    final buffer = Buffer(8, 1);
    paragraph.paintWithContext(
      TerminalCanvas(buffer, const Rect.fromLTWH(0, 0, 8, 1)),
      Offset.zero,
    );

    expect(hidden.styleReads, 0);
    expect(buffer.getCell(0, 0).char, 'a');
    expect(buffer.getCell(0, 0).style.color, Colors.red);
    expect(paragraph.selectableLayout!.didOverflowHeight, isTrue);
  });
}

class _CountingSegment extends StyledTextSegment {
  _CountingSegment(super.text, super.style);

  int styleReads = 0;

  @override
  TextStyle? get style {
    styleReads++;
    return super.style;
  }
}

class _InstrumentedSpan extends TextSpan {
  _InstrumentedSpan(this.segments)
    : super(text: segments.map((segment) => segment.text).join());

  final List<StyledTextSegment> segments;

  @override
  List<StyledTextSegment> toStyledSegments([TextStyle? parentStyle]) =>
      segments;
}
