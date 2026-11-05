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
              DataColumn<_RowData>(label: 'Name', width: 16, value: _name),
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

  test(
    'row values line up under their headers and never run together',
    () async {
      await testCinder('data table alignment', (tester) async {
        await tester.pumpWidget(
          SizedBox(
            width: 40,
            height: 6,
            child: VirtualizedDataTable<_RowData>(
              rows: const <_RowData>[_RowData('ABCDEFGH', 12345)],
              columns: const <DataColumn<_RowData>>[
                DataColumn<_RowData>(label: 'Name', width: 8, value: _name),
                DataColumn<_RowData>(
                  label: 'Value',
                  width: 5,
                  numeric: true,
                  value: _value,
                ),
              ],
            ),
          ),
        );
        final lines = tester.terminalState.getText().split('\n');
        final header = lines.firstWhere((l) => l.contains('Name'));
        final row = lines.firstWhere((l) => l.contains('ABCDEFGH'));
        expect(row, isNot(contains('ABCDEFGH12345')));
        expect(row.indexOf('ABCDEFGH'), header.indexOf('Name'));
        expect(row.indexOf('12345'), header.indexOf('Value'));
      });
    },
  );
}

Object? _name(_RowData row) => row.name;
Object? _value(_RowData row) => row.value;
