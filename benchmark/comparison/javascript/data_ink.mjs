import {Workspace} from './workspace.mjs';
import {readFileSync} from 'node:fs';
import React, {useState} from 'react';
import {Box, Text, render, useApp, useInput} from 'ink';

if (process.argv.length !== 3) {
  throw new Error('Usage: node data_ink.mjs <workload.json>');
}

const spec = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const {width, height, fps} = spec;
const model = new Workspace(spec);
if (!process.stdin.isTTY || !process.stdout.isTTY ||
    process.stdout.columns !== width || process.stdout.rows !== height) {
  throw new Error(`Expected a ${width}x${height} PTY for stdin and stdout.`);
}

function App() {
  const [, setRevision] = useState(0);
  const {exit} = useApp();

  useInput(input => {
    let changed = false;
    // Public useInput can combine printable keys into one input string.
    for (const key of input) {
      if (key === 'q') {
        exit();
        return;
      }
      changed = model.apply(key) || changed;
    }
    if (changed) {
      setRevision(current => current + 1);
    }
  });

  return React.createElement(
    Box,
    {width, height},
    React.createElement(Text, null, model.text()),
  );
}

const app = render(React.createElement(App), {
  stdin: process.stdin,
  stdout: process.stdout,
  stderr: process.stderr,
  interactive: true,
  alternateScreen: true,
  incrementalRendering: true,
  maxFps: fps,
  concurrent: false,
  debug: false,
  isScreenReaderEnabled: false,
  patchConsole: false,
  exitOnCtrlC: false,
  kittyKeyboard: {mode: 'disabled'},
});

await app.waitUntilExit();
app.cleanup();
