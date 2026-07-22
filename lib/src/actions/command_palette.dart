import '../components/basic.dart';
import '../components/gesture_detector.dart';
import '../components/focus.dart';
import '../components/list_view.dart';
import '../components/text_field.dart';
import '../framework/framework.dart';
import '../keyboard/keyboard_event.dart';
import '../keyboard/logical_key.dart';
import '../style.dart';
import '../theme/tui_theme.dart';
import 'actions.dart';

/// Searchable command surface backed by [CommandScope] and [Actions].
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    this.commands,
    this.title = 'Command palette',
    this.placeholder = 'Type a command…',
    this.width = 56,
    this.height = 14,
    this.maxResults = 100,
    this.onDismiss,
    this.onInvoked,
  });

  final List<Command>? commands;
  final String title;
  final String placeholder;
  final double width;
  final double height;
  final int maxResults;
  final VoidCallback? onDismiss;
  final void Function(Command command, Object? result)? onInvoked;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  late final TextEditingController _queryController;
  late final FocusNode _queryFocus;
  List<Command> _results = const <Command>[];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _queryFocus = FocusNode(debugLabel: 'Command palette query');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _filter(_queryController.text, rebuild: false);
  }

  @override
  void didUpdateWidget(CommandPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.commands, oldWidget.commands) ||
        widget.maxResults != oldWidget.maxResults) {
      _filter(_queryController.text);
    }
  }

  List<Command> get _commands => widget.commands ?? CommandScope.of(context);

  void _filter(String query, {bool rebuild = true}) {
    final matches = _commands
        .where((command) => command.enabled && command.matches(query))
        .take(widget.maxResults)
        .toList(growable: false);
    void update() {
      _results = matches;
      _selectedIndex =
          matches.isEmpty ? 0 : _selectedIndex.clamp(0, matches.length - 1);
    }

    if (rebuild && mounted) {
      setState(update);
    } else {
      update();
    }
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta) % _results.length;
      if (_selectedIndex < 0) _selectedIndex += _results.length;
    });
  }

  void _invoke(Command command) {
    if (!command.enabled || !Actions.isEnabled(context, command.intent)) return;
    final result = Actions.invoke(context, command.intent);
    widget.onInvoked?.call(command, result);
    widget.onDismiss?.call();
  }

  bool _handleQueryKey(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.arrowDown) {
      _move(1);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _move(-1);
      return true;
    }
    if (event.logicalKey == LogicalKey.pageDown) {
      _move(5);
      return true;
    }
    if (event.logicalKey == LogicalKey.pageUp) {
      _move(-5);
      return true;
    }
    if (event.logicalKey == LogicalKey.enter && _results.isNotEmpty) {
      _invoke(_results[_selectedIndex]);
      return true;
    }
    if (event.logicalKey == LogicalKey.escape) {
      widget.onDismiss?.call();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Container(
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: theme.surface,
        border: BoxBorder.all(
          color: theme.primary,
          style: BoxBorderStyle.rounded,
        ),
        title: BorderTitle(
          text: widget.title,
          style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _queryController,
            focusNode: _queryFocus,
            autofocus: true,
            placeholder: widget.placeholder,
            width: widget.width - 4,
            onChanged: _filter,
            onKeyEvent: _handleQueryKey,
          ),
          const SizedBox(height: 1),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      'No matching commands',
                      style: TextStyle(color: theme.outline),
                    ),
                  )
                : ListView.builder(
                    lazy: true,
                    itemExtent: 1,
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final command = _results[index];
                      final selected = index == _selectedIndex;
                      return GestureDetector(
                        onTap: () => _invoke(command),
                        child: Container(
                          color: selected ? theme.primary : null,
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  command.label,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected
                                        ? theme.onPrimary
                                        : theme.onSurface,
                                  ),
                                ),
                              ),
                              if (command.shortcut != null)
                                Text(
                                  command.shortcut!.label,
                                  style: TextStyle(
                                    color: selected
                                        ? theme.onPrimary
                                        : theme.outline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Text(
            '${_results.length} command${_results.length == 1 ? '' : 's'}',
            style: TextStyle(color: theme.outline),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _queryFocus.dispose();
    _queryController.dispose();
    super.dispose();
  }
}
