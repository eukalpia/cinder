import 'package:cinder/cinder.dart';

/// Visual kind of a unified-diff line.
enum DiffLineType {
  fileHeader,
  hunkHeader,
  context,
  addition,
  deletion,
  notice,
}

enum DiffViewMode { unified, sideBySide }

class DiffLine {
  const DiffLine({
    required this.type,
    required this.text,
    this.oldLineNumber,
    this.newLineNumber,
    this.hunkIndex,
  });

  final DiffLineType type;
  final String text;
  final int? oldLineNumber;
  final int? newLineNumber;
  final int? hunkIndex;
}

class DiffHunk {
  const DiffHunk({
    required this.index,
    required this.header,
    required this.startLine,
    required this.endLine,
  });

  final int index;
  final String header;
  final int startLine;
  final int endLine;
}

class ParsedDiff {
  const ParsedDiff({required this.lines, required this.hunks});

  final List<DiffLine> lines;
  final List<DiffHunk> hunks;

  static ParsedDiff parse(String source) {
    final result = <DiffLine>[];
    final hunks = <DiffHunk>[];
    final inputLines = source.replaceAll('\r\n', '\n').split('\n');
    var oldLine = 0;
    var newLine = 0;
    var hunkIndex = -1;
    var hunkStart = -1;
    var hunkHeader = '';

    void closeHunk() {
      if (hunkIndex < 0 || hunkStart < 0) return;
      hunks.add(
        DiffHunk(
          index: hunkIndex,
          header: hunkHeader,
          startLine: hunkStart,
          endLine: result.length,
        ),
      );
      hunkStart = -1;
    }

    final hunkPattern = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

    for (final rawLine in inputLines) {
      if (rawLine.startsWith('diff ') ||
          rawLine.startsWith('index ') ||
          rawLine.startsWith('--- ') ||
          rawLine.startsWith('+++ ')) {
        result.add(DiffLine(type: DiffLineType.fileHeader, text: rawLine));
        continue;
      }

      final match = hunkPattern.firstMatch(rawLine);
      if (match != null) {
        closeHunk();
        hunkIndex++;
        hunkStart = result.length;
        hunkHeader = rawLine;
        oldLine = int.parse(match.group(1)!);
        newLine = int.parse(match.group(3)!);
        result.add(
          DiffLine(
            type: DiffLineType.hunkHeader,
            text: rawLine,
            hunkIndex: hunkIndex,
          ),
        );
        continue;
      }

      if (rawLine.startsWith('+') && !rawLine.startsWith('+++')) {
        result.add(
          DiffLine(
            type: DiffLineType.addition,
            text: rawLine.substring(1),
            newLineNumber: newLine++,
            hunkIndex: hunkIndex >= 0 ? hunkIndex : null,
          ),
        );
      } else if (rawLine.startsWith('-') && !rawLine.startsWith('---')) {
        result.add(
          DiffLine(
            type: DiffLineType.deletion,
            text: rawLine.substring(1),
            oldLineNumber: oldLine++,
            hunkIndex: hunkIndex >= 0 ? hunkIndex : null,
          ),
        );
      } else if (rawLine.startsWith(' ')) {
        result.add(
          DiffLine(
            type: DiffLineType.context,
            text: rawLine.substring(1),
            oldLineNumber: oldLine++,
            newLineNumber: newLine++,
            hunkIndex: hunkIndex >= 0 ? hunkIndex : null,
          ),
        );
      } else if (rawLine.startsWith('\\')) {
        result.add(
          DiffLine(
            type: DiffLineType.notice,
            text: rawLine,
            hunkIndex: hunkIndex >= 0 ? hunkIndex : null,
          ),
        );
      } else {
        result.add(DiffLine(type: DiffLineType.context, text: rawLine));
      }
    }
    closeHunk();
    return ParsedDiff(
      lines: List<DiffLine>.unmodifiable(result),
      hunks: List<DiffHunk>.unmodifiable(hunks),
    );
  }
}

