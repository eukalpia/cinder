use serde::Deserialize;
use std::collections::HashSet;

#[derive(Clone, Deserialize)]
pub struct Record {
    pub id: usize,
    pub service: String,
    pub level: String,
    pub score: usize,
    pub message: String,
}

pub struct Workspace {
    width: usize,
    page_size: usize,
    records: Vec<Record>,
    matches: Vec<usize>,
    selected: HashSet<usize>,
    cursor: usize,
    top: usize,
    step: usize,
    query: String,
    errors: bool,
    order: &'static str,
    logs: Vec<String>,
}

impl Workspace {
    pub fn new(width: usize, height: usize, records: Vec<Record>) -> Self {
        Self {
            width,
            page_size: height - 8,
            matches: (0..records.len()).collect(),
            records,
            selected: HashSet::new(),
            cursor: 0,
            top: 0,
            step: 0,
            query: String::new(),
            errors: false,
            order: "id",
            logs: vec!["ready".into()],
        }
    }

    fn rebuild(&mut self) {
        self.matches = self
            .records
            .iter()
            .enumerate()
            .filter(|(_, row)| {
                (!self.errors || row.level == "ERROR")
                    && format!("{} {} {}", row.service, row.level, row.message)
                        .to_lowercase()
                        .contains(&self.query)
            })
            .map(|(index, _)| index)
            .collect();
        if self.order != "id" {
            let rows = &self.records;
            self.matches.sort_by(|a, b| {
                let order = rows[*a].score.cmp(&rows[*b].score);
                let order = if self.order == "score-desc" {
                    order.reverse()
                } else {
                    order
                };
                order.then(rows[*a].id.cmp(&rows[*b].id))
            });
        }
        self.cursor = 0;
        self.top = 0;
    }

    pub fn apply(&mut self, key: char) -> bool {
        let label = match key {
            'j' => "down",
            'k' => "up",
            'p' => "page",
            'g' => "home",
            'G' => "end",
            'x' => "select",
            'f' => "search",
            'e' => "errors",
            's' => "sort",
            'a' => "append",
            _ => return false,
        };
        self.step += 1;
        match key {
            'j' => self.cursor += 1,
            'k' => self.cursor = self.cursor.saturating_sub(1),
            'p' => self.cursor += self.page_size,
            'g' => self.cursor = 0,
            'G' => self.cursor = self.matches.len().saturating_sub(1),
            'x' if !self.matches.is_empty() => {
                let id = self.records[self.matches[self.cursor]].id;
                if !self.selected.remove(&id) {
                    self.selected.insert(id);
                }
            }
            'f' => {
                self.query = if self.query.is_empty() {
                    "needle".into()
                } else {
                    String::new()
                };
                self.rebuild();
            }
            'e' => {
                self.errors = !self.errors;
                self.rebuild();
            }
            's' => {
                self.order = if self.order == "score-desc" {
                    "score-asc"
                } else {
                    "score-desc"
                };
                self.rebuild();
            }
            'a' => {
                let id = self.records.len();
                self.records.push(Record {
                    id,
                    service: format!("service-{:02}", id % 17),
                    level: ["INFO", "WARN", "ERROR", "DEBUG"][id % 4].into(),
                    score: id * 37 % 10000,
                    message: format!(
                        "request {id:06} {}",
                        if id % 97 == 0 { "needle" } else { "regular" }
                    ),
                });
                self.rebuild();
            }
            _ => {}
        }
        self.cursor = self.cursor.min(self.matches.len().saturating_sub(1));
        if self.cursor < self.top {
            self.top = self.cursor;
        }
        if self.cursor >= self.top + self.page_size {
            self.top = self.cursor - self.page_size + 1;
        }
        self.logs.push(format!(
            "{:06} {label} cursor={} matches={}",
            self.step,
            self.cursor,
            self.matches.len()
        ));
        if self.logs.len() > 3 {
            self.logs.remove(0);
        }
        true
    }

    pub fn text(&self) -> String {
        let mut lines = vec![
            format!(
                "Workspace step={:06} rows={} matches={} selected={}",
                self.step,
                self.records.len(),
                self.matches.len(),
                self.selected.len()
            ),
            format!(
                "query={} errors={} sort={} cursor={} top={}",
                if self.query.is_empty() {
                    "-"
                } else {
                    &self.query
                },
                usize::from(self.errors),
                self.order,
                self.cursor,
                self.top
            ),
            "   ID     SERVICE    LEVEL SCORE MESSAGE".into(),
        ];
        for index in self.top..self.top + self.page_size {
            if let Some(&row_index) = self.matches.get(index) {
                let row = &self.records[row_index];
                lines.push(format!(
                    "{}{} {:06} {} {:<5} {:04} {}",
                    if index == self.cursor { '>' } else { ' ' },
                    if self.selected.contains(&row.id) {
                        '*'
                    } else {
                        ' '
                    },
                    row.id,
                    row.service,
                    row.level,
                    row.score,
                    row.message
                ));
            } else {
                lines.push(String::new());
            }
        }
        lines.push("Event log".into());
        for _ in self.logs.len()..3 {
            lines.push(String::new());
        }
        lines.extend(self.logs.iter().cloned());
        lines.push("j/k move  p page  g/G home/end  x select  f search  e errors  s sort  a append  q quit".into());
        lines
            .into_iter()
            .map(|line| {
                format!(
                    "{:<width$}",
                    &line[..line.len().min(self.width)],
                    width = self.width
                )
            })
            .collect::<Vec<_>>()
            .join("\n")
    }
}
