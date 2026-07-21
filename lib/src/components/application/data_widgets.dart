import 'package:cinder/cinder.dart';

/// Describes one column in a [DataTable] or [VirtualDataGrid].
class DataColumn<T> {
  const DataColumn({
    required this.id,
    required this.label,
    required this.valueBuilder,
    this.width,
    this.alignment = TextAlign.left,
    this.comparator,
  });

  final Object id;
  final String label;
  final String Function(T row) valueBuilder;
  final double? width;
  final TextAlign alignment;
  final int Function(T a, T b)? comparator;
}

/// A small, non-virtualized data table.
class DataTable<T> extends StatelessWidget {
  const DataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.selectedIndex,
    this.onRowSelected,
    this.showHeader = true,
    this.showDividers = true,
    this.selectedColor,
  });

  final List<DataColumn<T>> columns;
  final List<T> rows;
  final int? selectedIndex;
  final ValueChanged<int>? onRowSelected;
  final bool showHeader;
  final bool showDividers;
  final Color? selectedColor;

  Widget _cell(DataColumn<T> column, String value, {bool header = false}) {
    final child = TerminalText.safe(
      value,
      style: TextStyle(
        color: header ? Colors.cyan : null,
        fontWeight: header ? FontWeight.bold : FontWeight.normal,
      ),
      textAlign: column.alignment,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final width = column.width;
    return width == null
        ? Expanded(child: child)
        : SizedBox(width: width, child: child);
  }

  Widget _row(T row, int index) {
    Widget child = Row(
      children: [
        for (final column in columns) _cell(column, column.valueBuilder(row)),
      ],
    );
    if (selectedIndex == index) {
      child = Container(
        color: selectedColor ?? const Color.fromRGB(43, 49, 67),
        child: child,
      );
    }
    if (onRowSelected != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onRowSelected!(index),
        child: child,
      );
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              for (final column in columns)
                _cell(column, column.label, header: true),
            ],
          ),
          if (showDividers) const Divider(),
        ],
        for (var index = 0; index < rows.length; index++) ...[
          _row(rows[index], index),
          if (showDividers && index < rows.length - 1) const Divider(),
        ],
      ],
    );
  }
}

/// Virtualized data grid for large row sets.
class VirtualDataGrid<T> extends StatefulWidget {
  const VirtualDataGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.controller,
    this.selectedIndex,
    this.onRowSelected,
    this.rowExtent = 1,
    this.cacheExtent = 5,
    this.autofocus = false,
    this.selectedColor,
    this.showHeader = true,
    this.showDividers = true,
  }) : assert(rowExtent > 0);

  final List<DataColumn<T>> columns;
  final List<T> rows;
  final ScrollController? controller;
  final int? selectedIndex;
  final ValueChanged<int>? onRowSelected;
  final double rowExtent;
  final double cacheExtent;
  final bool autofocus;
  final Color? selectedColor;
  final bool showHeader;
  final bool showDividers;

  @override
  State<VirtualDataGrid<T>> createState() => _VirtualDataGridState<T>();
}

class _VirtualDataGridState<T> extends State<VirtualDataGrid<T>> {
  ScrollController? _owned;
  late ScrollController _controller;
  int _keyboardIndex = 0;

  @override
  void initState() {
    super.initState();
    _owned = widget.controller == null ? ScrollController() : null;
    _controller = widget.controller ?? _owned!;
    _keyboardIndex = widget.selectedIndex ?? 0;
  }

