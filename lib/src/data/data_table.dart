import '../components/basic.dart';
import '../components/controls.dart';
import '../components/focus.dart';
import '../components/gesture_detector.dart';
import '../components/list_view.dart';
import '../foundation/widget_state.dart';
import '../framework/framework.dart';
import '../keyboard/keyboard_event.dart';
import '../keyboard/logical_key.dart';
import '../style.dart';
import '../theme/tui_theme.dart';

/// Sort direction used by [VirtualizedDataTable].
enum DataSortDirection { ascending, descending }

/// Defines one typed column in a virtualized data table.
class DataColumn<T> {
  const DataColumn({
    required this.label,
    required this.value,
    this.width = 16,
    this.numeric = false,
    this.sort,
    this.format,
  }) : assert(width > 0);

  final String label;
  final Object? Function(T row) value;
  final int width;
  final bool numeric;
  final int Function(T a, T b)? sort;
  final String Function(Object? value)? format;

  String displayValue(T row) {
    final raw = value(row);
    return format?.call(raw) ?? raw?.toString() ?? '';
  }

  int compare(T a, T b) {
    final custom = sort;
    if (custom != null) return custom(a, b);
    final left = value(a);
    final right = value(b);
    if (left == null && right == null) return 0;
    if (left == null) return -1;
    if (right == null) return 1;
    if (left is Comparable && right.runtimeType == left.runtimeType) {
      return left.compareTo(right);
    }
    return left.toString().compareTo(right.toString());
  }
}

/// A table that builds only visible rows and supports keyboard navigation.
class VirtualizedDataTable<T> extends StatefulWidget {
  const VirtualizedDataTable({
    super.key,
    required this.rows,
    required this.columns,
    this.rowKey,
    this.onRowActivated,
    this.onSelectionChanged,
    this.initialSortColumn,
    this.initialSortDirection = DataSortDirection.ascending,
    this.showHeader = true,
    this.keyboardNavigation = true,
    this.autofocus = false,
    this.emptyMessage = 'No rows',
    this.cacheExtent = 8,
  });

  final List<T> rows;
  final List<DataColumn<T>> columns;
  final Object Function(T row)? rowKey;
  final void Function(T row)? onRowActivated;
  final void Function(T? row)? onSelectionChanged;
  final int? initialSortColumn;
  final DataSortDirection initialSortDirection;
  final bool showHeader;
  final bool keyboardNavigation;
  final bool autofocus;
  final String emptyMessage;
  final double cacheExtent;

  @override
  State<VirtualizedDataTable<T>> createState() =>
      _VirtualizedDataTableState<T>();
}

