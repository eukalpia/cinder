import { execFile } from 'node:child_process';
import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const scriptFile = fileURLToPath(import.meta.url);
const siteRoot = path.resolve(path.dirname(scriptFile), '..');
const repositoryRoot = path.resolve(siteRoot, '..');
const generatedRoot = path.join(siteRoot, 'public', 'generated', 'examples');
const sourceManifestPath = path.join(siteRoot, 'src', 'generated', 'examples.json');
const publicManifestPath = path.join(generatedRoot, 'manifest.json');
const launcherRoot = path.join(siteRoot, '.generated');
const adapterRoot = path.join(siteRoot, 'browser-adapters');
const basePath = normalizeBasePath(process.env.NEXT_PUBLIC_BASE_PATH ?? '');
const skipCompile = process.argv.includes('--skip-compile');
const preparedPackageRoots = new Set();

const adapterModes = new Map([
  ['clipboard-debug', 'browser-sandbox'],
  ['gesture-demo', 'browser-adapter'],
  ['hoverable-widgets-demo', 'browser-adapter'],
  ['image-demo', 'browser-adapter'],
  ['image-listview-demo', 'browser-adapter'],
  ['infinite-hoverable-list-demo', 'browser-adapter'],
  ['logger-demo', 'browser-adapter'],
  ['mouse-demo', 'browser-adapter'],
  ['pty-controller-demo', 'browser-sandbox'],
  ['test-resize-demo', 'browser-adapter'],
  ['test-resize-improved', 'browser-adapter'],
  ['test-resize', 'browser-adapter'],
  ['textfield-demo', 'browser-adapter'],
]);

await main();

async function main() {
  await mkdir(launcherRoot, { recursive: true });
  await mkdir(generatedRoot, { recursive: true });

  const manifest = JSON.parse(await readFile(sourceManifestPath, 'utf8'));

  for (const example of manifest.examples) {
    const sourceFile = path.join(repositoryRoot, example.repositoryPath);
    const source = await readFile(sourceFile, 'utf8');
    const adapterFile = path.join(adapterRoot, `${example.slug}.dart`);
    const hasAdapter = await exists(adapterFile);
    const adapterSource = hasAdapter ? await readFile(adapterFile, 'utf8') : '';
    const runtimeSource = `${source}\n${adapterSource}`;

    example.controls = inferControls(runtimeSource);
    example.tags = inferTags(example.repositoryPath, runtimeSource, example.category);
    example.adapterSourceUrl = hasAdapter
      ? `https://github.com/eukalpia/cinder/blob/main/docs-site/browser-adapters/${example.slug}.dart`
      : null;

    if (hasAdapter) {
      example.runtimeMode = adapterModes.get(example.slug) ?? 'browser-adapter';
      example.runtimeNote = runtimeNoteFor(example.runtimeMode);
      if (!skipCompile) {
        await compileOne(example, adapterFile, false, false);
      }
      continue;
    }

    if (example.runnable) {
      example.runtimeMode = 'direct-web';
      example.runtimeNote = runtimeNoteFor('direct-web');
      continue;
    }

    if (!skipCompile && isPortableCandidate(source)) {
      await compileOne(
        example,
        sourceFile,
        acceptsArguments(source),
        true,
      );
      continue;
    }

    example.runtimeMode = example.reason?.startsWith('The Dart web compiler rejected')
      ? 'build-failed'
      : 'native-only';
    example.runtimeNote = runtimeNoteFor(example.runtimeMode);
  }

  const json = `${JSON.stringify(manifest, null, 2)}\n`;
  await writeFile(sourceManifestPath, json, 'utf8');
  await writeFile(publicManifestPath, json, 'utf8');

  const counts = countBy(manifest.examples, (example) => example.runtimeMode);
  const runnable = manifest.examples.filter((example) => example.runnable).length;
  console.log(
    `Polished ${manifest.examples.length} examples: ${runnable} runnable; ${Array.from(
      counts.entries(),
    )
      .map(([mode, count]) => `${mode}=${count}`)
      .join(', ')}.`,
  );
}

async function compileOne(
  example,
  sourceFile,
  withArguments,
  useSourcePackage,
) {
  const packageRoot = useSourcePackage
    ? packageRootFor(example.repositoryPath)
    : repositoryRoot;
  const packageScoped = packageRoot !== repositoryRoot;
  const currentLauncherRoot = packageScoped
    ? path.join(packageRoot, '.cinder-web')
    : launcherRoot;
  const launcher = path.join(
    currentLauncherRoot,
    `polish-${example.slug}.dart`,
  );
  const bundleName = `example-${example.slug}.js`;
  const bundleOutput = path.join(generatedRoot, bundleName);

  if (packageScoped) {
    await preparePackageRoot(packageRoot);
  }
  await mkdir(currentLauncherRoot, { recursive: true });

  const relative = normalizePath(path.relative(path.dirname(launcher), sourceFile));
  const uri = relative.startsWith('.') ? relative : `./${relative}`;
  const invocation = withArguments ? 'example.main(const <String>[]);' : 'example.main();';

  await writeFile(
    launcher,
    `import 'dart:async';\nimport ${JSON.stringify(uri)} as example;\n\nFuture<void> main() async {\n  await Future<void>.sync(() { ${invocation} });\n}\n`,
    'utf8',
  );

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
        cwd: packageRoot,
        maxBuffer: 16 * 1024 * 1024,
        timeout: Number(process.env.CINDER_WEB_COMPILE_TIMEOUT_MS ?? 900_000),
      },
    );

    example.runnable = true;
    example.bundle = `${basePath}/generated/examples/${bundleName}`;
    example.reason = null;
    example.runtimeMode = adapterModes.get(example.slug) ?? 'direct-web';
    example.runtimeNote = runtimeNoteFor(example.runtimeMode);
  } catch (error) {
    const diagnostics = compilerDiagnostics(error);
    example.runnable = false;
    example.bundle = null;
    example.runtimeMode = 'build-failed';
    example.runtimeNote = runtimeNoteFor('build-failed');
    example.reason = `The isolated Dart web compiler rejected this example: ${firstMessage(
      diagnostics,
    )}`;
    await writeFile(
      path.join(generatedRoot, `${example.slug}.build-error.txt`),
      diagnostics || String(error),
      'utf8',
    );
  }
}

