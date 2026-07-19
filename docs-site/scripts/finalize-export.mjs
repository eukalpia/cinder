import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptFile = fileURLToPath(import.meta.url);
const siteRoot = path.resolve(path.dirname(scriptFile), '..');
const outRoot = path.join(siteRoot, 'out');

await mkdir(outRoot, { recursive: true });
await writeFile(path.join(outRoot, '.nojekyll'), '\n', 'utf8');

console.log('Finalized static export for GitHub Pages.');
