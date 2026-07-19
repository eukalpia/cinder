import { access, readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptFile = fileURLToPath(import.meta.url);
const siteRoot = path.resolve(path.dirname(scriptFile), '..');
const outRoot = path.join(siteRoot, 'out');
const manifestPath = path.join(siteRoot, 'src', 'generated', 'examples.json');
const basePath = normalizeBasePath(process.env.NEXT_PUBLIC_BASE_PATH ?? '');

const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const failures = [];
const required = [
  'index.html',
  'docs/index.html',
  'examples/index.html',
  'api/index.html',
  'robots.txt',
  'sitemap.xml',
  'site.webmanifest',
  'og-cinder.svg',
  '.nojekyll',
];

for (const route of required) {
  await requireFile(route);
}

const slugs = new Set();
for (const example of manifest.examples) {
  if (slugs.has(example.slug)) failures.push(`Duplicate example slug: ${example.slug}`);
  slugs.add(example.slug);

  await requireFile(`examples/${example.slug}/index.html`);
  await requireFile(`play/${example.slug}/index.html`);
  await requireFile(stripBasePath(example.sourcePath));

  if (example.runnable) {
    if (!example.bundle) failures.push(`Runnable example has no bundle: ${example.slug}`);
    else await requireFile(stripBasePath(example.bundle));
  }

  if (!example.runnable && !example.reason) {
    failures.push(`Non-runnable example has no compatibility reason: ${example.slug}`);
  }
}

const htmlFiles = (await walk(outRoot)).filter((file) => file.endsWith('.html'));
for (const file of htmlFiles) {
  const source = await readFile(file, 'utf8');
  const relative = path.relative(outRoot, file);
  const isGeneratedDartdoc =
    relative === 'api/index.html' || relative.startsWith(`api${path.sep}`);

  // Dartdoc intentionally emits empty anchor targets for its client-side router.
  // The Cinder/Next pages must still reject empty navigational attributes.
  if (!isGeneratedDartdoc && /\b(?:href|src)=["']\s*["']/.test(source)) {
    failures.push(`Empty href/src in ${relative}`);
  }
  if (/cdn\.jsdelivr\.net\/npm\/.+@latest/i.test(source)) {
    failures.push(`Unpinned latest CDN dependency in ${relative}`);
  }
  if (/\bNocterm\b/.test(source)) {
    failures.push(`Stale Nocterm branding in ${relative}`);
  }
  if (/Lorem ipsum|placeholder text/i.test(source)) {
    failures.push(`Placeholder content in ${relative}`);
  }
}

if (failures.length > 0) {
  console.error('Static export verification failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exitCode = 1;
} else {
  console.log(
    `Verified ${htmlFiles.length} HTML files and ${manifest.examples.length} example routes.`,
  );
}

async function requireFile(relative) {
  try {
    await access(path.join(outRoot, relative));
  } catch {
    failures.push(`Missing exported file: ${relative}`);
  }
}

function stripBasePath(value) {
  const normalized = value.replace(/^\/+/, '');
  const base = basePath.replace(/^\/+/, '');
  if (!base) return normalized;
  return normalized === base
    ? ''
    : normalized.startsWith(`${base}/`)
      ? normalized.slice(base.length + 1)
      : normalized;
}

function normalizeBasePath(value) {
  if (!value || value === '/') return '';
  return `/${value.replace(/^\/+|\/+$/g, '')}`;
}

async function walk(root) {
  const output = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const absolute = path.join(root, entry.name);
    if (entry.isDirectory()) output.push(...(await walk(absolute)));
    else output.push(absolute);
  }
  return output;
}
