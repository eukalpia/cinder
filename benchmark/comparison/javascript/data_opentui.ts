import {Workspace} from './workspace.mjs';
import {readFileSync} from 'node:fs';
import {createCliRenderer, TextRenderable} from '@opentui/core';

if (process.argv.length !== 3) {
  throw new Error('Usage: bun data_opentui.ts <workload.json>');
}

const spec = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const {width, height, fps} = spec;
const model = new Workspace(spec);
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
  content: model.text(),
});
renderer.root.add(text);

renderer.keyInput.on('keypress', key => {
  if (key.name === 'q') {
    renderer.destroy();
  } else if (model.apply(key.sequence)) {
    text.content = model.text();
  }
});
