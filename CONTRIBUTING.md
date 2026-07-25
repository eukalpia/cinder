# Contributing to Cinder

Cinder is a terminal framework, not a collection of screenshots. Changes must preserve the real Widget → Element → RenderObject → cell-buffer pipeline on native terminals and in the browser runtime.

## Branch flow

Create feature and fix branches from `dev` unless a release-maintenance change explicitly targets another branch.

```text
feature/* → dev → test → main
```

Do not develop directly on `main`.

## Local setup

```bash
git clone https://github.com/eukalpia/cinder.git
cd cinder
dart pub get
```

Install site dependencies separately:

```bash
cd docs-site
npm ci
```

## Required validation

Run the relevant checks before opening a pull request:

```bash
dart format --output=none --set-exit-if-changed lib test example benchmark packages
dart analyze --fatal-infos
dart test
```

For public-site, documentation, example, browser-backend, or routing changes:

```bash
cd docs-site
npm run lint
npm run typecheck
npm run build
npm run test:routes
npx playwright install chromium
npm run test:browser
```

The production build uses `NEXT_PUBLIC_BASE_PATH=/cinder` on GitHub Pages. Test that configuration when changing asset paths or routes:

```bash
NEXT_PUBLIC_BASE_PATH=/cinder \
NEXT_PUBLIC_SITE_ORIGIN=https://eukalpia.github.io \
npm run build
```

## Adding an example

Official examples are discovered automatically from:

- `example/**/*.dart`;
- `packages/*/example/**/*.dart`;
- `landing/demos/**/*.dart` while legacy demo sources remain in the repository.

A new example must:

1. have a stable `main()` entry point;
2. explain its purpose with a Dart documentation comment;
3. avoid unrelated native dependencies;
4. dispose controllers, focus nodes, timers, subscriptions, files, sockets, and processes;
5. work at narrow and large terminal sizes;
6. support keyboard operation when interactive;
7. appear in the generated `/examples/` catalogue;
8. have an exported `/examples/[slug]/` and `/play/[slug]/` route.

Do not manually edit generated manifests or bundles. Run `npm run prepare:site` instead.

## Browser compatibility modes

Every example receives one explicit runtime mode:

| Mode | Contract |
| --- | --- |
| `direct-web` | Original repository Dart source is compiled and executed in the browser. |
| `browser-adapter` | An official browser capability adapter preserves the example intent and Cinder UI. |
| `browser-sandbox` | A deterministic backend demonstrates state transitions without claiming native access. |
| `native-only` | The example genuinely requires a native terminal or operating-system capability. |
| `build-failed` | The source is indexed, but the current Dart web compiler did not produce a bundle. |

Never label a deterministic shell as a real PTY, a fixture as real SSH, or an in-memory filesystem as unrestricted host-file access.

## Adding a browser adapter

Create:

```text
docs-site/browser-adapters/<generated-example-slug>.dart
```

The adapter must:

- use real Cinder widgets and rendering;
- preserve the original example's educational intent;
- state the browser capability boundary in the UI;
- avoid network services that make static Pages deployment nondeterministic;
- expose an executable `main()`;
- compile with `dart compile js`;
- clean up timers and controllers;
- never replace the terminal UI with React or static HTML.

Use `browser-adapter` when a browser capability is genuinely substituted, such as in-memory RGBA pixels replacing a local image path. Use `browser-sandbox` when the native operation itself cannot exist, such as PTY process execution.

## Documentation

Curated guides live under `docs-site/content/docs/`. Engineering documents under `doc/` are synchronized into the reference section during every site build.

Documentation changes must:

- use current public API names;
- avoid manually duplicated version strings;
- include runnable snippets where practical;
- link to real source or tests for substantial claims;
- describe native and browser behavior separately when they differ;
- contain no invented benchmarks, testimonials, stars, adoption numbers, or compatibility claims.

## Design changes

Read and follow:

```text
skills/human_design/SKILL.md
```

Cinder interfaces should show the product before marketing copy. Prefer terminal-native ledgers, pipelines, source/runtime splits, and real application surfaces over rounded-card grids, glowing blobs, glass panels, or fake terminal windows.

Review at these widths before completion:

- 1440×1000;
- 1024×768;
- 768×1024;
- 390×844;
- 320×700.

## Pull requests

A pull request should state:

- the problem and architectural decision;
- native and browser behavior;
- tests run;
- generated example compatibility changes;
- screenshots for visual work;
- honest remaining limitations.

Do not merge while required checks are failing. Do not commit temporary diagnostic workflows, generated compiler launchers, local logs, or screenshot artifacts.