class DiffViewController extends ChangeNotifier {
  int _selectedLine = 0;
  int get selectedLine => _selectedLine;

  set selectedLine(int value) {
    final next = value < 0 ? 0 : value;
    if (_selectedLine == next) return;
    _selectedLine = next;
    notifyListeners();
  }
}

/// Virtualized unified/side-by-side diff viewer with hunk actions.
class DiffView extends StatefulWidget {
  const DiffView({
    super.key,
    required this.diff,
    this.controller,
    this.mode = DiffViewMode.unified,
    this.autofocus = false,
    this.showLineNumbers = true,
    this.onAcceptHunk,
    this.onRejectHunk,
    this.selectedColor,
  });

  final String diff;
  final DiffViewController? controller;
  final DiffViewMode mode;
  final bool autofocus;
  final bool showLineNumbers;
  final ValueChanged<DiffHunk>? onAcceptHunk;
  final ValueChanged<DiffHunk>? onRejectHunk;
  final Color? selectedColor;

  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
  DiffViewController? _ownedController;
  late DiffViewController _controller;
  final ScrollController _scrollController = ScrollController();
  late ParsedDiff _parsed;

  @override
  void initState() {
    super.initState();
    _parsed = ParsedDiff.parse(widget.diff);
    _attachController();
  }

  void _attachController() {
    _ownedController = widget.controller == null ? DiffViewController() : null;
    _controller = widget.controller ?? _ownedController!;
    _controller.addListener(_handleControllerChanged);
  }

  void _detachController() {
    _controller.removeListener(_handleControllerChanged);
    _ownedController?.dispose();
    _ownedController = null;
  }

  @override
  void didUpdateWidget(DiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.diff != oldWidget.diff) {
      _parsed = ParsedDiff.parse(widget.diff);
      _controller.selectedLine = _controller.selectedLine.clamp(
        0,
        _parsed.lines.isEmpty ? 0 : _parsed.lines.length - 1,
      );
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      _detachController();
      _attachController();
    }
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  DiffHunk? _selectedHunk() {
    if (_parsed.lines.isEmpty) return null;
    final line = _parsed
        .lines[_controller.selectedLine.clamp(0, _parsed.lines.length - 1)];
    final index = line.hunkIndex;
    if (index == null || index < 0 || index >= _parsed.hunks.length) {
      return null;
    }
    return _parsed.hunks[index];
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    if (_parsed.lines.isEmpty) return false;
    if (event.logicalKey == LogicalKey.arrowDown) {
      _controller.selectedLine = (_controller.selectedLine + 1).clamp(
        0,
        _parsed.lines.length - 1,
      );
      _scrollController.ensureIndexVisible(index: _controller.selectedLine);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _controller.selectedLine = (_controller.selectedLine - 1).clamp(
        0,
        _parsed.lines.length - 1,
      );
      _scrollController.ensureIndexVisible(index: _controller.selectedLine);
      return true;
    }
    if (event.logicalKey == LogicalKey.keyA) {
      final hunk = _selectedHunk();
      if (hunk != null) widget.onAcceptHunk?.call(hunk);
      return hunk != null;
    }
    if (event.logicalKey == LogicalKey.keyR) {
      final hunk = _selectedHunk();
      if (hunk != null) widget.onRejectHunk?.call(hunk);
      return hunk != null;
    }
    return false;
  }

  ({String marker, TextStyle style}) _presentation(DiffLine line) {
    switch (line.type) {
      case DiffLineType.addition:
        return (
          marker: '+',
          style: const TextStyle(
            color: Colors.green,
            backgroundColor: Color.fromRGB(18, 45, 28),
          ),
        );
      case DiffLineType.deletion:
        return (
          marker: '-',
          style: const TextStyle(
            color: Colors.red,
            backgroundColor: Color.fromRGB(55, 22, 24),
          ),
        );
      case DiffLineType.hunkHeader:
        return (
          marker: '@',
          style: const TextStyle(
            color: Colors.cyan,
            backgroundColor: Color.fromRGB(22, 35, 55),
            fontWeight: FontWeight.bold,
          ),
        );
      case DiffLineType.fileHeader:
        return (
          marker: ' ',
          style: const TextStyle(
            color: Colors.yellow,
            fontWeight: FontWeight.bold,
          ),
        );
      case DiffLineType.notice:
        return (
          marker: '!',
          style: const TextStyle(
            color: Colors.grey,
            fontStyle: FontStyle.italic,
          ),
        );
      case DiffLineType.context:
        return (marker: ' ', style: const TextStyle());
    }
  }

