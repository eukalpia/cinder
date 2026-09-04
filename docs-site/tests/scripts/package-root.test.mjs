import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { findPackageRoot } from '../../scripts/package-root.mjs';

const repositoryRoot = path.resolve('..');

test('uses the standalone Dart example package inside the Flutter host', async () => {
  const exampleRoot = path.join(repositoryRoot, 'packages/cinder_web/example');
  assert.equal(
    await findPackageRoot(path.join(exampleRoot, 'lib/main.dart'), repositoryRoot),
    exampleRoot,
  );
});

test('uses a library package for an example without its own pubspec', async () => {
  const packageRoot = path.join(repositoryRoot, 'packages/cinder_riverpod');
  assert.equal(
    await findPackageRoot(path.join(packageRoot, 'example/counter_watch_demo.dart'), repositoryRoot),
    packageRoot,
  );
});

test('uses the repository package for root examples', async () => {
  assert.equal(
    await findPackageRoot(path.join(repositoryRoot, 'example/web_showcase.dart'), repositoryRoot),
    repositoryRoot,
  );
});
