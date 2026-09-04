import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import test from 'node:test';

for (const basePath of ['', '/cinder']) {
  test(`serves the exported homepage with base path ${basePath || '/'}`, async (t) => {
    const server = spawn(process.execPath, ['scripts/serve-export.mjs'], {
      env: { ...process.env, NEXT_PUBLIC_BASE_PATH: basePath, PORT: '4189' },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    t.after(async () => {
      server.kill();
      await once(server, 'exit');
    });
    await once(server.stdout, 'data');
    const response = await fetch(`http://127.0.0.1:4189${basePath}/`, {
      redirect: 'manual',
    });
    assert.equal(response.status, 200);
    assert.match(await response.text(), /Cinder/);
    if (basePath) {
      const root = await fetch('http://127.0.0.1:4189/', { redirect: 'manual' });
      assert.equal(root.status, 302);
      assert.equal(root.headers.get('location'), `${basePath}/`);
      assert.equal((await fetch('http://127.0.0.1:4189/other/')).status, 404);
    }
  });
}
