import 'package:cinder/cinder.dart';

/// A tab displayed by [Tabs] or [TabBar].
class TabItem {
  const TabItem({
    required this.id,
    required this.label,
    required this.child,
    this.icon,
    this.closeable = false,
    this.disabled = false,
  });

  final Object id;
  final String label;
  final Widget child;
  final Widget? icon;
  final bool closeable;
  final bool disabled;
}

/// Controls the active tab.
class TabsController extends ChangeNotifier {
  TabsController({Object? selectedId}) : _selectedId = selectedId;

  Object? _selectedId;
  Object? get selectedId => _selectedId;

  set selectedId(Object? value) {
    if (_selectedId == value) return;
    _selectedId = value;
    notifyListeners();
  }

  void select(Object id) => selectedId = id;
}

/// Keyboard- and mouse-accessible tab strip.
class TabBar extends StatefulWidget {
  const TabBar({
    super.key,
    required this.tabs,
    required this.controller,
    this.onSelected,
    this.onClose,
    this.autofocus = false,
    this.selectedColor,
    this.divider = '│',
  });

  final List<TabItem> tabs;
  final TabsController controller;
  final ValueChanged<TabItem>? onSelected;
  final ValueChanged<TabItem>? onClose;
  final bool autofocus;
  final Color? selectedColor;
  final String divider;

  @override
  State<TabBar> createState() => _TabBarState();
}

class _TabBarState extends State<TabBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(TabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  int _selectedIndex() {
    final index = widget.tabs.indexWhere(
      (tab) => tab.id == widget.controller.selectedId && !tab.disabled,
    );
    if (index >= 0) return index;
    return widget.tabs.indexWhere((tab) => !tab.disabled);
  }

  void _select(TabItem tab) {
    if (tab.disabled) return;
    widget.controller.select(tab.id);
    widget.onSelected?.call(tab);
  }

  bool _handleKey(KeyboardEvent event) {
    if (widget.tabs.isEmpty) return false;
    final current = _selectedIndex();
    int? next;
    if (event.logicalKey == LogicalKey.arrowRight ||
        event.logicalKey == LogicalKey.arrowDown) {
      next = current < 0 ? 0 : current + 1;
    } else if (event.logicalKey == LogicalKey.arrowLeft ||
        event.logicalKey == LogicalKey.arrowUp) {
      next = current < 0 ? widget.tabs.length - 1 : current - 1;
    } else if (event.logicalKey == LogicalKey.home) {
      next = 0;
    } else if (event.logicalKey == LogicalKey.end) {
      next = widget.tabs.length - 1;
    } else if (event.logicalKey == LogicalKey.delete && current >= 0) {
      final tab = widget.tabs[current];
      if (tab.closeable) widget.onClose?.call(tab);
      return tab.closeable;
    } else {
      return false;
    }

    for (var attempt = 0; attempt < widget.tabs.length; attempt++) {
      final index = next!.clamp(0, widget.tabs.length - 1).toInt();
      final tab = widget.tabs[index];
      if (!tab.disabled) {
        _select(tab);
        return true;
      }
      next =
          event.logicalKey == LogicalKey.arrowLeft ||
              event.logicalKey == LogicalKey.arrowUp
          ? (index - 1 + widget.tabs.length) % widget.tabs.length
          : (index + 1) % widget.tabs.length;
    }
    return false;
  }

  Widget _buildTab(TabItem tab) {
    final selected = tab.id == widget.controller.selectedId;
    final style = TextStyle(
      color: tab.disabled ? Colors.grey : null,
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
    );
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tab.icon != null) ...[tab.icon!, const SizedBox(width: 1)],
        TerminalText.safe(
          tab.label,
          style: style,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (tab.closeable) ...[
          const SizedBox(width: 1),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onClose?.call(tab),
            child: Text('×', style: style),
          ),
        ],
      ],
    );
    content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: content,
    );
    if (selected) {
      content = Container(
        color: widget.selectedColor ?? const Color.fromRGB(43, 49, 67),
        child: content,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(tab),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var index = 0; index < widget.tabs.length; index++) {
      if (index > 0) {
        children.add(
          Text(widget.divider, style: const TextStyle(color: Colors.grey)),
        );
      }
      children.add(_buildTab(widget.tabs[index]));
    }
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: Row(children: children),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }
}

