import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readCinderVersion } from './version.mjs';

const scriptFile = fileURLToPath(import.meta.url);
const siteRoot = path.resolve(path.dirname(scriptFile), '..');
const repositoryRoot = path.resolve(siteRoot, '..');
const version = await readCinderVersion(repositoryRoot);

const targets = [
  path.join(siteRoot, 'src', 'generated', 'examples.json'),
  path.join(siteRoot, 'public', 'generated', 'examples', 'manifest.json'),
];

for (const target of targets) {
  const manifest = JSON.parse(await readFile(target, 'utf8'));
  manifest.version = version;
  await writeFile(target, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
}

console.log(`Synchronized Cinder site metadata to ${version}.`);
