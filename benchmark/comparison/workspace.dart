/// The workspace-v1 application model. Only the visible rows are formatted.
class Workspace {
  Workspace(Map<String, dynamic> spec)
    : width = spec['width'] as int,
      height = spec['height'] as int,
      records = (spec['records'] as List).cast<Map<String, dynamic>>() {
    matches = List.of(records);
  }

  final int width, height;
  final List<Map<String, dynamic>> records;
  late List<Map<String, dynamic>> matches;
  final selected = <int>{};
  int cursor = 0, top = 0, step = 0;
  String query = '', order = 'id';
  bool errors = false;
  List<String> logs = ['ready'];
  int get pageSize => height - 8;
  static const labels = {
    'j': 'down',
    'k': 'up',
    'p': 'page',
    'g': 'home',
    'G': 'end',
    'x': 'select',
    'f': 'search',
    'e': 'errors',
    's': 'sort',
    'a': 'append',
  };
  String pad(int value, int width) => '$value'.padLeft(width, '0');

  void rebuild() {
    matches = records
        .where(
          (row) =>
              (!errors || row['level'] == 'ERROR') &&
              '${row['service']} ${row['level']} ${row['message']}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    if (order != 'id') {
      final sign = order == 'score-desc' ? -1 : 1;
      matches.sort((a, b) {
        final score = sign * (a['score'] as int).compareTo(b['score'] as int);
        return score == 0 ? (a['id'] as int).compareTo(b['id'] as int) : score;
      });
    }
    cursor = top = 0;
  }

  bool apply(String key) {
    if (!labels.containsKey(key)) return false;
    step++;
    switch (key) {
      case 'j':
        cursor++;
      case 'k':
        cursor--;
      case 'p':
        cursor += pageSize;
      case 'g':
        cursor = 0;
      case 'G':
        cursor = matches.length - 1;
      case 'x':
        if (matches.isNotEmpty) {
          final id = matches[cursor]['id'] as int;
          if (!selected.remove(id)) selected.add(id);
        }
      case 'f':
        query = query.isEmpty ? 'needle' : '';
        rebuild();
      case 'e':
        errors = !errors;
        rebuild();
      case 's':
        order = order == 'score-desc' ? 'score-asc' : 'score-desc';
        rebuild();
      case 'a':
        final id = records.length;
        records.add({
          'id': id,
          'service': 'service-${pad(id % 17, 2)}',
          'level': ['INFO', 'WARN', 'ERROR', 'DEBUG'][id % 4],
          'score': id * 37 % 10000,
          'message':
              'request ${pad(id, 6)} ${id % 97 == 0 ? 'needle' : 'regular'}',
        });
        rebuild();
    }
    cursor = cursor.clamp(0, matches.isEmpty ? 0 : matches.length - 1);
    if (cursor < top) top = cursor;
    if (cursor >= top + pageSize) top = cursor - pageSize + 1;
    logs.add(
      '${pad(step, 6)} ${labels[key]} cursor=$cursor matches=${matches.length}',
    );
    if (logs.length > 3) logs.removeAt(0);
    return true;
  }

  String text() {
    final rows = [
      'Workspace step=${pad(step, 6)} rows=${records.length} matches=${matches.length} selected=${selected.length}',
      'query=${query.isEmpty ? '-' : query} errors=${errors ? 1 : 0} sort=$order cursor=$cursor top=$top',
      '   ID     SERVICE    LEVEL SCORE MESSAGE',
    ];
    for (var offset = 0; offset < pageSize; offset++) {
      final index = top + offset;
      if (index >= matches.length) {
        rows.add('');
        continue;
      }
      final row = matches[index];
      rows.add(
        '${index == cursor ? '>' : ' '}${selected.contains(row['id']) ? '*' : ' '} '
        '${pad(row['id'] as int, 6)} ${row['service']} ${(row['level'] as String).padRight(5)} '
        '${pad(row['score'] as int, 4)} ${row['message']}',
      );
    }
    rows.addAll([
      'Event log',
      ...List.filled(3 - logs.length, ''),
      ...logs,
      'j/k move  p page  g/G home/end  x select  f search  e errors  s sort  a append  q quit',
    ]);
    return rows
        .map(
          (row) => row.length > width
              ? row.substring(0, width)
              : row.padRight(width),
        )
        .join('\n');
  }
}