/// A complete tab container with a tab strip and active page.
class Tabs extends StatefulWidget {
  const Tabs({
    super.key,
    required this.tabs,
    this.controller,
    this.initialSelectedId,
    this.onSelected,
    this.onClose,
    this.autofocus = false,
    this.tabBarAtBottom = false,
  });

  final List<TabItem> tabs;
  final TabsController? controller;
  final Object? initialSelectedId;
  final ValueChanged<TabItem>? onSelected;
  final ValueChanged<TabItem>? onClose;
  final bool autofocus;
  final bool tabBarAtBottom;

  @override
  State<Tabs> createState() => _TabsState();
}

class _TabsState extends State<Tabs> {
  TabsController? _owned;
  late TabsController _controller;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final initial =
        widget.initialSelectedId ??
        widget.tabs.where((tab) => !tab.disabled).firstOrNull?.id;
    _owned = widget.controller == null
        ? TabsController(selectedId: initial)
        : null;
    _controller = widget.controller ?? _owned!;
    _controller.addListener(_changed);
  }

  void _detach() {
    _controller.removeListener(_changed);
    _owned?.dispose();
    _owned = null;
  }

  @override
  void didUpdateWidget(Tabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach();
      _attach();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  TabItem? _activeTab() {
    for (final tab in widget.tabs) {
      if (tab.id == _controller.selectedId && !tab.disabled) return tab;
    }
    for (final tab in widget.tabs) {
      if (!tab.disabled) return tab;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeTab();
    final bar = TabBar(
      tabs: widget.tabs,
      controller: _controller,
      autofocus: widget.autofocus,
      onSelected: widget.onSelected,
      onClose: widget.onClose,
    );
    final page = Expanded(child: active?.child ?? const SizedBox.expand());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.tabBarAtBottom
          ? [page, const Divider(), bar]
          : [bar, const Divider(), page],
    );
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}

/// The edge used by [Drawer].
enum DrawerEdge { left, right }

/// A side panel that can be composed in a [Stack] or ordinary layout.
class Drawer extends StatelessWidget {
  const Drawer({
    super.key,
    required this.child,
    this.width = 32,
    this.edge = DrawerEdge.left,
    this.title,
    this.onClose,
  });

  final Widget child;
  final double width;
  final DrawerEdge edge;
  final String? title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: TuiTheme.of(context).surface,
        border: BoxBorder.all(
          color: TuiTheme.of(context).outline,
          style: BoxBorderStyle.rounded,
        ),
        title: title == null ? null : BorderTitle(text: ' $title '),
      ),
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onClose != null)
            Align(
              alignment: edge == DrawerEdge.left
                  ? Alignment.topRight
                  : Alignment.topLeft,
              child: GestureDetector(onTap: onClose, child: const Text('×')),
            ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A bordered modal/dialog surface.
class Dialog extends StatelessWidget {
  const Dialog({
    super.key,
    required this.child,
    this.title,
    this.actions = const [],
    this.width = 60,
    this.height,
    this.padding = const EdgeInsets.all(1),
  });

  final Widget child;
  final String? title;
  final List<Widget> actions;
  final double width;
  final double? height;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: TuiTheme.of(context).surface,
        border: BoxBorder.all(
          color: TuiTheme.of(context).primary,
          style: BoxBorderStyle.rounded,
        ),
        title: title == null ? null : BorderTitle(text: ' $title '),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (height != null) Expanded(child: child) else child,
          if (actions.isNotEmpty) ...[
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ],
      ),
    );
  }
}

/// A bottom-anchored surface.
class BottomSheet extends StatelessWidget {
  const BottomSheet({
    super.key,
    required this.child,
    this.title,
    this.height = 12,
  });

  final Widget child;
  final String? title;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: TuiTheme.of(context).surface,
        border: BoxBorder.all(color: TuiTheme.of(context).outline),
        title: title == null ? null : BorderTitle(text: ' $title '),
      ),
      padding: const EdgeInsets.all(1),
      child: child,
    );
  }
}

