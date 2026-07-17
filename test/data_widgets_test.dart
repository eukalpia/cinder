import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('data grid renders headers and rows', () {
    final grid = DataGrid(
      columns: const <DataColumn>[DataColumn('Name'), DataColumn('Score')],
      rows: const <List<Object?>>[
        <Object?>['Ada', 10],
      ],
      rowNumbers: true,
    );

    expect(grid.render(), contains('Ada'));
    expect(grid.render(), contains('Score'));
  });

  test('sparkline renders one glyph per value', () {
    expect(const Sparkline(<num>[1, 2, 3]).render().runes.length, 3);
  });
}
