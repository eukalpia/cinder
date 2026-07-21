import 'package:cinder/cinder.dart' hide TextAlign;

import '../components/render_text.dart' show TextAlign, TextOverflow;

/// A text widget with an explicit terminal trust boundary.
///
/// Use [TerminalText.safe] for LLM, shell, Git, file, network, Markdown, log,
/// and other untrusted output. Use [TerminalText.trusted] only for
/// framework-generated display text that contains no terminal control bytes.
class TerminalText extends StatelessWidget {
  TerminalText.safe(
    String input, {
    super.key,
    this.style,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.textAlign = TextAlign.left,
    this.maxLines,
    int tabWidth = 4,
  }) : data = TerminalTextSanitizer.sanitize(input, tabWidth: tabWidth),
       trusted = false;

  TerminalText.trusted(
    String input, {
    super.key,
    this.style,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.textAlign = TextAlign.left,
    this.maxLines,
  }) : data = TerminalTextSanitizer.requireDisplaySafe(input),
       trusted = true;

  /// Sanitized display data.
  final String data;

  /// Whether the caller asserted that this is framework-generated display text.
  final bool trusted;

  final TextStyle? style;
  final bool softWrap;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      softWrap: softWrap,
      overflow: overflow,
      textAlign: textAlign,
      maxLines: maxLines,
    );
  }
}