/// Places floating content above an anchor inside a stack.
class Popover extends StatelessWidget {
  const Popover({
    super.key,
    required this.anchor,
    required this.content,
    this.open = true,
    this.left = 0,
    this.top = 1,
    this.width = 32,
    this.height,
  });

  final Widget anchor;
  final Widget content;
  final bool open;
  final double left;
  final double top;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        anchor,
        if (open)
          Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: Container(
              decoration: BoxDecoration(
                color: TuiTheme.of(context).surface,
                border: BoxBorder.all(
                  color: TuiTheme.of(context).outline,
                  style: BoxBorderStyle.rounded,
                ),
              ),
              padding: const EdgeInsets.all(1),
              child: content,
            ),
          ),
      ],
    );
  }
}

/// Shows a small help label while the child is hovered.
class Tooltip extends StatefulWidget {
  const Tooltip({
    super.key,
    required this.message,
    required this.child,
    this.width = 36,
  });

  final String message;
  final Widget child;
  final double width;

  @override
  State<Tooltip> createState() => _TooltipState();
}

class _TooltipState extends State<Tooltip> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _visible = true),
      onExit: (_) => setState(() => _visible = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_visible)
            Positioned(
              left: 0,
              top: 1,
              width: widget.width,
              child: Container(
                color: const Color.fromRGB(45, 45, 50),
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: TerminalText.safe(widget.message, softWrap: true),
              ),
            ),
        ],
      ),
    );
  }
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.label,
    required this.onSelected,
    this.shortcut,
    this.enabled = true,
    this.checked = false,
  });

  final Object id;
  final String label;
  final String? shortcut;
  final bool enabled;
  final bool checked;
  final VoidCallback onSelected;
}

/// Keyboard-first menu used for context and dropdown menus.
class ContextMenu extends StatefulWidget {
  const ContextMenu({
    super.key,
    required this.items,
    this.autofocus = true,
    this.width = 36,
    this.onDismiss,
  });

  final List<MenuItem> items;
  final bool autofocus;
  final double width;
  final VoidCallback? onDismiss;

  @override
  State<ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<ContextMenu> {
  int _selected = 0;

  int _nearestEnabled(int start, int direction) {
    if (widget.items.isEmpty) return 0;
    var index = start;
    for (var count = 0; count < widget.items.length; count++) {
      index = (index + direction + widget.items.length) % widget.items.length;
      if (widget.items[index].enabled) return index;
    }
    return _selected;
  }

  bool _key(KeyboardEvent event) {
    if (event.logicalKey == LogicalKey.escape) {
      widget.onDismiss?.call();
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowDown) {
      setState(() => _selected = _nearestEnabled(_selected, 1));
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      setState(() => _selected = _nearestEnabled(_selected, -1));
      return true;
    }
    if (event.logicalKey == LogicalKey.enter && widget.items.isNotEmpty) {
      final item = widget.items[_selected.clamp(0, widget.items.length - 1)];
      if (item.enabled) item.onSelected();
      return item.enabled;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          color: TuiTheme.of(context).surface,
          border: BoxBorder.all(
            color: TuiTheme.of(context).outline,
            style: BoxBorderStyle.rounded,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < widget.items.length; index++)
              _menuRow(widget.items[index], index),
          ],
        ),
      ),
    );
  }

  Widget _menuRow(MenuItem item, int index) {
    final selected = index == _selected;
    final style = TextStyle(
      color: item.enabled ? null : Colors.grey,
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
    );
    Widget row = Row(
      children: [
        SizedBox(width: 2, child: Text(item.checked ? '✓' : ' ')),
        Expanded(
          child: TerminalText.safe(
            item.label,
            style: style,
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (item.shortcut != null)
          TerminalText.safe(
            item.shortcut!,
            style: const TextStyle(color: Colors.grey),
            softWrap: false,
            maxLines: 1,
          ),
        const SizedBox(width: 1),
      ],
    );
    if (selected) {
      row = Container(color: const Color.fromRGB(43, 49, 67), child: row);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: item.enabled
          ? () {
              setState(() => _selected = index);
              item.onSelected();
            }
          : null,
      child: row,
    );
  }
}

class MenuBarItem {
  const MenuBarItem({required this.label, required this.items});

  final String label;
  final List<MenuItem> items;
}

/// A horizontal application menu bar.
class MenuBar extends StatefulWidget {
  const MenuBar({super.key, required this.menus, this.autofocus = false});

  final List<MenuBarItem> menus;
  final bool autofocus;

  @override
  State<MenuBar> createState() => _MenuBarState();
}

class _MenuBarState extends State<MenuBar> {
  int _selected = 0;
  bool _open = false;

  bool _key(KeyboardEvent event) {
    if (widget.menus.isEmpty) return false;
    if (event.logicalKey == LogicalKey.arrowRight) {
      setState(() => _selected = (_selected + 1) % widget.menus.length);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowLeft) {
      setState(
        () => _selected =
            (_selected - 1 + widget.menus.length) % widget.menus.length,
      );
      return true;
    }
    if (event.logicalKey == LogicalKey.enter ||
        event.logicalKey == LogicalKey.arrowDown) {
      setState(() => _open = true);
      return true;
    }
    if (event.logicalKey == LogicalKey.escape) {
      setState(() => _open = false);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bar = Row(
      children: [
        for (var index = 0; index < widget.menus.length; index++)
          GestureDetector(
            onTap: () => setState(() {
              _selected = index;
              _open = !_open;
            }),
            child: Container(
              color: index == _selected
                  ? const Color.fromRGB(43, 49, 67)
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: TerminalText.safe(widget.menus[index].label),
            ),
          ),
      ],
    );
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          bar,
          if (_open && widget.menus.isNotEmpty)
            Positioned(
              left: 0,
              top: 1,
              child: ContextMenu(
                items: widget.menus[_selected].items,
                onDismiss: () => setState(() => _open = false),
              ),
            ),
        ],
      ),
    );
  }
}

