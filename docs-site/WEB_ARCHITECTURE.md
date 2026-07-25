# Cinder web architecture

## Scope

`docs-site/` is the single public website for Cinder. It owns:

- the homepage;
- long-form documentation;
- engineering reference pages synchronized from `doc/`;
- the generated example catalogue;
- isolated live example runners;
- generated Dart API documentation;
- static GitHub Pages output.

The old `landing/` directory is an implementation source to migrate from, not a second public source of truth.

## Current repository foundations

Cinder already provides:

- Widget, Element, State, BuildContext, and RenderObject architecture;
- terminal layout, painting, cell buffers, and differential output;
- conditional native and web backends;
- `WebBackend` communication through `window.cinderBridge`;
- xterm-hosted browser examples;
- a Next.js/Fumadocs documentation project with static export;
- architecture documents under `doc/`;
- root and package example directories.

## Problems addressed

1. The previous homepage redirected directly to documentation.
2. The static landing and docs site could drift independently.
3. Browser demos were manually selected.
4. Example counts and compatibility could become stale.
5. The existing landing loaded browser terminal dependencies directly from CDN scripts.
6. Runtime lifecycle needed explicit ownership and teardown.
7. Documentation contained older versions and API names.
8. The visual language resembled a generic developer-tool landing page rather than Cinder itself.

## Target request flow

```text
Repository source
  ├─ pubspec.yaml
  ├─ doc/**/*.md
  ├─ example/**/*.dart
  ├─ packages/*/example/**/*.dart
  └─ landing/demos/**/*.dart
          │
          ▼
docs-site/scripts/prepare-site.mjs
  ├─ synchronizes brand assets
  ├─ generates engineering reference MDX
  ├─ discovers examples
  ├─ classifies obvious native blockers
  ├─ writes browser launcher registries
  ├─ compiles Dart to JavaScript
  ├─ records compilation failures
  └─ writes a typed example manifest
          │
          ▼
Next.js static export
  ├─ /
  ├─ /docs/**
  ├─ /examples/
  ├─ /examples/[slug]/
  ├─ /play/[slug]/
  ├─ /api/
  ├─ /robots.txt
  └─ /sitemap.xml
```

## Browser runtime contract

The browser does not reimplement Cinder UI in React.

```text
Dart example
  → Cinder Widget tree
  → Element reconciliation
  → RenderObject layout and paint
  → terminal cell buffer
  → differential ANSI output
  → WebBackend
  → window.cinderBridge
  → xterm.js terminal host
```

React owns only the surrounding document, runner controls, loading/error state, and iframe boundary.

## Isolation and lifecycle

Every live application route is loaded in its own document context.

Boot order:

1. create the terminal host;
2. fit the terminal and obtain non-zero columns/rows;
3. create `window.cinderBridge` with dimensions and output callback;
4. subscribe to keyboard and resize events;
5. load the generated Dart bundle;
6. allow the Cinder guest to register input, resize, and shutdown callbacks;
7. focus the terminal only after the guest loads.

Teardown order:

1. mark the host disposed;
2. disconnect `ResizeObserver`;
3. dispose xterm subscriptions;
4. remove the guest script;
5. dispose xterm;
6. clear host references;
7. delete `window.cinderBridge`;
8. destroy the iframe when navigating or restarting.

A restart recreates the runner document instead of attempting to reset framework singletons inside a reused JavaScript context.

## Example discovery

The build scans:

- `example/**/*.dart`;
- `packages/*/example/**/*.dart`;
- `landing/demos/**/*.dart`.

Each manifest entry records:

- stable slug;
- title;
- category;
- repository path;
- generated source path;
- GitHub source URL;
- description;
- browser bundle;
- runnable state;
- failure or native-only reason.

Counts displayed by the site come from this generated manifest.

## Compilation strategy

The first production target is `dart compile js -O2 --no-source-maps`.

Examples are grouped by inferred category into registry bundles. The generated launcher selects an example from the final URL slug. Grouped bundles reduce total output files while still allowing the build script to remove an individual source that the web compiler rejects and retry the remaining group.

Compiler stderr is preserved as a generated build-error artifact when shared code prevents the whole group from compiling.

A future WASM target can be added behind the same manifest fields without changing public routes.

## Browser compatibility classes

### Direct web

The original example compiles without native APIs. The published runner executes the repository source.

### Adapter-backed

The Cinder UI remains unchanged while a browser service replaces a portable capability such as persistence, clipboard, clock, assets, or deterministic data.

### Native source

The example requires a PTY, operating-system process, FFI, native sockets, FFmpeg process, raw filesystem, or another capability the static browser site cannot honestly provide. The detail page still publishes source and the exact reason. It must not display a fake running state.

## Documentation synchronization

`doc/**/*.md` is converted to generated MDX under `content/docs/reference/` on every build. Asset links are rewritten to the synchronized public asset directory. The generated `meta.json` follows the repository directory order.

Long-form guides remain curated in `docs-site/content/docs/`, but code snippets and version claims must be validated against the current public API.

## API reference

The Pages build should run `dart doc` and copy the output below `/api/`. Deep links must remain static-export compatible. The navigation links to `/api/` only after the generated output is present.

## Static hosting and base path

The site uses `output: 'export'` and `trailingSlash: true`.

`NEXT_PUBLIC_BASE_PATH` is empty for a custom domain and `/cinder` for GitHub project Pages. All generated asset paths, runner bundle paths, iframes, manifest links, sitemap entries, and documentation assets use the same normalized base path.

`NEXT_PUBLIC_SITE_ORIGIN` controls canonical, Open Graph, robots, sitemap, and structured-data origins.

## SEO strategy

- semantic HTML remains the source of discoverable documentation;
- each example has a static detail route;
- isolated runner routes are `noindex`;
- canonical URL, Open Graph, Twitter metadata, manifest, robots, and sitemap are generated;
- SoftwareSourceCode and WebSite structured data reference the real repository;
- headings describe the framework rather than repeating marketing slogans;
- example and documentation counts are build-generated;
- the live runtime is supporting evidence, not the only content on the page.

## Testing strategy

### Repository and Dart

- formatting;
- analyzer with fatal infos;
- existing test suites;
- browser example compilation;
- manifest completeness;
- generated bundle existence;
- WebBackend lifecycle tests.

### Site

- TypeScript and ESLint;
- Next production export;
- route and asset smoke tests;
- base-path validation;
- broken-link validation;
- stale-version and old-API checks.

### Browser

- homepage and docs load;
- catalogue search and filters work;
- live terminal boots;
- keyboard input reaches Cinder;
- resize reaches Cinder;
- restart creates a clean runtime;
- navigating away stops the previous runtime;
- native-only explanations render;
- mobile and keyboard navigation work.

## Browser limitations

A static browser runner cannot provide unrestricted:

- PTY or shell execution;
- SSH access;
- arbitrary operating-system processes;
- raw sockets;
- native file access without explicit browser APIs and user permission;
- FFI;
- FFmpeg process control;
- native terminal graphics capability detection.

These limits must be visible and must not be hidden behind simulated success states.

## Readiness criteria

The web release is ready when:

- the homepage is a real route rather than a redirect;
- the Cinder scene and example runners are real compiled Cinder apps;
- all official examples have generated catalogue entries and detail routes;
- browser-runnable examples compile during CI;
- source-only examples contain an actionable limitation reason;
- documentation and engineering reference use current API names and version metadata;
- the Pages export works with and without a base path;
- accessibility, mobile, keyboard, and runtime lifecycle checks pass;
- the final diff contains no temporary payloads, fake metrics, or manually maintained example counts.
