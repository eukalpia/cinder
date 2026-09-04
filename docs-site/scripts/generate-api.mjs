import { execFileSync } from 'node:child_process';
import { rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = path.resolve(siteRoot, '..');
const output = path.join(siteRoot, 'public', 'api');

await rm(output, { recursive: true, force: true });
execFileSync('dart', ['doc', '--output', output], {
  cwd: repositoryRoot,
  stdio: 'inherit',
});
