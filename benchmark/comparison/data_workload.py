"""Shared input specification and independent screen oracle for workspace-v1.

Adapters receive records and keys, never expected screens. All model actions and
viewport formatting happen inside their application process after real input.
"""
import argparse
import json
from pathlib import Path

ACTIONS = tuple('jpjxfspejxsfeGakgaxpksfg')
LABELS = dict(j='down', k='up', p='page', g='home', G='end', x='select',
              f='search', e='errors', s='sort', a='append')


def record(index):
    return {'id': index, 'service': f'service-{index % 17:02}',
            'level': ['INFO', 'WARN', 'ERROR', 'DEBUG'][index % 4],
            'score': index * 37 % 10000,
            'message': f'request {index:06} ' + ('needle' if index % 97 == 0 else 'regular')}


def workload(width=120, height=40, fps=60, count=50000):
    if width < 100 or height < 12 or count < 1 or not 1 <= fps <= 120:
        raise ValueError('workspace-v1 requires width >= 100, height >= 12, records >= 1, fps 1..120')
    return {'kind': 'workspace-v1', 'name': f'workspace-{count}',
            'width': width, 'height': height, 'fps': fps,
            'records': [record(index) for index in range(count)],
            'actions': list(ACTIONS)}


class Workspace:
    def __init__(self, spec):
        self.width, self.height = spec['width'], spec['height']
        self.page_size = self.height - 8
        self.records = list(spec['records'])
        self.matches = list(self.records)
        self.selected = set()
        self.cursor = self.top = self.step = 0
        self.query = ''
        self.errors = False
        self.order = 'id'
        self.logs = ['ready']

    def rebuild(self):
        self.matches = [row for row in self.records
                        if (not self.errors or row['level'] == 'ERROR') and
                        self.query in (row['service'] + ' ' + row['level'] + ' ' + row['message']).lower()]
        if self.order != 'id':
            sign = -1 if self.order == 'score-desc' else 1
            self.matches.sort(key=lambda row: (sign * row['score'], row['id']))
        self.cursor = self.top = 0

    def apply(self, key):
        if key not in LABELS:
            return False
        self.step += 1
        if key == 'j':
            self.cursor += 1
        elif key == 'k':
            self.cursor -= 1
        elif key == 'p':
            self.cursor += self.page_size
        elif key == 'g':
            self.cursor = 0
        elif key == 'G':
            self.cursor = len(self.matches) - 1
        elif key == 'x' and self.matches:
            identifier = self.matches[self.cursor]['id']
            if identifier in self.selected:
                self.selected.remove(identifier)
            else:
                self.selected.add(identifier)
        elif key == 'f':
            self.query = '' if self.query else 'needle'
            self.rebuild()
        elif key == 'e':
            self.errors = not self.errors
            self.rebuild()
        elif key == 's':
            self.order = 'score-asc' if self.order == 'score-desc' else 'score-desc'
            self.rebuild()
        elif key == 'a':
            self.records.append(record(len(self.records)))
            self.rebuild()
        self.cursor = max(0, min(self.cursor, len(self.matches) - 1))
        if self.cursor < self.top:
            self.top = self.cursor
        if self.cursor >= self.top + self.page_size:
            self.top = self.cursor - self.page_size + 1
        self.logs.append(f'{self.step:06} {LABELS[key]} cursor={self.cursor} matches={len(self.matches)}')
        self.logs = self.logs[-3:]
        return True

    def lines(self):
        rows = [f'Workspace step={self.step:06} rows={len(self.records)} matches={len(self.matches)} selected={len(self.selected)}',
                f'query={self.query or "-"} errors={int(self.errors)} sort={self.order} cursor={self.cursor} top={self.top}',
                '   ID     SERVICE    LEVEL SCORE MESSAGE']
        for offset in range(self.page_size):
            index = self.top + offset
            if index >= len(self.matches):
                rows.append('')
                continue
            row = self.matches[index]
            cursor = '>' if index == self.cursor else ' '
            selected = '*' if row['id'] in self.selected else ' '
            rows.append(f'{cursor}{selected} {row["id"]:06} {row["service"]} {row["level"]:<5} {row["score"]:04} {row["message"]}')
        rows.extend(['Event log'] + [''] * (3 - len(self.logs)) + self.logs)
        rows.append('j/k move  p page  g/G home/end  x select  f search  e errors  s sort  a append  q quit')
        return [row[:self.width].ljust(self.width) for row in rows]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--records', type=int, default=50000)
    args = parser.parse_args()
    args.output.write_text(json.dumps(workload(count=args.records)) + '\n')
