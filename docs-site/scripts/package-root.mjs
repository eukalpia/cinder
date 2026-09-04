import { access } from 'node:fs/promises';
import path from 'node:path';

export async function findPackageRoot(sourceFile, repositoryRoot) {
  let directory = path.dirname(sourceFile);
  while (directory !== repositoryRoot) {
    try {
      await access(path.join(directory, 'pubspec.yaml'));
      return directory;
    } catch {
      const parent = path.dirname(directory);
      if (parent === directory) break;
      directory = parent;
    }
  }
  return repositoryRoot;
}
