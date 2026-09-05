mod workspace;

use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{Terminal, backend::CrosstermBackend, widgets::Paragraph};
use serde::Deserialize;
use std::{
    error::Error,
    fs, io,
    time::{Duration, Instant},
};
use workspace::{Record, Workspace};

#[derive(Deserialize)]
struct Spec {
    width: usize,
    height: usize,
    fps: u32,
    #[serde(default)]
    kind: String,
    #[serde(default)]
    frames: Vec<String>,
    #[serde(default)]
    records: Vec<Record>,
}

fn run(spec: Spec) -> Result<(), Box<dyn Error>> {
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let mut terminal = Terminal::new(CrosstermBackend::new(stdout))?;
    terminal.hide_cursor()?;
    let mut model = (spec.kind == "workspace-v1")
        .then(|| Workspace::new(spec.width, spec.height, spec.records));
    let mut counter = 0;
    let mut next_frame = Instant::now();
    let interval = Duration::from_secs_f64(1.0 / f64::from(spec.fps));
    let result = (|| -> Result<(), Box<dyn Error>> {
        loop {
            // Ratatui delegates pacing to its application. This public draw
            // loop caps changed frames, using the normal Crossterm backend.
            std::thread::sleep(next_frame.saturating_duration_since(Instant::now()));
            next_frame = Instant::now() + interval;
            let value = model
                .as_ref()
                .map_or_else(|| spec.frames[counter % 2].clone(), Workspace::text);
            terminal.draw(|frame| frame.render_widget(Paragraph::new(value), frame.area()))?;
            loop {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press {
                        if let KeyCode::Char(character) = key.code {
                            if character == 'q' {
                                return Ok(());
                            }
                            let changed = if let Some(model) = model.as_mut() {
                                model.apply(character)
                            } else if character == 'n' {
                                counter += 1;
                                true
                            } else {
                                false
                            };
                            if changed {
                                break;
                            }
                        }
                    }
                }
            }
        }
    })();
    terminal.show_cursor()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    disable_raw_mode()?;
    result
}

fn main() -> Result<(), Box<dyn Error>> {
    let path = std::env::args()
        .nth(1)
        .ok_or("usage: ratatui-comparison workload.json")?;
    run(serde_json::from_str(&fs::read_to_string(path)?)?)
}