async function preparePackageRoot(packageRoot) {
  if (preparedPackageRoots.has(packageRoot)) return;
  preparedPackageRoots.add(packageRoot);

  await execFileAsync('dart', ['pub', 'get'], {
    cwd: packageRoot,
    maxBuffer: 16 * 1024 * 1024,
    timeout: Number(process.env.CINDER_WEB_COMPILE_TIMEOUT_MS ?? 900_000),
  });
}

function packageRootFor(repositoryPath) {
  const match = /^packages\/([^/]+)\//.exec(repositoryPath);
  return match
    ? path.join(repositoryRoot, 'packages', match[1])
    : repositoryRoot;
}

function isPortableCandidate(source) {
  if (/(?:import|export)\s+['"]dart:(?:io|ffi|isolate)['"]/.test(source)) return false;
  if (/\b(?:PtyController|FfmpegProcessBackend|MediaController)\b/.test(source)) {
    return false;
  }
  return /\bmain\s*\(/.test(source);
}

function acceptsArguments(source) {
  return /\bmain\s*\(\s*(?:final\s+)?List\s*<\s*String\s*>/.test(source);
}

function runtimeNoteFor(mode) {
  switch (mode) {
    case 'browser-adapter':
      return 'Runs through an official browser adapter while preserving the example intent and Cinder widget model.';
    case 'browser-sandbox':
      return 'Runs in a deterministic browser sandbox. Native operating-system access is not presented as real access.';
    case 'native-only':
      return 'The original source requires a native terminal or operating-system capability.';
    case 'build-failed':
      return 'The example is indexed, but the current Dart web compiler did not produce a runnable bundle.';
    default:
      return 'Runs directly from repository Dart source through Cinder WebBackend.';
  }
}

function inferControls(source) {
  const controls = [];
  const candidates = [
    ['Tab / Shift+Tab', /LogicalKey\.tab|Shift\+Tab/i],
    ['Arrow keys', /LogicalKey\.arrow(?:Up|Down|Left|Right)|keyboardScrollable/],
    ['Enter', /LogicalKey\.enter|onSubmitted/],
    ['Space', /LogicalKey\.space/],
    ['Escape', /LogicalKey\.escape/],
    ['Mouse', /GestureDetector|MouseRegion|onHover|onTap/],
    ['Scroll', /ListView|SingleChildScrollView|Scrollbar/],
    ['Text input', /TextField|TextEditingController/],
  ];
  for (const [label, pattern] of candidates) {
    if (pattern.test(source)) controls.push(label);
  }
  return controls;
}

function inferTags(repositoryPath, source, category) {
  const text = `${repositoryPath} ${source}`.toLowerCase();
  const tags = new Set([category.toLowerCase()]);
  const rules = [
    ['keyboard', /keyboard|logicalkey|onkey/],
    ['mouse', /mouse|gesture|hover|tap/],
    ['unicode', /unicode|emoji|cjk|chinese|arabic|grapheme/],
    ['scrolling', /listview|scrollbar|scrollcontroller/],
    ['state', /statefulwidget|setstate/],
    ['animation', /animation|timer|ticker|progress/],
    ['images', /image|sixel|kitty|iterm/],
    ['terminal', /terminal|pty|xterm|shell/],
    ['forms', /textfield|form|controller/],
  ];
  for (const [tag, pattern] of rules) {
    if (pattern.test(text)) tags.add(tag);
  }
  return Array.from(tags).sort();
}

function compilerDiagnostics(error) {
  return [error?.stderr, error?.stdout, error?.message]
    .map((value) => String(value ?? '').trim())
    .filter(Boolean)
    .join('\n');
}

function firstMessage(value) {
  const line = value
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .find(Boolean);
  return (line ?? 'unknown compiler failure')
    .replaceAll(repositoryRoot, '<repo>')
    .replace(/\s+/g, ' ')
    .slice(0, 320);
}

function normalizeBasePath(value) {
  if (!value || value === '/') return '';
  return `/${value.replace(/^\/+|\/+$/g, '')}`;
}

function normalizePath(value) {
  return value.split(path.sep).join('/');
}

async function exists(file) {
  try {
    await access(file);
    return true;
  } catch {
    return false;
  }
}

function countBy(values, selector) {
  const counts = new Map();
  for (const value of values) {
    const key = selector(value);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return counts;
}
