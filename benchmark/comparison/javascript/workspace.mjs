// Port of the documented workspace-v1 model; no precomputed screen states.
const labels = {j:'down', k:'up', p:'page', g:'home', G:'end', x:'select', f:'search', e:'errors', s:'sort', a:'append'};
const pad = (value, width) => String(value).padStart(width, '0');
function record(id) {
  return {id, service:`service-${pad(id % 17, 2)}`, level:['INFO','WARN','ERROR','DEBUG'][id % 4],
    score:id * 37 % 10000, message:`request ${pad(id, 6)} ${id % 97 === 0 ? 'needle' : 'regular'}`};
}
export class Workspace {
  constructor(spec) {
    this.width = spec.width; this.height = spec.height; this.pageSize = spec.height - 8;
    this.records = [...spec.records]; this.matches = [...this.records]; this.selected = new Set();
    this.cursor = 0; this.top = 0; this.step = 0; this.query = ''; this.errors = false;
    this.order = 'id'; this.logs = ['ready'];
  }
  rebuild() {
    this.matches = this.records.filter(row => (!this.errors || row.level === 'ERROR') &&
      `${row.service} ${row.level} ${row.message}`.toLowerCase().includes(this.query));
    if (this.order !== 'id') {
      const sign = this.order === 'score-desc' ? -1 : 1;
      this.matches.sort((a,b) => sign * (a.score - b.score) || a.id - b.id);
    }
    this.cursor = this.top = 0;
  }
  apply(key) {
    if (!Object.hasOwn(labels, key)) return false;
    this.step++;
    switch (key) {
      case 'j': this.cursor++; break;
      case 'k': this.cursor--; break;
      case 'p': this.cursor += this.pageSize; break;
      case 'g': this.cursor = 0; break;
      case 'G': this.cursor = this.matches.length - 1; break;
      case 'x': if (this.matches.length) {
        const id = this.matches[this.cursor].id;
        if (this.selected.has(id)) this.selected.delete(id); else this.selected.add(id);
      } break;
      case 'f': this.query = this.query ? '' : 'needle'; this.rebuild(); break;
      case 'e': this.errors = !this.errors; this.rebuild(); break;
      case 's': this.order = this.order === 'score-desc' ? 'score-asc' : 'score-desc'; this.rebuild(); break;
      case 'a': this.records.push(record(this.records.length)); this.rebuild(); break;
    }
    this.cursor = Math.max(0, Math.min(this.cursor, this.matches.length - 1));
    if (this.cursor < this.top) this.top = this.cursor;
    if (this.cursor >= this.top + this.pageSize) this.top = this.cursor - this.pageSize + 1;
    this.logs.push(`${pad(this.step,6)} ${labels[key]} cursor=${this.cursor} matches=${this.matches.length}`);
    this.logs = this.logs.slice(-3);
    return true;
  }
  text() {
    const rows = [`Workspace step=${pad(this.step,6)} rows=${this.records.length} matches=${this.matches.length} selected=${this.selected.size}`,
      `query=${this.query || '-'} errors=${Number(this.errors)} sort=${this.order} cursor=${this.cursor} top=${this.top}`,
      '   ID     SERVICE    LEVEL SCORE MESSAGE'];
    for (let offset = 0; offset < this.pageSize; offset++) {
      const index = this.top + offset, row = this.matches[index];
      rows.push(row ? `${index === this.cursor ? '>' : ' '}${this.selected.has(row.id) ? '*' : ' '} ${pad(row.id,6)} ${row.service} ${row.level.padEnd(5)} ${pad(row.score,4)} ${row.message}` : '');
    }
    rows.push('Event log', ...Array(3 - this.logs.length).fill(''), ...this.logs,
      'j/k move  p page  g/G home/end  x select  f search  e errors  s sort  a append  q quit');
    return rows.map(row => row.slice(0,this.width).padEnd(this.width)).join('\n');
  }
}
