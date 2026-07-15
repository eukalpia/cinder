import 'package:cinder/cinder.dart';

class CommandItem {
  const CommandItem({
    required this.id,
    required this.label,
    required this.action,
    this.description,
    this.keywords = const [],
    this.shortcut,
    this.enabled = true,
  });

  final String id;
  final String label;
  final String? description;
  final List<String> keywords;
  final String? shortcut;
  final bool enabled;
  final VoidCallback action;
}

class CommandPaletteController extends ChangeNotifier {
  String _query = '';
  int _selectedIndex = 0;

  String get query => _query;
  int get selectedIndex => _selectedIndex;

  set query(String value) {
    if (_query == value) return;
    _query = value;
    _selectedIndex = 0;
    notifyListeners();
  }

  set selectedIndex(int value) {
    final next = value < 0 ? 0 : value;
    if (_selectedIndex == next) return;
    _selectedIndex = next;
    notifyListeners();
  }

  void reset() {
    _query = '';
    _selectedIndex = 0;
    notifyListeners();
  }
}

class _ScoredCommand {
  const _ScoredCommand(this.command, this.score);
  final CommandItem command;
  final int score;
}

/// Searchable keyboard-first command launcher.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.commands,
    this.controller,
    this.placeholder = 'Type a command…',
    this.emptyMessage = 'No matching commands',
    this.width = 70,
    this.height = 18,
    this.onSelected,
    this.onDismiss,
    this.autofocus = true,
    this.selectedColor,
  });

  final List<CommandItem> commands;
  final CommandPaletteController? controller;
  final String placeholder;
  final String emptyMessage;
  final double width;
  final double height;
  final ValueChanged<CommandItem>? onSelected;
  final VoidCallback? onDismiss;
  final bool autofocus;
  final Color? selectedColor;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  CommandPaletteController? _ownedController;
  late CommandPaletteController _controller;
  late TextEditingController _textController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _attachController();
    _textController = TextEditingController(text: _controller.query);
  }

  void _attachController() {
    _ownedController = widget.controller == null
        ? CommandPaletteController()
        : null;
    _controller = widget.controller ?? _ownedController!;
    _controller.addListener(_handleControllerChanged);
  }

  void _detachController() {
    _controller.removeListener(_handleControllerChanged);
    _ownedController?.dispose();
    _ownedController = null;
  }

  @override
  void didUpdateWidget(CommandPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _detachController();
      _attachController();
      _textController.text = _controller.query;
    }
  }

  void _handleControllerChanged() {
    if (_textController.text != _controller.query) {
      _textController.text = _controller.query;
    }
    if (mounted) setState(() {});
  }

  static int _score(String query, String candidate) {
    if (query.isEmpty) return 0;
    final needle = query.toLowerCase();
    final haystack = candidate.toLowerCase();
    final exact = haystack.indexOf(needle);
    if (exact >= 0) return 10000 - exact * 10 - haystack.length;

    var score = 0;
    var queryIndex = 0;
    var previousMatch = -2;
    for (
      var index = 0;
      index < haystack.length && queryIndex < needle.length;
      index++
    ) {
      if (haystack.codeUnitAt(index) != needle.codeUnitAt(queryIndex)) continue;
      score += previousMatch + 1 == index ? 20 : 5;
      if (index == 0 || ' /_-'.contains(haystack[index - 1])) score += 15;
      previousMatch = index;
      queryIndex++;
    }
    return queryIndex == needle.length ? score : -1;
  }

  List<CommandItem> _filteredCommands() {
    final query = _controller.query.trim();
    if (query.isEmpty) {
      return widget.commands.where((command) => command.enabled).toList();
    }

    final scored = <_ScoredCommand>[];
    for (final command in widget.commands) {
      if (!command.enabled) continue;
      final searchable = <String>[
        command.label,
        command.description ?? '',
        command.id,
        ...command.keywords,
      ].join(' ');
      final score = _score(query, searchable);
      if (score >= 0) scored.add(_ScoredCommand(command, score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0
          ? byScore
          : a.command.label.compareTo(b.command.label);
    });
    return scored.map((entry) => entry.command).toList(growable: false);
  }

  void _execute(CommandItem command) {
    command.action();
    widget.onSelected?.call(command);
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    final commands = _filteredCommands();
    if (event.logicalKey == LogicalKey.escape) {
      widget.onDismiss?.call();
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowDown) {
      if (commands.isNotEmpty) {
        _controller.selectedIndex = (_controller.selectedIndex + 1).clamp(
          0,
          commands.length - 1,
        );
        _scrollController.ensureIndexVisible(index: _controller.selectedIndex);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      if (commands.isNotEmpty) {
        _controller.selectedIndex = (_controller.selectedIndex - 1).clamp(
          0,
          commands.length - 1,
        );
        _scrollController.ensureIndexVisible(index: _controller.selectedIndex);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      if (commands.isNotEmpty) {
        _execute(
          commands[_controller.selectedIndex.clamp(0, commands.length - 1)],
        );
      }
      return true;
    }
    return false;
  }

  Widget _buildCommandRow(CommandItem command, int index, int selectedIndex) {
    final selected = index == selectedIndex;
    Widget row = Row(
      children: [
        SizedBox(
          width: 2,
          child: Text(
            selected ? '›' : ' ',
            style: const TextStyle(color: Colors.cyan),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TerminalText.safe(
                command.label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (command.description != null)
                TerminalText.safe(
                  command.description!,
                  style: const TextStyle(color: Colors.grey),
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
            ],
          ),
        ),
        if (command.shortcut != null)
          TerminalText.safe(
            command.shortcut!,
            style: const TextStyle(color: Colors.grey),
            softWrap: false,
            maxLines: 1,
          ),
      ],
    );

    if (selected) {
      row = Container(
        color: widget.selectedColor ?? const Color.fromRGB(40, 48, 68),
        child: row,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _controller.selectedIndex = index,
      onDoubleTap: () => _execute(command),
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final commands = _filteredCommands();
    final selectedIndex = commands.isEmpty
        ? 0
        : _controller.selectedIndex.clamp(0, commands.length - 1).toInt();

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color.fromRGB(20, 23, 32),
        border: BoxBorder.all(
          color: Colors.cyan,
          style: BoxBorderStyle.rounded,
        ),
        title: const BorderTitle(text: ' Command Palette '),
      ),
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _textController,
            autofocus: widget.autofocus,
            placeholder: widget.placeholder,
            onChanged: (value) => _controller.query = value,
            onKeyEvent: _handleKeyEvent,
          ),
          const Divider(),
          Expanded(
            child: commands.isEmpty
                ? Center(
                    child: TerminalText.safe(
                      widget.emptyMessage,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : VirtualListView.builder(
                    controller: _scrollController,
                    itemExtent: 2,
                    cacheExtent: 4,
                    itemCount: commands.length,
                    itemBuilder: (context, index) =>
                        _buildCommandRow(commands[index], index, selectedIndex),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _detachController();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
