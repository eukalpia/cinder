import { readFile } from 'node:fs/promises';
import path from 'node:path';

export async function readCinderVersion(repositoryRoot) {
  const pubspec = await readFile(path.join(repositoryRoot, 'pubspec.yaml'), 'utf8');
  const version = pubspec.match(/^version:\s*([^\s#]+)\s*$/m)?.[1];
  if (!version) throw new Error('Unable to read the Cinder version from pubspec.yaml.');
  return version;
}
