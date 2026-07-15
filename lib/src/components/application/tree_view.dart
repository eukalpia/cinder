import 'package:cinder/cinder.dart';

/// Immutable data node for [TreeView].
class TreeNode<T> {
  const TreeNode({
    required this.id,
    required this.label,
    this.value,
    this.children = const [],
    this.disabled = false,
    this.leading,
  });

  final Object id;
  final String label;
  final T? value;
  final List<TreeNode<T>> children;
  final bool disabled;
  final Widget? leading;

  bool get isLeaf => children.isEmpty;
}

/// Flattened visible tree entry passed to custom builders.
class TreeViewEntry<T> {
  const TreeViewEntry({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.selected,
    required this.parentId,
  });

  final TreeNode<T> node;
  final int depth;
  final bool expanded;
  final bool selected;
  final Object? parentId;
}

typedef TreeViewItemBuilder<T> =
    Widget Function(BuildContext context, TreeViewEntry<T> entry);

class TreeViewController<T> extends ChangeNotifier {
  TreeViewController({
    Iterable<Object> expandedIds = const [],
    Object? selectedId,
  }) : _expandedIds = Set<Object>.of(expandedIds),
       _selectedId = selectedId;

  final Set<Object> _expandedIds;
  Object? _selectedId;

  Set<Object> get expandedIds => Set<Object>.unmodifiable(_expandedIds);
  Object? get selectedId => _selectedId;

  bool isExpanded(Object id) => _expandedIds.contains(id);

  void setExpanded(Object id, bool expanded) {
    final changed = expanded ? _expandedIds.add(id) : _expandedIds.remove(id);
    if (changed) notifyListeners();
  }

  void toggle(Object id) => setExpanded(id, !isExpanded(id));

  void select(Object? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  void expandAll(Iterable<TreeNode<T>> roots) {
    void visit(TreeNode<T> node) {
      if (node.children.isNotEmpty) _expandedIds.add(node.id);
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final root in roots) {
      visit(root);
    }
    notifyListeners();
  }

  void collapseAll() {
    if (_expandedIds.isEmpty) return;
    _expandedIds.clear();
    notifyListeners();
  }
}

/// A virtualized, keyboard-first expandable tree.
class TreeView<T> extends StatefulWidget {
  const TreeView({
    super.key,
    required this.nodes,
    this.controller,
    this.itemBuilder,
    this.onSelected,
    this.onActivated,
    this.indent = 2,
    this.cacheExtent = 8,
    this.autofocus = false,
    this.showRootLines = false,
    this.selectedColor,
    this.textStyle,
  }) : assert(indent >= 0),
       assert(cacheExtent >= 0);

  final List<TreeNode<T>> nodes;
  final TreeViewController<T>? controller;
  final TreeViewItemBuilder<T>? itemBuilder;
  final ValueChanged<TreeNode<T>>? onSelected;
  final ValueChanged<TreeNode<T>>? onActivated;
  final int indent;
  final double cacheExtent;
  final bool autofocus;
  final bool showRootLines;
  final Color? selectedColor;
  final TextStyle? textStyle;

  @override
  State<TreeView<T>> createState() => _TreeViewState<T>();
}

class _TreeViewState<T> extends State<TreeView<T>> {
  TreeViewController<T>? _ownedController;
  late TreeViewController<T> _controller;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _attachController();
  }

  void _attachController() {
    _ownedController = widget.controller == null
        ? TreeViewController<T>()
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
  void didUpdateWidget(TreeView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      _detachController();
      _attachController();
    }
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  List<TreeViewEntry<T>> _flatten() {
    final entries = <TreeViewEntry<T>>[];

    void visit(TreeNode<T> node, int depth, Object? parentId) {
      final expanded = _controller.isExpanded(node.id);
      entries.add(
        TreeViewEntry<T>(
          node: node,
          depth: depth,
          expanded: expanded,
          selected: _controller.selectedId == node.id,
          parentId: parentId,
        ),
      );
      if (!expanded) return;
      for (final child in node.children) {
        visit(child, depth + 1, node.id);
      }
    }

    for (final node in widget.nodes) {
      visit(node, 0, null);
    }
    return entries;
  }

  void _selectEntry(List<TreeViewEntry<T>> entries, int index) {
    if (entries.isEmpty) return;
    final target = entries[index.clamp(0, entries.length - 1)];
    if (target.node.disabled) return;
    _controller.select(target.node.id);
    widget.onSelected?.call(target.node);
    _scrollController.ensureIndexVisible(index: index);
  }

  bool _handleKeyEvent(KeyboardEvent event) {
    final entries = _flatten();
    if (entries.isEmpty) return false;
    var index = entries.indexWhere((entry) => entry.selected);
    if (index < 0) index = 0;
    final current = entries[index];

    if (event.logicalKey == LogicalKey.arrowDown) {
      _selectEntry(entries, index + 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _selectEntry(entries, index - 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.home) {
      _selectEntry(entries, 0);
      return true;
    }
    if (event.logicalKey == LogicalKey.end) {
      _selectEntry(entries, entries.length - 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowRight) {
      if (current.node.children.isNotEmpty && !current.expanded) {
        _controller.setExpanded(current.node.id, true);
      } else if (index + 1 < entries.length &&
          entries[index + 1].parentId == current.node.id) {
        _selectEntry(entries, index + 1);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowLeft) {
      if (current.expanded) {
        _controller.setExpanded(current.node.id, false);
      } else if (current.parentId != null) {
        final parentIndex = entries.indexWhere(
          (entry) => entry.node.id == current.parentId,
        );
        if (parentIndex >= 0) _selectEntry(entries, parentIndex);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      widget.onActivated?.call(current.node);
      return true;
    }
    if (event.logicalKey == LogicalKey.space) {
      if (current.node.children.isNotEmpty) {
        _controller.toggle(current.node.id);
      }
      return true;
    }
    return false;
  }

  Widget _defaultItem(BuildContext context, TreeViewEntry<T> entry) {
    final node = entry.node;
    final marker = node.children.isEmpty
        ? '  '
        : (entry.expanded ? '▾ ' : '▸ ');
    final guide = widget.showRootLines && entry.depth > 0
        ? '${'│ ' * (entry.depth - 1)}├ '
        : ' ' * (entry.depth * widget.indent);
    final prefix = '$guide$marker';
    final baseStyle = widget.textStyle ?? const TextStyle();
    final style = node.disabled
        ? baseStyle.copyWith(color: Colors.grey, fontWeight: FontWeight.dim)
        : baseStyle;

    Widget content = Row(
      children: [
        Text(prefix, style: style, softWrap: false),
        if (node.leading != null) ...[node.leading!, const Text(' ')],
        Expanded(
          child: TerminalText.safe(
            node.label,
            style: style,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );

    if (entry.selected) {
      content = Container(
        color: widget.selectedColor ?? const Color.fromRGB(45, 55, 75),
        child: content,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (node.disabled) return;
        _controller.select(node.id);
        widget.onSelected?.call(node);
      },
      onDoubleTap: () {
        if (node.disabled) return;
        if (node.children.isNotEmpty) _controller.toggle(node.id);
        widget.onActivated?.call(node);
      },
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _flatten();
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: VirtualListView.builder(
        controller: _scrollController,
        itemExtent: 1,
        cacheExtent: widget.cacheExtent,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return widget.itemBuilder?.call(context, entry) ??
              _defaultItem(context, entry);
        },
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