  String _lineNumber(int? value) => value?.toString().padLeft(4) ?? '    ';

  Widget _buildUnifiedLine(int index, DiffLine line) {
    final presentation = _presentation(line);
    Widget row = Row(
      children: [
        if (widget.showLineNumbers) ...[
          SizedBox(
            width: 5,
            child: Text(
              _lineNumber(line.oldLineNumber),
              style: const TextStyle(color: Colors.grey),
              softWrap: false,
            ),
          ),
          SizedBox(
            width: 5,
            child: Text(
              _lineNumber(line.newLineNumber),
              style: const TextStyle(color: Colors.grey),
              softWrap: false,
            ),
          ),
        ],
        SizedBox(
          width: 2,
          child: Text(presentation.marker, style: presentation.style),
        ),
        Expanded(
          child: TerminalText.safe(
            line.text,
            style: presentation.style,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );

    if (_controller.selectedLine == index) {
      row = Container(
        color: widget.selectedColor ?? const Color.fromRGB(40, 44, 58),
        child: row,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.selectedLine = index,
      child: row,
    );
  }

  List<({DiffLine? left, DiffLine? right})> _sideBySideRows() {
    final rows = <({DiffLine? left, DiffLine? right})>[];
    for (var index = 0; index < _parsed.lines.length; index++) {
      final line = _parsed.lines[index];
      if (line.type == DiffLineType.deletion &&
          index + 1 < _parsed.lines.length &&
          _parsed.lines[index + 1].type == DiffLineType.addition) {
        rows.add((left: line, right: _parsed.lines[index + 1]));
        index++;
      } else if (line.type == DiffLineType.deletion) {
        rows.add((left: line, right: null));
      } else if (line.type == DiffLineType.addition) {
        rows.add((left: null, right: line));
      } else {
        rows.add((left: line, right: line));
      }
    }
    return rows;
  }

  Widget _buildSideCell(DiffLine? line, {required bool oldSide}) {
    if (line == null) return const SizedBox.expand();
    final presentation = _presentation(line);
    final number = oldSide ? line.oldLineNumber : line.newLineNumber;
    return Row(
      children: [
        if (widget.showLineNumbers)
          SizedBox(
            width: 5,
            child: Text(
              _lineNumber(number),
              style: const TextStyle(color: Colors.grey),
              softWrap: false,
            ),
          ),
        SizedBox(
          width: 2,
          child: Text(presentation.marker, style: presentation.style),
        ),
        Expanded(
          child: TerminalText.safe(
            line.text,
            style: presentation.style,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == DiffViewMode.sideBySide) {
      final rows = _sideBySideRows();
      return Focus(
        autofocus: widget.autofocus,
        onKeyEvent: _handleKeyEvent,
        child: VirtualListView.builder(
          itemExtent: 1,
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Row(
              children: [
                Expanded(child: _buildSideCell(row.left, oldSide: true)),
                const Text('│', style: TextStyle(color: Colors.grey)),
                Expanded(child: _buildSideCell(row.right, oldSide: false)),
              ],
            );
          },
        ),
      );
    }

    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: VirtualListView.builder(
        controller: _scrollController,
        itemExtent: 1,
        itemCount: _parsed.lines.length,
        itemBuilder: (context, index) =>
            _buildUnifiedLine(index, _parsed.lines[index]),
      ),
    );
  }

  @override
  void dispose() {
    _detachController();
    _scrollController.dispose();
    super.dispose();
  }
}
