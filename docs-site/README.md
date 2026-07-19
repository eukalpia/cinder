# Cinder web platform

`docs-site/` is the single public website for Cinder. It contains the terminal-native homepage, documentation, engineering reference, generated example catalogue, isolated browser runners, and Dart API reference.

## Requirements

- Dart stable matching the repository SDK constraint;
- Node.js 22;
- npm;
- Chromium for Playwright browser tests.

From the repository root:

```bash
dart pub get
cd docs-site
npm ci
```

## Development

```bash
npm run dev
```

Development mode scans documentation and examples but skips the expensive full browser compilation pass. Existing generated metadata remains available for route development.

## Production build

```bash
npm run build
```

The build performs these stages:

1. synchronize brand assets;
2. generate engineering-reference MDX from `../doc/`;
3. discover official Dart examples;
4. compile direct-web example groups;
5. compile browser adapters and recover isolated portable examples;
6. resolve nested package examples with their own package configuration;
7. classify every example runtime mode;
8. synchronize the package version from `../pubspec.yaml`;
9. build the static Next.js export;
10. write `.nojekyll` for GitHub Pages.

A nested example under `packages/<name>/example/` is compiled from that package root. The recovery pass runs `dart pub get` only for a nested package that needs an isolated browser build, so its package imports and dependency overrides remain authoritative.

Verify the export:

```bash
npm run test:routes
```

## GitHub Pages base path

Project Pages is deployed below `/cinder`:

```bash
NEXT_PUBLIC_BASE_PATH=/cinder \
NEXT_PUBLIC_SITE_ORIGIN=https://eukalpia.github.io \
npm run build
```

All public assets, example bundles, iframe routes, sitemap entries, and generated source links must use the normalized base path.

## Browser tests

```bash
npx playwright install chromium
npm run test:browser
```

The suite checks real Cinder output, keyboard input, resize propagation, restart isolation, compatibility disclosures, Unicode input, keyboard navigation, and responsive widths. Screenshots are written to Playwright test artifacts rather than committed to the repository.

## Example runtime modes

- `direct-web`: original Dart source;
- `browser-adapter`: real Cinder UI with a browser capability implementation;
- `browser-sandbox`: deterministic substitute with an explicit native boundary;
- `native-only`: source is indexed but requires native access;
- `build-failed`: isolated web compilation failed and diagnostics are preserved.

Adapters live in `browser-adapters/` and are selected by generated example slug. They must not imitate Cinder with HTML.

## Generated files

Do not edit these manually:

- `src/generated/examples.json`;
- `public/generated/examples/**`;
- `.generated/**`;
- `content/docs/reference/**`;
- `public/api/**`.

The Pages workflow rebuilds them from repository source.
