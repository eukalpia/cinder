import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

class _RowData {
  const _RowData(this.name, this.value);
  final String name;
  final int value;
}

void main() {
  test('VirtualizedDataTable renders rows and navigates selection', () async {
    _RowData? selected;
    await testCinder('virtualized data table', (tester) async {
      await tester.pumpWidget(
        SizedBox(
          width: 40,
          height: 8,
          child: VirtualizedDataTable<_RowData>(
            autofocus: true,
            rows: const <_RowData>[
              _RowData('Alpha', 30),
              _RowData('Beta', 10),
              _RowData('Gamma', 20),
            ],
            columns: const <DataColumn<_RowData>>[
              DataColumn<_RowData>(
                label: 'Name',
                width: 16,
                value: _name,
              ),
              DataColumn<_RowData>(
                label: 'Value',
                width: 10,
                numeric: true,
                value: _value,
              ),
            ],
            onSelectionChanged: (row) => selected = row,
          ),
        ),
      );
      expect(tester.terminalState, containsText('Alpha'));
      await tester.sendKey(LogicalKey.arrowDown);
      expect(selected?.name, 'Alpha');
      await tester.sendKey(LogicalKey.arrowDown);
      expect(selected?.name, 'Beta');
    });
  });
}

Object? _name(_RowData row) => row.name;
Object? _value(_RowData row) => row.value;