  @override
  void didUpdateWidget(VirtualDataGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _owned?.dispose();
      _owned = widget.controller == null ? ScrollController() : null;
      _controller = widget.controller ?? _owned!;
    }
    if (widget.selectedIndex != null) {
      _keyboardIndex = widget.selectedIndex!;
    }
  }

  Widget _cell(DataColumn<T> column, String value, {bool header = false}) {
    final child = TerminalText.safe(
      value,
      style: TextStyle(
        color: header ? Colors.cyan : null,
        fontWeight: header ? FontWeight.bold : FontWeight.normal,
      ),
      textAlign: column.alignment,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return column.width == null
        ? Expanded(child: child)
        : SizedBox(width: column.width, child: child);
  }

  bool _key(KeyboardEvent event) {
    if (widget.rows.isEmpty) return false;
    if (event.logicalKey == LogicalKey.arrowDown) {
      _select((_keyboardIndex + 1).clamp(0, widget.rows.length - 1));
      return true;
    }
    if (event.logicalKey == LogicalKey.arrowUp) {
      _select((_keyboardIndex - 1).clamp(0, widget.rows.length - 1));
      return true;
    }
    if (event.logicalKey == LogicalKey.home) {
      _select(0);
      return true;
    }
    if (event.logicalKey == LogicalKey.end) {
      _select(widget.rows.length - 1);
      return true;
    }
    if (event.logicalKey == LogicalKey.enter) {
      widget.onRowSelected?.call(_keyboardIndex);
      return true;
    }
    return false;
  }

  void _select(int index) {
    _keyboardIndex = index;
    _controller.ensureIndexVisible(index: index);
    widget.onRowSelected?.call(index);
    if (widget.selectedIndex == null && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSelected = widget.selectedIndex ?? _keyboardIndex;
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader) ...[
            Row(
              children: [
                for (final column in widget.columns)
                  _cell(column, column.label, header: true),
              ],
            ),
            if (widget.showDividers) const Divider(),
          ],
          Expanded(
            child: VirtualListView.builder(
              controller: _controller,
              itemCount: widget.rows.length,
              itemExtent: widget.rowExtent,
              cacheExtent: widget.cacheExtent,
              itemBuilder: (context, index) {
                final row = widget.rows[index];
                Widget child = Row(
                  children: [
                    for (final column in widget.columns)
                      _cell(column, column.valueBuilder(row)),
                  ],
                );
                if (effectiveSelected == index) {
                  child = Container(
                    color:
                        widget.selectedColor ?? const Color.fromRGB(43, 49, 67),
                    child: child,
                  );
                }
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _select(index),
                  child: child,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }
}

/// A virtual grid with clickable sortable headers.
class SortableTable<T> extends StatefulWidget {
  const SortableTable({
    super.key,
    required this.columns,
    required this.rows,
    this.initialSortColumn,
    this.initialAscending = true,
    this.selectedIndex,
    this.onRowSelected,
  });

  final List<DataColumn<T>> columns;
  final List<T> rows;
  final Object? initialSortColumn;
  final bool initialAscending;
  final int? selectedIndex;
  final ValueChanged<int>? onRowSelected;

  @override
  State<SortableTable<T>> createState() => _SortableTableState<T>();
}

class _SortableTableState<T> extends State<SortableTable<T>> {
  Object? _sortColumn;
  late bool _ascending;

  @override
  void initState() {
    super.initState();
    _sortColumn = widget.initialSortColumn;
    _ascending = widget.initialAscending;
  }

  void _sortBy(DataColumn<T> column) {
    if (column.comparator == null) return;
    setState(() {
      if (_sortColumn == column.id) {
        _ascending = !_ascending;
      } else {
        _sortColumn = column.id;
        _ascending = true;
      }
    });
  }

  List<T> _sortedRows() {
    final rows = List<T>.of(widget.rows);
    DataColumn<T>? column;
    for (final candidate in widget.columns) {
      if (candidate.id == _sortColumn) {
        column = candidate;
        break;
      }
    }
    final comparator = column?.comparator;
    if (comparator != null) {
      rows.sort((a, b) => _ascending ? comparator(a, b) : comparator(b, a));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final columns = [
      for (final column in widget.columns)
        DataColumn<T>(
          id: column.id,
          label: column.comparator == null
              ? column.label
              : '${column.label}${_sortColumn == column.id ? (_ascending ? ' ↑' : ' ↓') : ''}',
          width: column.width,
          alignment: column.alignment,
          valueBuilder: column.valueBuilder,
          comparator: column.comparator,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final column in columns)
              _SortableHeader<T>(
                column: column,
                onSelected: () => _sortBy(column),
              ),
          ],
        ),
        const Divider(),
        Expanded(
          child: VirtualDataGrid<T>(
            columns: [
              for (final column in columns)
                DataColumn<T>(
                  id: column.id,
                  label: '',
                  valueBuilder: column.valueBuilder,
                  width: column.width,
                  alignment: column.alignment,
                ),
            ],
            rows: _sortedRows(),
            selectedIndex: widget.selectedIndex,
            onRowSelected: widget.onRowSelected,
            showHeader: false,
            showDividers: false,
          ),
        ),
      ],
    );
  }
}

class _SortableHeader<T> extends StatelessWidget {
  const _SortableHeader({required this.column, required this.onSelected});

  final DataColumn<T> column;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: column.comparator == null ? null : onSelected,
      child: TerminalText.safe(
        column.label,
        style: const TextStyle(color: Colors.cyan, fontWeight: FontWeight.bold),
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return column.width == null
        ? Expanded(child: child)
        : SizedBox(width: column.width, child: child);
  }
}

/// A searchable/filterable virtual table.
class FilterableTable<T> extends StatefulWidget {
  const FilterableTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.matches,
    this.placeholder = 'Filter…',
    this.selectedIndex,
    this.onRowSelected,
  });

  final List<DataColumn<T>> columns;
  final List<T> rows;
  final bool Function(T row, String query) matches;
  final String placeholder;
  final int? selectedIndex;
  final ValueChanged<int>? onRowSelected;

  @override
  State<FilterableTable<T>> createState() => _FilterableTableState<T>();
}