class DropdownMenuItem<T> {
  const DropdownMenuItem({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

/// A compact single-selection dropdown.
class DropdownMenu<T> extends StatefulWidget {
  const DropdownMenu({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.width = 32,
    this.placeholder = 'Select…',
    this.autofocus = false,
  });

  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T> onChanged;
  final double width;
  final String placeholder;
  final bool autofocus;

  @override
  State<DropdownMenu<T>> createState() => _DropdownMenuState<T>();
}

class _DropdownMenuState<T> extends State<DropdownMenu<T>> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    DropdownMenuItem<T>? selected;
    for (final item in widget.items) {
      if (item.value == widget.value) {
        selected = item;
        break;
      }
    }
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          border: BoxBorder.all(color: TuiTheme.of(context).outline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Row(
          children: [
            Expanded(
              child: TerminalText.safe(
                selected?.label ?? widget.placeholder,
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(_open ? '▴' : '▾'),
          ],
        ),
      ),
    );
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.escape && _open) {
          setState(() => _open = false);
          return true;
        }
        if (event.logicalKey == LogicalKey.enter) {
          setState(() => _open = !_open);
          return true;
        }
        return false;
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          if (_open)
            Positioned(
              left: 0,
              top: 1,
              width: widget.width,
              child: ContextMenu(
                items: [
                  for (final item in widget.items)
                    MenuItem(
                      id: item,
                      label: item.label,
                      enabled: item.enabled,
                      checked: item.value == widget.value,
                      onSelected: () {
                        widget.onChanged(item.value);
                        setState(() => _open = false);
                      },
                    ),
                ],
                onDismiss: () => setState(() => _open = false),
              ),
            ),
        ],
      ),
    );
  }
}

enum ToastSeverity { info, success, warning, error }

class ToastMessage {
  const ToastMessage({
    required this.id,
    required this.message,
    this.title,
    this.severity = ToastSeverity.info,
  });

  final Object id;
  final String message;
  final String? title;
  final ToastSeverity severity;
}

class ToastController extends ChangeNotifier {
  final List<ToastMessage> _messages = [];
  List<ToastMessage> get messages => List.unmodifiable(_messages);

  void show(ToastMessage message) {
    _messages.removeWhere((item) => item.id == message.id);
    _messages.add(message);
    notifyListeners();
  }

  void dismiss(Object id) {
    final before = _messages.length;
    _messages.removeWhere((item) => item.id == id);
    if (_messages.length != before) notifyListeners();
  }

