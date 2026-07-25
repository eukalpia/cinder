import '../foundation/widget_state.dart';
import '../framework/framework.dart';
import '../style.dart';
import '../theme/tui_theme.dart';
import 'basic.dart';
import 'controls.dart';
import 'focus.dart';
import 'mouse_region.dart';

/// A bordered terminal dialog surface that can be shown through Navigator.
class Dialog extends StatelessWidget {
  const Dialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const <Widget>[],
    this.width = 56,
    this.padding = const EdgeInsets.all(1),
  });

  final String? title;
  final Widget content;
  final List<Widget> actions;
  final double width;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: theme.surface,
        border: BoxBorder.all(
          color: theme.outline,
          style: BoxBorderStyle.rounded,
        ),
        title: title == null
            ? null
            : BorderTitle(
                text: title!,
                style: TextStyle(
                  color: theme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          content,
          if (actions.isNotEmpty) const SizedBox(height: 1),
          if (actions.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                for (var index = 0;
                    index < actions.length;
                    index++) ...<Widget>[
                  if (index > 0) const SizedBox(width: 1),
                  actions[index],
                ],
              ],
            ),
        ],
      ),
    );
  }
}

/// Opinionated dialog for confirmations, warnings, and errors.
class AlertDialog extends StatelessWidget {
  const AlertDialog({
    super.key,
    this.title,
    required this.message,
    this.level = StatusLevel.info,
    this.actions = const <Widget>[],
    this.width = 56,
  });

  final String? title;
  final String message;
  final StatusLevel level;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final color = switch (level) {
      StatusLevel.neutral => theme.onSurface,
      StatusLevel.info => theme.primary,
      StatusLevel.success => theme.success,
      StatusLevel.warning => theme.warning,
      StatusLevel.error => theme.error,
    };
    return Dialog(
      title: title,
      width: width,
      actions: actions,
      content: Text(message, style: TextStyle(color: color), softWrap: true),
    );
  }
}

/// One action in a [Menu].
class MenuItem {
  const MenuItem({
    required this.label,
    this.onSelected,
    this.shortcut,
    this.leading,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onSelected;
  final String? shortcut;
  final Widget? leading;
  final bool destructive;
}

/// Keyboard-first vertical menu with consistent button states.
class Menu extends StatelessWidget {
  const Menu({
    super.key,
    required this.items,
    this.width = 32,
    this.autofocus = true,
  });

  final List<MenuItem> items;
  final double width;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return FocusScope(
      autofocus: autofocus,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: theme.surface,
          border: BoxBorder.all(
            color: theme.outline,
            style: BoxBorderStyle.rounded,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var index = 0; index < items.length; index++) ...<Widget>[
              if (index > 0) const SizedBox(height: 1),
              Button(
                autofocus: autofocus && index == 0,
                onPressed: items[index].onSelected,
                style: ButtonStyle(
                  borderColor:
                      WidgetStateProperty.all<Color?>(theme.outlineVariant),
                  foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                    (states) => items[index].destructive
                        ? theme.error
                        : states.contains(WidgetState.focused) ||
                                states.contains(WidgetState.hovered)
                            ? theme.onPrimary
                            : theme.onSurface,
                  ),
                  padding: EdgeInsets.zero,
                  borderStyle: BoxBorderStyle.none,
                ),
                semanticLabel: items[index].label,
                child: Row(
                  children: <Widget>[
                    if (items[index].leading != null) items[index].leading!,
                    if (items[index].leading != null) const SizedBox(width: 1),
                    Expanded(child: Text(items[index].label)),
                    if (items[index].shortcut != null)
                      Text(
                        items[index].shortcut!,
                        style: TextStyle(color: theme.outline),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Combines [TabBar] with the selected content pane.
class Tabs extends StatelessWidget {
  const Tabs({
    super.key,
    required this.tabs,
    required this.children,
    required this.selectedIndex,
    required this.onSelected,
    this.spacing = 1,
  }) : assert(tabs.length == children.length);

  final List<TabItem> tabs;
  final List<Widget> children;
  final int selectedIndex;
  final void Function(int index) onSelected;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final safeIndex =
        children.isEmpty ? 0 : selectedIndex.clamp(0, children.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TabBar(
          tabs: tabs,
          selectedIndex: safeIndex,
          onSelected: onSelected,
        ),
        SizedBox(height: spacing),
        if (children.isNotEmpty) Expanded(child: children[safeIndex]),
      ],
    );
  }
}

/// Shows a compact explanation only while its child is focused or hovered.
class Tooltip extends StatefulWidget {
  const Tooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<Tooltip> createState() => _TooltipState();
}

class _TooltipState extends State<Tooltip> {
  bool _visible = false;

  void _setVisible(bool value) {
    if (_visible == value) return;
    setState(() => _visible = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Focus(
      canRequestFocus: false,
      onFocusChange: _setVisible,
      child: MouseRegion(
        onEnter: (_) => _setVisible(true),
        onExit: (_) => _setVisible(false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            widget.child,
            if (_visible)
              Text(widget.message, style: TextStyle(color: theme.outline)),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.description,
    this.action,
  });

  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: theme.onBackground,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (description != null)
            Text(description!, style: TextStyle(color: theme.outline)),
          if (action != null) const SizedBox(height: 1),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    this.description,
    this.retry,
  });

  final String title;
  final String? description;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(color: theme.error, fontWeight: FontWeight.bold),
          ),
          if (description != null)
            Text(description!, style: TextStyle(color: theme.outline)),
          if (retry != null) const SizedBox(height: 1),
          if (retry != null) Button.text('Retry', onPressed: retry),
        ],
      ),
    );
  }
}

/// Static loading placeholder that degrades cleanly without animation.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.lines = 3,
    this.width = 24,
    this.character = '▒',
  });

  final int lines;
  final int width;
  final String character;

  @override
  Widget build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var index = 0; index < lines; index++)
          Text(
            character * (width - (index.isOdd ? width ~/ 4 : 0)),
            style: TextStyle(color: theme.outlineVariant),
          ),
      ],
    );
  }
}
