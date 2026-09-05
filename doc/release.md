# Release validation

The current version is **1.0.0-rc.2**. A release candidate makes the tested
implementation available while keeping the stable-release gates explicit.
A green test suite is evidence for its exercised cases, not a guarantee that
all terminal emulators, fonts, transports, or applications behave identically.

## Reproduce the automated checks

Use Dart 3.9 or newer. CI checks Dart 3.9.4 and 3.13.3 on Linux, macOS and Windows.
The format check uses Dart 3.13.3, matching the repository's formatter.

```sh
dart pub get
dart tool/check.dart
```

The runner performs strict analysis and tests of the core and every publishable
integration package, source formatting, deterministic renderer workload checks,
and a root package publication dry run. It excludes generated browser exports
and the optional Flutter wrapper. Each stage can also run separately:

```sh
dart tool/check.dart core
dart tool/check.dart packages
dart tool/check.dart benchmarks
dart tool/check.dart format package
dart run benchmark/benchmark.dart --ci
dart compile exe example/task_manager_demo.dart -o cinder-demo
python3 tool/terminal_smoke.py ./cinder-demo # Linux/macOS
dart tool/verify_git_installation.dart <pushed-commit-or-tag>
```

Renderer gates require one comparison/run for one damaged cell and one initial
paint plus 999 cache hits for 1,000 cached composites. Wall-clock benchmark
numbers are recorded separately because they depend on the machine.

For the documentation/browser runtime:

```sh
cd docs-site
npm ci
npm run lint
npm run typecheck
NEXT_PUBLIC_BASE_PATH=/cinder \
NEXT_PUBLIC_SITE_ORIGIN=https://eukalpia.github.io npm run build
NEXT_PUBLIC_BASE_PATH=/cinder npm run test:routes
npx playwright install chromium
NEXT_PUBLIC_BASE_PATH=/cinder npm run test:browser
npm audit
```

The site build compiles all catalogued examples, generates Dart API docs,
exports static routes, and fails on compiler errors. Browser tests exercise
runnable examples and explicitly identify adapters and sandboxes.

For the optional Flutter terminal wrapper:

```sh
cd packages/cinder_web
cd example
dart pub get
dart compile js lib/main.dart -o ../web/app.js
cd ..
flutter pub get
flutter analyze --fatal-infos
flutter build web
```

## Before declaring a stable release

Record the exact commit, toolchain versions, CI run links, and outcomes in the
GitHub release. Complete the runtime gates in [runtime-contracts.md](runtime-contracts.md),
including hands-on checks of the reference application on:

- Windows Terminal, a macOS terminal, and a Linux terminal;
- SSH and tmux sessions;
- a narrow viewport, repeated resize, Unicode/CJK/emoji, text selection/paste,
  dialog focus, scrolling, and interrupted shutdown;
- supported native image protocols and their Unicode fallback.

CI uses hosted runners and a browser emulator; it does not substitute for that
physical-terminal compatibility matrix. Note unavailable environments rather
than marking them as tested.

## Version and publication procedure

1. Change the root and publishable package versions and their Cinder dependency
   constraints together. Update changelogs and README status; regenerate the
   site's version/compatibility metadata with its normal build.
2. Run all checks and review the complete diff. Publish the branch and require
   the CI, Benchmark, Documentation site, Flutter wrapper, and Native distributions
   workflows to pass for that commit.
3. Merge only the reviewed commit into `main`; check that remote `main` contains
   it. Create a new annotated tag matching the root version. Never delete or
   force-move an existing release tag.
4. Create GitHub release notes with fixes, validation evidence, and limitations.
   Mark versions containing a prerelease suffix as GitHub prereleases.
5. Pub.dev publication is separate. Check package-name ownership and publication
   rights, then publish in dependency order: core, nested, provider, remaining
   integrations and CLI. Run each package's dry run first; confirm its matching
   dependencies are available before publication.

`just release` only runs validation. It never rewrites a subset of versions,
creates commits, deletes tags, pushes branches, or publishes packages.