class _FilterableTableState<T> extends State<FilterableTable<T>> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    final rows = query.isEmpty
        ? widget.rows
        : widget.rows.where((row) => widget.matches(row, query)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          placeholder: widget.placeholder,
          onChanged: (value) => setState(() => _query = value),
        ),
        const Divider(),
        Expanded(
          child: VirtualDataGrid<T>(
            columns: widget.columns,
            rows: rows,
            selectedIndex: widget.selectedIndex,
            onRowSelected: widget.onRowSelected,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class PropertyEntry {
  const PropertyEntry({
    required this.name,
    required this.value,
    this.description,
    this.editable = false,
    this.onChanged,
  });

  final String name;
  final String value;
  final String? description;
  final bool editable;
  final ValueChanged<String>? onChanged;
}

/// Name/value editor used by inspectors and IDE sidebars.
class PropertyInspector extends StatelessWidget {
  const PropertyInspector({
    super.key,
    required this.properties,
    this.nameWidth = 24,
    this.emptyMessage = 'No properties',
  });

  final List<PropertyEntry> properties;
  final double nameWidth;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (properties.isEmpty) {
      return Center(child: TerminalText.safe(emptyMessage));
    }
    return VirtualListView.builder(
      itemCount: properties.length,
      itemExtent: 2,
      itemBuilder: (context, index) {
        final property = properties[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: nameWidth,
                  child: TerminalText.safe(
                    property.name,
                    style: const TextStyle(color: Colors.cyan),
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Text(' '),
                Expanded(
                  child: property.editable && property.onChanged != null
                      ? _EditablePropertyValue(
                          value: property.value,
                          onChanged: property.onChanged!,
                        )
                      : TerminalText.safe(
                          property.value,
                          softWrap: false,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ],
            ),
            const Divider(),
          ],
        );
      },
    );
  }
}

class _EditablePropertyValue extends StatefulWidget {
  const _EditablePropertyValue({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_EditablePropertyValue> createState() => _EditablePropertyValueState();
}

class _EditablePropertyValueState extends State<_EditablePropertyValue> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_EditablePropertyValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(controller: _controller, onChanged: widget.onChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class TimelineEntry {
  const TimelineEntry({
    required this.id,
    required this.title,
    this.description,
    this.timestamp,
    this.statusMarker = '●',
    this.color,
  });

  final Object id;
  final String title;
  final String? description;
  final DateTime? timestamp;
  final String statusMarker;
  final Color? color;
}

/// Virtualized chronological event timeline.
class Timeline extends StatelessWidget {
  const Timeline({
    super.key,
    required this.entries,
    this.onSelected,
    this.reverse = false,
  });

  final List<TimelineEntry> entries;
  final ValueChanged<TimelineEntry>? onSelected;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    return VirtualListView.builder(
      itemCount: entries.length,
      itemExtent: 3,
      reverse: reverse,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelected == null ? null : () => onSelected!(entry),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 3,
                child: Column(
                  children: [
                    Text(
                      entry.statusMarker,
                      style: TextStyle(color: entry.color ?? Colors.cyan),
                    ),
                    const Text('│', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TerminalText.safe(
                            entry.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            softWrap: false,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.timestamp != null)
                          TerminalText.safe(
                            entry.timestamp!.toIso8601String(),
                            style: const TextStyle(color: Colors.grey),
                            softWrap: false,
                          ),
                      ],
                    ),
                    TerminalText.safe(
                      entry.description ?? '',
                      style: const TextStyle(color: Colors.grey),
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum LogLevel { trace, debug, info, warning, error, fatal }

class LogViewEntry {
  const LogViewEntry({
    required this.message,
    this.level = LogLevel.info,
    this.timestamp,
    this.source,
  });

  final String message;
  final LogLevel level;
  final DateTime? timestamp;
  final String? source;
}

class LogViewController extends ChangeNotifier {
  LogViewController({this.maxEntries = 10000});

  final int maxEntries;
  final List<LogViewEntry> _entries = [];
  List<LogViewEntry> get entries => List.unmodifiable(_entries);

  void add(LogViewEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    notifyListeners();
  }

  void addAll(Iterable<LogViewEntry> entries) {
    _entries.addAll(entries);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }
}

/// High-volume, sanitized log viewer.
class LogView extends StatefulWidget {
  const LogView({
    super.key,
    required this.controller,
    this.followTail = true,
    this.showTimestamp = true,
    this.showSource = true,
  });

  final LogViewController controller;
  final bool followTail;
  final bool showTimestamp;
  final bool showSource;

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(LogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (widget.followTail && widget.controller.entries.isNotEmpty) {
      _scroll.ensureIndexVisible(index: widget.controller.entries.length - 1);
    }
    if (mounted) setState(() {});
  }

  Color _color(LogLevel level) {
    switch (level) {
      case LogLevel.trace:
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.info:
        return Colors.cyan;
      case LogLevel.warning:
        return Colors.yellow;
      case LogLevel.error:
      case LogLevel.fatal:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.entries;
    return VirtualListView.builder(
      controller: _scroll,
      itemCount: entries.length,
      itemExtent: 1,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Row(
          children: [
            if (widget.showTimestamp && entry.timestamp != null) ...[
              TerminalText.safe(
                entry.timestamp!.toIso8601String(),
                style: const TextStyle(color: Colors.grey),
                softWrap: false,
              ),
              const Text(' '),
            ],
            SizedBox(
              width: 7,
              child: Text(
                entry.level.name.toUpperCase(),
                style: TextStyle(color: _color(entry.level)),
                softWrap: false,
              ),
            ),
            if (widget.showSource && entry.source != null) ...[
              TerminalText.safe(
                '[${entry.source}]',
                style: const TextStyle(color: Colors.grey),
                softWrap: false,
              ),
              const Text(' '),
            ],
            Expanded(
              child: TerminalText.safe(
                entry.message,
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }
}

/// Search box plus a virtualized generic result list.
class SearchableList<T> extends StatefulWidget {
  const SearchableList({
    super.key,
    required this.items,
    required this.searchText,
    required this.itemBuilder,
    this.placeholder = 'Search…',
    this.emptyMessage = 'No results',
    this.itemExtent,
  });

  final List<T> items;
  final String Function(T item) searchText;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String placeholder;
  final String emptyMessage;
  final double? itemExtent;

  @override
  State<SearchableList<T>> createState() => _SearchableListState<T>();
}

class _SearchableListState<T> extends State<SearchableList<T>> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final items = query.isEmpty
        ? widget.items
        : widget.items
              .where(
                (item) => widget.searchText(item).toLowerCase().contains(query),
              )
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          placeholder: widget.placeholder,
          onChanged: (value) => setState(() => _query = value),
        ),
        const Divider(),
        Expanded(
          child: items.isEmpty
              ? Center(child: TerminalText.safe(widget.emptyMessage))
              : VirtualListView.builder(
                  itemCount: items.length,
                  itemExtent: widget.itemExtent,
                  itemBuilder: (context, index) =>
                      widget.itemBuilder(context, items[index], index),
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Convenience facade for an unbounded builder-backed list.
class InfiniteList extends StatelessWidget {
  const InfiniteList({
    super.key,
    required this.itemBuilder,
    this.controller,
    this.itemExtent,
    this.reverse = false,
    this.cacheExtent = 5,
  });

  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final double? itemExtent;
  final bool reverse;
  final double cacheExtent;

  @override
  Widget build(BuildContext context) {
    return VirtualListView.infinite(
      controller: controller,
      itemBuilder: itemBuilder,
      itemExtent: itemExtent,
      reverse: reverse,
      cacheExtent: cacheExtent,
    );
  }
}
