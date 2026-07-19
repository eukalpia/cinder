import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import { createServer } from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptFile = fileURLToPath(import.meta.url);
const siteRoot = path.resolve(path.dirname(scriptFile), '..');
const outRoot = path.join(siteRoot, 'out');
const port = Number.parseInt(process.env.PORT ?? '4173', 10);
const basePath = normalizeBasePath(process.env.NEXT_PUBLIC_BASE_PATH ?? '/cinder');

const mimeTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.map', 'application/json; charset=utf-8'],
  ['.png', 'image/png'],
  ['.svg', 'image/svg+xml'],
  ['.txt', 'text/plain; charset=utf-8'],
  ['.webmanifest', 'application/manifest+json; charset=utf-8'],
  ['.woff2', 'font/woff2'],
]);

const server = createServer(async (request, response) => {
  try {
    const requestUrl = new URL(request.url ?? '/', `http://${request.headers.host}`);
    const pathname = decodeURIComponent(requestUrl.pathname);

    if (pathname === '/') {
      response.writeHead(302, { Location: `${basePath}/` });
      response.end();
      return;
    }

    if (basePath && pathname !== basePath && !pathname.startsWith(`${basePath}/`)) {
      respondNotFound(response);
      return;
    }

    const relativeUrl = basePath ? pathname.slice(basePath.length) : pathname;
    const requested = relativeUrl.replace(/^\/+/, '');
    const safePath = path.normalize(requested).replace(/^(\.\.(\/|\\|$))+/, '');
    let filePath = path.join(outRoot, safePath);
    const resolvedRoot = `${path.resolve(outRoot)}${path.sep}`;
    const resolvedFile = path.resolve(filePath);

    if (resolvedFile !== path.resolve(outRoot) && !`${resolvedFile}${path.sep}`.startsWith(resolvedRoot)) {
      respondNotFound(response);
      return;
    }

    let fileStats = await stat(filePath).catch(() => null);
    if (fileStats?.isDirectory()) {
      filePath = path.join(filePath, 'index.html');
      fileStats = await stat(filePath).catch(() => null);
    }

    if (!fileStats?.isFile()) {
      respondNotFound(response);
      return;
    }

    response.writeHead(200, {
      'Cache-Control': 'no-store',
      'Content-Type': mimeTypes.get(path.extname(filePath)) ?? 'application/octet-stream',
    });
    createReadStream(filePath).pipe(response);
  } catch (error) {
    response.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end(error instanceof Error ? error.message : String(error));
  }
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Serving ${outRoot} at http://127.0.0.1:${port}${basePath}/`);
});

function normalizeBasePath(value) {
  if (!value || value === '/') return '';
  return `/${value.replace(/^\/+|\/+$/g, '')}`;
}

function respondNotFound(response) {
  response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  response.end('Not found');
}
