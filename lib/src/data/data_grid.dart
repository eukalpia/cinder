import 'package:cinder/cinder.dart';

class DataColumn {
  const DataColumn(this.label, {this.width, this.align = TextAlign.left});

  final String label;
  final int? width;
  final TextAlign align;
}

class DataGrid extends StatelessWidget {
  const DataGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.showHeader = true,
    this.rowNumbers = false,
    this.maxColumnWidth = 32,
  });

  final List<DataColumn> columns;
  final List<List<Object?>> rows;
  final bool showHeader;
  final bool rowNumbers;
  final int maxColumnWidth;

  @override
  Widget build(BuildContext context) => Text(render());

  String render() {
    final effectiveColumns = rowNumbers
        ? <DataColumn>[const DataColumn('#'), ...columns]
        : columns;
    final effectiveRows = <List<String>>[
      if (showHeader) effectiveColumns.map((column) => column.label).toList(),
      for (var index = 0; index < rows.length; index++)
        <String>[
          if (rowNumbers) '${index + 1}',
          ...rows[index].map((value) => value?.toString() ?? ''),
        ],
    ];
    final widths = List<int>.generate(effectiveColumns.length, (column) {
      final configured = effectiveColumns[column].width;
      if (configured != null) return configured;
      var width = effectiveColumns[column].label.length;
      for (final row in effectiveRows) {
        if (column < row.length && row[column].length > width) {
          width = row[column].length;
        }
      }
      return width.clamp(1, maxColumnWidth);
    });

    String border(String left, String middle, String right) =>
        '$left${widths.map((width) => '─' * (width + 2)).join(middle)}$right';

    String line(List<String> row) =>
        '│${List<String>.generate(widths.length, (index) {
          final text = index < row.length ? row[index] : '';
          final clipped = text.length > widths[index] ? '${text.substring(0, widths[index] - 1)}…' : text;
          return ' ${clipped.padRight(widths[index])} ';
        }).join('│')}│';

    final output = <String>[border('┌', '┬', '┐')];
    for (var index = 0; index < effectiveRows.length; index++) {
      output.add(line(effectiveRows[index]));
      if (showHeader && index == 0) {
        output.add(border('├', '┼', '┤'));
      }
    }
    output.add(border('└', '┴', '┘'));
    return output.join('\n');
  }
}
