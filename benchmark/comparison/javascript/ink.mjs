import {readFileSync} from 'node:fs';
import React, {useState} from 'react';
import {Box, Text, render, useApp, useInput} from 'ink';

if (process.argv.length !== 3) {
  throw new Error('Usage: node ink.mjs <workload.json>');
}

const {width, height, fps, frames} = JSON.parse(readFileSync(process.argv[2], 'utf8'));
if (
  !Number.isInteger(width) || width < 1 ||
  !Number.isInteger(height) || height < 1 ||
  !Number.isFinite(fps) || fps <= 0 ||
  !Array.isArray(frames) || frames.length !== 2 ||
  !frames.every(frame => typeof frame === 'string' &&
    frame.split('\n').length === height &&
    frame.split('\n').every(row => row.length === width && /^[\x20-\x7e]+$/.test(row)))
) {
  throw new Error('Workload must contain two printable ASCII grids matching width and height, and a positive fps.');
}
if (!process.stdin.isTTY || !process.stdout.isTTY ||
    process.stdout.columns !== width || process.stdout.rows !== height) {
  throw new Error(`Expected a ${width}x${height} PTY for stdin and stdout.`);
}

function App() {
  const [counter, setCounter] = useState(0);
  const {exit} = useApp();

  useInput(input => {
    if (input === 'q') {
      exit();
    } else if (input === 'n') {
      setCounter(current => current + 1);
    }
  });

  return React.createElement(
    Box,
    {width, height},
    React.createElement(Text, null, frames[counter % 2]),
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