  void clear() {
    if (_messages.isEmpty) return;
    _messages.clear();
    notifyListeners();
  }
}

/// Renders transient toast messages controlled by [ToastController].
class Toast extends StatefulWidget {
  const Toast({
    super.key,
    required this.controller,
    this.maxVisible = 3,
    this.width = 44,
  });

  final ToastController controller;
  final int maxVisible;
  final double width;

  @override
  State<Toast> createState() => _ToastState();
}

class _ToastState extends State<Toast> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(Toast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Color _color(ToastSeverity severity) {
    switch (severity) {
      case ToastSeverity.info:
        return Colors.cyan;
      case ToastSeverity.success:
        return Colors.green;
      case ToastSeverity.warning:
        return Colors.yellow;
      case ToastSeverity.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.controller.messages;
    final start = all.length > widget.maxVisible
        ? all.length - widget.maxVisible
        : 0;
    final visible = all.sublist(start);
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final message in visible)
            Container(
              margin: const EdgeInsets.only(bottom: 1),
              decoration: BoxDecoration(
                color: TuiTheme.of(context).surface,
                border: BoxBorder.all(
                  color: _color(message.severity),
                  style: BoxBorderStyle.rounded,
                ),
                title: message.title == null
                    ? null
                    : BorderTitle(text: ' ${message.title} '),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Row(
                children: [
                  Expanded(child: TerminalText.safe(message.message)),
                  GestureDetector(
                    onTap: () => widget.controller.dismiss(message.id),
                    child: const Text('×'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    this.timestamp,
    this.read = false,
    this.severity = ToastSeverity.info,
  });

  final Object id;
  final String title;
  final String message;
  final DateTime? timestamp;
  final bool read;
  final ToastSeverity severity;

  NotificationItem copyWith({bool? read}) => NotificationItem(
    id: id,
    title: title,
    message: message,
    timestamp: timestamp,
    read: read ?? this.read,
    severity: severity,
  );
}

class NotificationCenterController extends ChangeNotifier {
  NotificationCenterController([
    Iterable<NotificationItem> notifications = const [],
  ]) : _notifications = List.of(notifications);

  final List<NotificationItem> _notifications;
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((item) => !item.read).length;

  void add(NotificationItem item) {
    _notifications.removeWhere((existing) => existing.id == item.id);
    _notifications.insert(0, item);
    notifyListeners();
  }

  void markRead(Object id, [bool read = true]) {
    final index = _notifications.indexWhere((item) => item.id == id);
    if (index < 0 || _notifications[index].read == read) return;
    _notifications[index] = _notifications[index].copyWith(read: read);
    notifyListeners();
  }

  void remove(Object id) {
    final before = _notifications.length;
    _notifications.removeWhere((item) => item.id == id);
    if (_notifications.length != before) notifyListeners();
  }

  void clear() {
    if (_notifications.isEmpty) return;
    _notifications.clear();
    notifyListeners();
  }
}

/// A virtualized notification inbox.
class NotificationCenter extends StatefulWidget {
  const NotificationCenter({
    super.key,
    required this.controller,
    this.emptyMessage = 'No notifications',
    this.onSelected,
  });

  final NotificationCenterController controller;
  final String emptyMessage;
  final ValueChanged<NotificationItem>? onSelected;

  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(NotificationCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.controller.notifications;
    if (items.isEmpty) {
      return Center(child: TerminalText.safe(widget.emptyMessage));
    }
    return VirtualListView.builder(
      itemCount: items.length,
      itemExtent: 3,
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.controller.markRead(item.id);
            widget.onSelected?.call(item);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    item.read ? ' ' : '●',
                    style: const TextStyle(color: Colors.cyan),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: TerminalText.safe(
                      item.title,
                      style: TextStyle(
                        fontWeight: item.read
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.timestamp != null)
                    TerminalText.safe(
                      item.timestamp!.toIso8601String(),
                      style: const TextStyle(color: Colors.grey),
                      softWrap: false,
                    ),
                ],
              ),
              TerminalText.safe(
                item.message,
                style: const TextStyle(color: Colors.grey),
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