class _VirtualizedDataTableState<T> extends State<VirtualizedDataTable<T>> {
  late List<T> _rows;
  int? _sortColumn;
  late DataSortDirection _sortDirection;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _sortColumn = widget.initialSortColumn;
    _sortDirection = widget.initialSortDirection;
    _rebuildRows(preserveSelection: false);
  }

  @override
  void didUpdateWidget(VirtualizedDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.rows, oldWidget.rows) ||
        !identical(widget.columns, oldWidget.columns)) {
      _rebuildRows(preserveSelection: true);
    }
  }

  Object? _selectedKey() {
    final index = _selectedIndex;
    if (index == null || index < 0 || index >= _rows.length) return null;
    final row = _rows[index];
    return widget.rowKey?.call(row) ?? row;
  }

  void _rebuildRows({required bool preserveSelection}) {
    final key = preserveSelection ? _selectedKey() : null;
    _rows = List<T>.of(widget.rows);
    _applySort();
    if (key != null) {
      final index = _rows.indexWhere(
        (row) => (widget.rowKey?.call(row) ?? row) == key,
      );
      _selectedIndex = index < 0 ? null : index;
    } else if (_rows.isEmpty) {
      _selectedIndex = null;
    }
  }

  void _applySort() {
    final columnIndex = _sortColumn;
    if (columnIndex == null ||
        columnIndex < 0 ||
        columnIndex >= widget.columns.length) {
      return;
    }
    final column = widget.columns[columnIndex];
    _rows.sort((a, b) {
      final result = column.compare(a, b);
      return _sortDirection == DataSortDirection.ascending ? result : -result;
    });
  }

  void _sortBy(int columnIndex) {
    if (columnIndex < 0 || columnIndex >= widget.columns.length) return;
    setState(() {
      if (_sortColumn == columnIndex) {
        _sortDirection = _sortDirection == DataSortDirection.ascending
            ? DataSortDirection.descending
            : DataSortDirection.ascending;
      } else {
        _sortColumn = columnIndex;
        _sortDirection = DataSortDirection.ascending;
      }
      final key = _selectedKey();
      _applySort();
      if (key != null) {
        final index = _rows.indexWhere(
          (row) => (widget.rowKey?.call(row) ?? row) == key,
        );
        _selectedIndex = index < 0 ? null : index;
      }
    });
  }

  void _select(int? index) {
    final next = index == null || _rows.isEmpty
        ? null
        : index.clamp(0, _rows.length - 1);
    if (_selectedIndex == next) return;
    setState(() => _selectedIndex = next);
    widget.onSelectionChanged?.call(next == null ? null : _rows[next]);
  }

  bool _handleKey(KeyboardEvent event) {
    if (!widget.keyboardNavigation || _rows.isEmpty) return false;
    if (event.logicalKey == LogicalKey.arrowDown) {
      _select((_selectedIndex ?? -1) + 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _select((_selectedIndex ?? 1) - 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.home) {
      _select(0);
      return true;
    }
    if (event.logicalKey == LogicalKey.end) {
      _select(_rows.length - 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.enter && _selectedIndex != null) {
      widget.onRowActivated?.call(_rows[_selectedIndex!]);
      return true;
    }
    return false;
  }

  Widget _cell(String value, DataColumn<T> column, TextStyle style) {
    final padded = column.numeric
        ? value.padLeft(column.width)
        : value.padRight(column.width);
    return SizedBox(
      width: column.width.toDouble(),
      child: Text(
        padded,
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: column.numeric ? TextAlign.right : TextAlign.left,
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Row(
      children: <Widget>[
        for (var index = 0; index < widget.columns.length; index++)
          Button(
            onPressed: () => _sortBy(index),
            density: ControlDensity.compact,
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all<Color?>(theme.surface),
              borderColor: WidgetStateProperty.all<Color?>(
                _sortColumn == index ? theme.primary : theme.outlineVariant,
              ),
              padding: EdgeInsets.zero,
            ),
            child: _cell(
              '${widget.columns[index].label}${_sortColumn == index ? (_sortDirection == DataSortDirection.ascending ? ' ↑' : ' ↓') : ''}',
              widget.columns[index],
              TextStyle(
                color: _sortColumn == index ? theme.primary : theme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, int index) {
    final theme = TuiTheme.of(context);
    final selected = index == _selectedIndex;
    final foreground = selected ? theme.onPrimary : theme.onBackground;
    final content = Row(
      children: <Widget>[
        for (final column in widget.columns)
          _cell(
            column.displayValue(_rows[index]),
            column,
            TextStyle(color: foreground),
          ),
      ],
    );
    return GestureDetector(
      onTap: () {
        _select(index);
        widget.onRowActivated?.call(_rows[index]);
      },
      child: Container(color: selected ? theme.primary : null, child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final table = _rows.isEmpty
        ? Center(child: Text(widget.emptyMessage))
        : ListView.builder(
            lazy: true,
            itemExtent: 1,
            cacheExtent: widget.cacheExtent,
            itemCount: _rows.length,
            itemBuilder: _row,
          );
    final content = Column(
      children: <Widget>[
        if (widget.showHeader) _header(context),
        Expanded(child: table),
      ],
    );
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: content,
    );
  }
}
