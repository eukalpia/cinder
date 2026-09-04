import {readFileSync} from 'node:fs';
import {createCliRenderer, TextRenderable} from '@opentui/core';

if (process.argv.length !== 3) {
  throw new Error('Usage: bun opentui.ts <workload.json>');
}

const {width, height, fps, frames} = JSON.parse(readFileSync(process.argv[2], 'utf8'));
if (
  !Number.isInteger(width) || width < 1 ||
  !Number.isInteger(height) || height < 1 ||
  !Number.isFinite(fps) || fps <= 0 ||
  !Array.isArray(frames) || frames.length !== 2 ||
  !frames.every((frame: unknown) => typeof frame === 'string' &&
    frame.split('\n').length === height &&
    frame.split('\n').every(row => row.length === width && /^[\x20-\x7e]+$/.test(row)))
) {
  throw new Error('Workload must contain two printable ASCII grids matching width and height, and a positive fps.');
}
if (!process.stdin.isTTY || !process.stdout.isTTY ||
    process.stdout.columns !== width || process.stdout.rows !== height) {
  throw new Error(`Expected a ${width}x${height} PTY for stdin and stdout.`);
}

const renderer = await createCliRenderer({
  stdin: process.stdin,
  stdout: process.stdout,
  width,
  height,
  targetFps: fps,
  maxFps: fps,
  screenMode: 'alternate-screen',
  consoleMode: 'disabled',
  openConsoleOnError: false,
  gatherStats: false,
  memorySnapshotInterval: 0,
  useMouse: false,
  enableMouseMovement: false,
  exitOnCtrlC: false,
  useKittyKeyboard: {
    disambiguate: false,
    alternateKeys: false,
    events: false,
    allKeysAsEscapes: false,
    reportText: false,
  },
});

const text = new TextRenderable(renderer, {
  id: 'grid',
  width,
  height,
  wrapMode: 'none',
  content: frames[0],
});
renderer.root.add(text);

let counter = 0;
renderer.keyInput.on('keypress', key => {
  if (key.name === 'q') {
    renderer.destroy();
  } else if (key.name === 'n') {
    counter += 1;
    text.content = frames[counter % 2];
  }
});
