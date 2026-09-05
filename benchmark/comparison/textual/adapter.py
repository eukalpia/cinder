"""Textual's normal App / Static update path, for both comparison suites."""
import json
import os
from pathlib import Path
import sys

spec = json.loads(Path(sys.argv[1]).read_text())
# Textual's documented environment setting is read at import time.
os.environ['TEXTUAL_FPS'] = str(spec['fps'])

from textual.app import App, ComposeResult
from textual.widgets import Static
from rich.text import Text

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from data_workload import Workspace


class Comparison(App):
    CSS = '''
    Screen { background: black; color: white; }
    Static { width: 100%; height: 100%; padding: 0; margin: 0; overflow: hidden hidden; }
    '''
    ENABLE_COMMAND_PALETTE = False
    BINDINGS = []

    def __init__(self):
        super().__init__()
        self.model = Workspace(spec) if spec.get('kind') == 'workspace-v1' else None
        self.counter = 0

    def content(self):
        value = '\n'.join(self.model.lines()) if self.model else spec['frames'][self.counter % 2]
        return Text(value, no_wrap=True, overflow='crop')

    def compose(self) -> ComposeResult:
        yield Static(self.content(), markup=False, expand=False, shrink=False)

    def on_key(self, event):
        key = event.character
        if key == 'q':
            self.exit()
        elif (self.model is not None and self.model.apply(key)) or (self.model is None and key == 'n'):
            self.counter += 1
            self.query_one(Static).update(self.content())


Comparison().run(mouse=False)
