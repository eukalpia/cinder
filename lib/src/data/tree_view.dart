import '../components/basic.dart';
import '../components/focus.dart';
import '../components/gesture_detector.dart';
import '../components/list_view.dart';
import '../framework/framework.dart';
import '../keyboard/keyboard_event.dart';
import '../keyboard/logical_key.dart';
import '../style.dart';
import '../theme/tui_theme.dart';

/// Immutable node used by [TreeView].
class TreeNode<T> {
  TreeNode({
    required this.id,
    required this.label,
    required this.value,
    List<TreeNode<T>>? children,
    this.icon,
    this.disabled = false,
  }) : children = List<TreeNode<T>>.unmodifiable(children ?? <TreeNode<T>>[]);

  final Object id;
  final String label;
  final T value;
  final List<TreeNode<T>> children;
  final Widget? icon;
  final bool disabled;

  bool get isLeaf => children.isEmpty;
}

class _VisibleTreeNode<T> {
  const _VisibleTreeNode(this.node, this.depth, this.parentId);

  final TreeNode<T> node;
  final int depth;
  final Object? parentId;
}

/// A virtualized, keyboard-navigable hierarchical data view.
class TreeView<T> extends StatefulWidget {
  const TreeView({
    super.key,
    required this.nodes,
    this.initiallyExpanded = const <Object>{},
    this.selectedId,
    this.onSelectionChanged,
    this.onActivated,
    this.indent = 2,
    this.autofocus = false,
    this.cacheExtent = 8,
    this.emptyMessage = 'No items',
  });

  final List<TreeNode<T>> nodes;
  final Set<Object> initiallyExpanded;
  final Object? selectedId;
  final void Function(TreeNode<T>? node)? onSelectionChanged;
  final void Function(TreeNode<T> node)? onActivated;
  final int indent;
  final bool autofocus;
  final double cacheExtent;
  final String emptyMessage;

  @override
  State<TreeView<T>> createState() => _TreeViewState<T>();
}

class _TreeViewState<T> extends State<TreeView<T>> {
  late final Set<Object> _expanded;
  List<_VisibleTreeNode<T>> _visible = <_VisibleTreeNode<T>>[];
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _expanded = <Object>{...widget.initiallyExpanded};
    _rebuildVisible();
  }

  @override
  void didUpdateWidget(TreeView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.nodes, oldWidget.nodes) ||
        widget.selectedId != oldWidget.selectedId) {
      _rebuildVisible();
    }
  }

  void _rebuildVisible() {
    final output = <_VisibleTreeNode<T>>[];
    void append(List<TreeNode<T>> nodes, int depth, Object? parentId) {
      for (final node in nodes) {
        output.add(_VisibleTreeNode<T>(node, depth, parentId));
        if (_expanded.contains(node.id)) {
          append(node.children, depth + 1, node.id);
        }
      }
    }

    append(widget.nodes, 0, null);
    _visible = output;
    final selectedId = widget.selectedId ??
        (_selectedIndex != null && _selectedIndex! < output.length
            ? output[_selectedIndex!].node.id
            : null);
    if (selectedId != null) {
      final index = output.indexWhere((entry) => entry.node.id == selectedId);
      _selectedIndex = index < 0 ? null : index;
    } else if (output.isEmpty) {
      _selectedIndex = null;
    }
  }

  void _select(int? index) {
    if (_visible.isEmpty) return;
    final next = (index ?? 0).clamp(0, _visible.length - 1);
    final entry = _visible[next];
    if (entry.node.disabled) return;
    if (_selectedIndex != next) setState(() => _selectedIndex = next);
    widget.onSelectionChanged?.call(entry.node);
  }

  void _toggle(_VisibleTreeNode<T> entry) {
    if (entry.node.isLeaf) return;
    setState(() {
      if (!_expanded.add(entry.node.id)) _expanded.remove(entry.node.id);
      _rebuildVisible();
    });
  }

  int? _indexOfId(Object? id) {
    if (id == null) return null;
    final index = _visible.indexWhere((entry) => entry.node.id == id);
    return index < 0 ? null : index;
  }

  bool _handleKey(KeyboardEvent event) {
    if (_visible.isEmpty) return false;
    final index = _selectedIndex ?? 0;
    final entry = _visible[index];
    if (event.logicalKey == LogicalKey.arrowDown) {
      _select(index + 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _select(index - 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.home) {
      _select(0);
      return true;
    }
    if (event.logicalKey == LogicalKey.end) {
      _select(_visible.length - 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowRight) {
      if (!entry.node.isLeaf && !_expanded.contains(entry.node.id)) {
        _toggle(entry);
      } else if (!entry.node.isLeaf) {
        _select(index + 1);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowLeft) {
      if (_expanded.contains(entry.node.id)) {
        _toggle(entry);
      } else {
        final parentIndex = _indexOfId(entry.parentId);
        if (parentIndex != null) _select(parentIndex);
      }
      return true;
    }
    if (event.logicalKey == LogicalKey.enter ||
        event.logicalKey == LogicalKey.space) {
      if (!entry.node.isLeaf) _toggle(entry);
      widget.onActivated?.call(entry.node);
      return true;
    }
    return false;
  }

  Widget _row(BuildContext context, int index) {
    final theme = TuiTheme.of(context);
    final entry = _visible[index];
    final selected = index == _selectedIndex;
    final expanded = _expanded.contains(entry.node.id);
    final branch = entry.node.isLeaf
        ? ' '
        : expanded
            ? '▾'
            : '▸';
    final prefix = ' ' * (entry.depth * widget.indent);
    final foreground = entry.node.disabled
        ? theme.outline
        : selected
            ? theme.onPrimary
            : theme.onBackground;
    return GestureDetector(
      onTap: () {
        _select(index);
        if (!entry.node.isLeaf) _toggle(entry);
        widget.onActivated?.call(entry.node);
      },
      child: Container(
        color: selected ? theme.primary : null,
        child: Row(
          children: <Widget>[
            Text('$prefix$branch ', style: TextStyle(color: foreground)),
            if (entry.node.icon != null) entry.node.icon!,
            if (entry.node.icon != null) const SizedBox(width: 1),
            Expanded(
              child: Text(
                entry.node.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: _visible.isEmpty
          ? Center(child: Text(widget.emptyMessage))
          : ListView.builder(
              lazy: true,
              itemExtent: 1,
              cacheExtent: widget.cacheExtent,
              itemCount: _visible.length,
              itemBuilder: _row,
            ),
    );
  }
}
