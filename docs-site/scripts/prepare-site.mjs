import { execFile } from 'node:child_process';
import {
  access,
  copyFile,
  cp,
  mkdir,
  readFile,
  readdir,
  rm,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const scriptFile = fileURLToPath(import.meta.url);
const siteRoot = path.resolve(path.dirname(scriptFile), '..');
const repositoryRoot = path.resolve(siteRoot, '..');
const skipCompile = process.argv.includes('--skip-compile');
const publicRoot = path.join(siteRoot, 'public');
const generatedPublicRoot = path.join(publicRoot, 'generated', 'examples');
const generatedSourceRoot = path.join(siteRoot, 'src', 'generated');
const launcherRoot = path.join(siteRoot, '.generated');
const referenceRoot = path.join(siteRoot, 'content', 'docs', 'reference');
const basePath = normalizeBasePath(process.env.NEXT_PUBLIC_BASE_PATH ?? '');

const blockedPatterns = [
  {
    pattern: /(?:import|export)\s+['"]dart:io['"]/,
    reason: 'Uses dart:io and requires a native operating-system runtime.',
  },
  {
    pattern: /(?:import|export)\s+['"]dart:ffi['"]/,
    reason: 'Uses dart:ffi and requires native libraries.',
  },
  {
    pattern: /(?:import|export)\s+['"]dart:isolate['"]/,
    reason: 'Uses native isolate APIs that are not available in this browser runner.',
  },
  {
    pattern: /\b(?:Process|ProcessSignal|File|Directory|RandomAccessFile|InternetAddress|RawSocket|ServerSocket|SecureSocket|HttpClient)\b/,
    reason: 'Uses operating-system files, processes, or sockets.',
  },
  {
    pattern: /\b(?:PtyController|TerminalXterm|FfmpegProcessBackend|MediaController)\b/,
    reason: 'Requires a PTY, FFmpeg, or another native process.',
  },
];

await main();

async function main() {
  await Promise.all([
    mkdir(generatedPublicRoot, { recursive: true }),
    mkdir(generatedSourceRoot, { recursive: true }),
    mkdir(launcherRoot, { recursive: true }),
    mkdir(publicRoot, { recursive: true }),
  ]);

  await syncBrandAssets();
  const documentationCount = await syncEngineeringReference();
  const examples = await discoverExamples();

  if (!skipCompile) {
    await compileExampleBundles(examples);
  }

  await writeExampleManifest(examples, documentationCount);

  const runnable = examples.filter((example) => example.runnable).length;
  console.log(
    `Prepared ${examples.length} examples (${runnable} browser-runnable) and ${documentationCount} reference documents.`,
  );
}

async function syncBrandAssets() {
  const source = path.join(repositoryRoot, 'doc', 'assets', 'cinder_logo.png');
  const destination = path.join(publicRoot, 'cinder-logo.png');

  if (await exists(source)) {
    await copyFile(source, destination);
  }

  const sourceAssets = path.join(repositoryRoot, 'doc', 'assets');
  const destinationAssets = path.join(publicRoot, 'doc-assets');

  if (await exists(sourceAssets)) {
    await rm(destinationAssets, { recursive: true, force: true });
    await cp(sourceAssets, destinationAssets, { recursive: true });
  }
}

async function syncEngineeringReference() {
  const sourceRoot = path.join(repositoryRoot, 'doc');
  await rm(referenceRoot, { recursive: true, force: true });
  await mkdir(referenceRoot, { recursive: true });

  if (!(await exists(sourceRoot))) {
    return 0;
  }

  const files = (await walk(sourceRoot))
    .filter((file) => file.endsWith('.md'))
    .sort((left, right) => left.localeCompare(right));
  const pageSlugs = [];

  for (const file of files) {
    const relative = normalizePath(path.relative(sourceRoot, file));
    const slug = relative.replace(/\.md$/i, '');
    if (slug === 'index') continue;

    const raw = await readFile(file, 'utf8');
    const title = extractTitle(raw, slug);
    const body = normalizeReferenceBody(raw);
    const output = path.join(referenceRoot, `${slug}.mdx`);

    await mkdir(path.dirname(output), { recursive: true });
    await writeFile(
      output,
      `---\ntitle: ${JSON.stringify(title)}\ndescription: ${JSON.stringify(`Cinder engineering reference for ${title}.`)}\n---\n\n${body}\n`,
      'utf8',
    );
    pageSlugs.push(slug);
  }

  await writeFile(
    path.join(referenceRoot, 'index.mdx'),
    `---\ntitle: Engineering reference\ndescription: Architecture, rendering, input, graphics, security, and performance contracts maintained with the Cinder source tree.\nicon: library\n---\n\nThis section is generated from the repository's \`doc/\` directory during every site build. It is not a second, drifting copy of the documentation.\n\nUse the navigation to inspect the runtime contracts, implementation notes, and subsystem guides that ship with Cinder.\n`,
    'utf8',
  );

  await writeFile(
    path.join(referenceRoot, 'meta.json'),
    `${JSON.stringify(
      {
        title: 'Engineering reference',
        pages: ['index', ...pageSlugs],
      },
      null,
      2,
    )}\n`,
    'utf8',
  );

  return files.length;
}

function normalizeReferenceBody(raw) {
  let body = raw.replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n/, '');
  body = body.replace(/^#\s+.+?\r?\n+/, '');
  body = body.replace(
    /\]\((?:\.\.\/)*assets\//g,
    `](${basePath}/doc-assets/`,
  );
  body = body.replace(
    /(?:src|href)=["'](?:\.\.\/)*assets\//g,
    (match) => `${match.slice(0, match.indexOf('=') + 2)}${basePath}/doc-assets/`,
  );
  return body.trim();
}

async function discoverExamples() {
  const roots = [];
  const rootExamples = path.join(repositoryRoot, 'example');
  const landingExamples = path.join(repositoryRoot, 'landing', 'demos');

  if (await exists(rootExamples)) roots.push(rootExamples);
  if (await exists(landingExamples)) roots.push(landingExamples);

  const packagesRoot = path.join(repositoryRoot, 'packages');
  if (await exists(packagesRoot)) {
    for (const entry of await readdir(packagesRoot, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const packageExamples = path.join(packagesRoot, entry.name, 'example');
      if (await exists(packageExamples)) roots.push(packageExamples);
    }
  }

  const files = [];
  for (const root of roots) {
    for (const file of await walk(root)) {
      if (file.endsWith('.dart')) files.push(file);
    }
  }

  files.sort((left, right) => left.localeCompare(right));
  const usedSlugs = new Set();
  const examples = [];

  for (const file of files) {
    const source = await readFile(file, 'utf8');
    const repositoryPath = normalizePath(path.relative(repositoryRoot, file));
    const baseSlug = createBaseSlug(repositoryPath);
    const slug = uniqueSlug(baseSlug, usedSlugs);
    const title = titleFromFilename(path.basename(file, '.dart'));
    const category = inferCategory(repositoryPath, source);
    const blocker = findWebBlocker(source);
    const hasMain = /\bmain\s*\(/.test(source);
    const acceptsArguments = /\bmain\s*\(\s*(?:final\s+)?List\s*<\s*String\s*>/.test(source);
    const sourceOutput = path.join(generatedPublicRoot, slug, 'source.dart');

    await mkdir(path.dirname(sourceOutput), { recursive: true });
    await writeFile(sourceOutput, source, 'utf8');

    examples.push({
      slug,
      title,
      category,
      repositoryPath,
      sourcePath: `${basePath}/generated/examples/${slug}/source.dart`,
      sourceUrl: `https://github.com/eukalpia/cinder/blob/main/${repositoryPath}`,
      runnable: false,
      bundle: null,
      reason: blocker?.reason ?? (hasMain ? 'Pending browser compilation.' : 'This source file has no executable main() entrypoint.'),
      webCandidate: !blocker && hasMain,
      acceptsArguments,
      description: inferDescription(source, title, category),
    });
  }

  return examples;
}

async function compileExampleBundles(examples) {
  await rm(generatedPublicRoot, { recursive: true, force: true });
  await mkdir(generatedPublicRoot, { recursive: true });

  for (const example of examples) {
    const source = await readFile(
      path.join(repositoryRoot, example.repositoryPath),
      'utf8',
    );
    const sourceOutput = path.join(generatedPublicRoot, example.slug, 'source.dart');
    await mkdir(path.dirname(sourceOutput), { recursive: true });
    await writeFile(sourceOutput, source, 'utf8');
  }

  const groups = Map.groupBy(
    examples.filter((example) => example.webCandidate),
    (example) => slugify(example.category),
  );

  for (const [groupName, groupExamples] of groups) {
    await compileGroup(groupName, groupExamples);
  }
}

async function compileGroup(groupName, groupExamples) {
  let active = [...groupExamples];
  const excluded = new Set();
  const bundleName = `${groupName}.js`;
  const bundleOutput = path.join(generatedPublicRoot, bundleName);

  while (active.length > 0) {
    const launcher = path.join(launcherRoot, `${groupName}.dart`);
    await writeLauncher(launcher, active);
    await rm(bundleOutput, { force: true });

    try {
      await execFileAsync(
        'dart',
        [
          'compile',
          'js',
          '-O2',
          '--no-source-maps',
          '-o',
          bundleOutput,
          launcher,
        ],
        {
          cwd: repositoryRoot,
          maxBuffer: 16 * 1024 * 1024,
          timeout: Number(process.env.CINDER_WEB_COMPILE_TIMEOUT_MS ?? 900_000),
        },
      );

      for (const example of active) {
        example.runnable = true;
        example.bundle = `${basePath}/generated/examples/${bundleName}`;
        example.reason = null;
      }
      return;
    } catch (error) {
      const stderr = String(error.stderr ?? error.message ?? 'Unknown compiler error');
      const offender = active.find((example) =>
        stderr.includes(example.repositoryPath),
      );

      if (!offender || excluded.has(offender.slug)) {
        const summary = firstCompilerMessage(stderr);
        for (const example of active) {
          example.reason = `Browser compilation stopped in shared code: ${summary}`;
        }
        await writeFile(
          path.join(generatedPublicRoot, `${groupName}.build-error.txt`),
          stderr,
          'utf8',
        );
        return;
      }

      offender.webCandidate = false;
      offender.reason = `The Dart web compiler rejected this example: ${firstCompilerMessage(stderr, offender.repositoryPath)}`;
      excluded.add(offender.slug);
      active = active.filter((example) => example !== offender);
    }
  }
}

async function writeLauncher(output, examples) {
  const imports = examples
    .map((example, index) => {
      const sourceFile = path.join(repositoryRoot, example.repositoryPath);
      const relative = normalizePath(path.relative(path.dirname(output), sourceFile));
      const uri = relative.startsWith('.') ? relative : `./${relative}`;
      return `import ${JSON.stringify(uri)} as example_${index};`;
    })
    .join('\n');

  const cases = examples
    .map((example, index) => {
      const invocation = example.acceptsArguments
        ? `example_${index}.main(const <String>[]);`
        : `example_${index}.main();`;
      return `    case ${JSON.stringify(example.slug)}:\n      await Future<void>.sync(() { ${invocation} });\n      return;`;
    })
    .join('\n');

  const source = `import 'dart:async';\n${imports}\n\nFuture<void> main() async {\n  final segments = Uri.base.pathSegments.where((segment) => segment.isNotEmpty).toList();\n  final slug = segments.isEmpty ? '' : segments.last;\n\n  switch (slug) {\n${cases}\n    default:\n      throw StateError('Unknown Cinder web example: $slug');\n  }\n}\n`;

  await writeFile(output, source, 'utf8');
}

async function writeExampleManifest(examples, documentationCount) {
  const cleaned = examples.map(({ webCandidate, acceptsArguments, ...example }) => example);
  const manifest = {
    generatedAt: new Date().toISOString(),
    version: '1.0.0-dev.2',
    documentationCount,
    examples: cleaned,
  };
  const json = `${JSON.stringify(manifest, null, 2)}\n`;

  await writeFile(path.join(generatedSourceRoot, 'examples.json'), json, 'utf8');
  await writeFile(path.join(generatedPublicRoot, 'manifest.json'), json, 'utf8');
}

function findWebBlocker(source) {
  return blockedPatterns.find(({ pattern }) => pattern.test(source)) ?? null;
}

function inferDescription(source, title, category) {
  const docComment = source.match(/(?:^|\n)\s*\/\/\/\s*([^\n]+)/)?.[1]?.trim();
  if (docComment && docComment.length >= 20) return docComment;
  return `${title} demonstrates Cinder's ${category.toLowerCase()} APIs in a terminal application.`;
}

function inferCategory(repositoryPath, source) {
  const text = `${repositoryPath} ${source.slice(0, 2500)}`.toLowerCase();
  const rules = [
    ['Media', /\b(video|audio|media|image|sixel|kitty|iterm)\b/],
    ['Input', /\b(text_field|textfield|input|form|focus|keyboard|mouse|gesture)\b/],
    ['Data', /\b(list|scroll|table|grid|tree|chart|log|data)\b/],
    ['Navigation', /\b(navigation|navigator|route|dialog|overlay|menu|tabs|drawer)\b/],
    ['Motion', /\b(animation|animated|progress|spinner|transition)\b/],
    ['Layout', /\b(layout|row|column|stack|flex|expanded|container|split)\b/],
    ['Terminal', /\b(terminal|pty|shell|process|ssh|xterm)\b/],
  ];
  return rules.find(([, pattern]) => pattern.test(text))?.[0] ?? 'Framework';
}

function createBaseSlug(repositoryPath) {
  let value = repositoryPath
    .replace(/^example\//, '')
    .replace(/^landing\/demos\//, '')
    .replace(/^packages\//, '')
    .replace(/\/example\//, '/')
    .replace(/\.dart$/i, '');
  return slugify(value.replaceAll('/', '-')) || 'example';
}

function uniqueSlug(base, used) {
  let slug = base;
  let index = 2;
  while (used.has(slug)) slug = `${base}-${index++}`;
  used.add(slug);
  return slug;
}

function titleFromFilename(filename) {
  return filename
    .replace(/[_-]+/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function extractTitle(raw, slug) {
  const frontmatterTitle = raw.match(/^---\r?\n[\s\S]*?^title:\s*["']?(.+?)["']?\s*$[\s\S]*?^---/m)?.[1];
  const heading = raw.match(/^#\s+(.+)$/m)?.[1];
  return (frontmatterTitle ?? heading ?? titleFromFilename(path.basename(slug))).trim();
}

function firstCompilerMessage(stderr, repositoryPath = '') {
  const lines = stderr
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  const preferred = lines.find((line) =>
    repositoryPath ? line.includes(repositoryPath) : /Error:|error:/i.test(line),
  );
  return sanitizeCompilerMessage(preferred ?? lines[0] ?? 'unknown web compiler error');
}

function sanitizeCompilerMessage(message) {
  return message
    .replaceAll(repositoryRoot, '<repo>')
    .replace(/\s+/g, ' ')
    .slice(0, 240);
}

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function normalizeBasePath(value) {
  if (!value || value === '/') return '';
  return `/${value.replace(/^\/+|\/+$/g, '')}`;
}

function normalizePath(value) {
  return value.split(path.sep).join('/');
}

async function walk(root) {
  const output = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    if (entry.name.startsWith('.') || entry.name === 'build' || entry.name === 'node_modules') {
      continue;
    }
    const absolute = path.join(root, entry.name);
    if (entry.isDirectory()) output.push(...(await walk(absolute)));
    else output.push(absolute);
  }
  return output;
}

async function exists(file) {
  try {
    await access(file);
    return true;
  } catch {
    return false;
  }
}
