# Cinder release stabilization implementation plan

> **For agentic workers:** Use superpowers:executing-plans task by task. Independent package, site, and runtime investigations are delegated using superpowers:dispatching-parallel-agents.

**Goal:** Repair reproducible code defects and installation/documentation discrepancies, establish executable release checks, and publish the verified changes to the supplied GitHub repository.

**Architecture:** Preserve Widget → Element → RenderObject and the existing public API. Reproduce failures before changing implementation; restore disabled regression coverage. Validate native, package, and browser entry points independently.

**Tech Stack:** Dart, Flutter compatibility wrapper, Next.js, Playwright, GitHub Actions.

**Spec:** User requests of 2026-09-05, CONTRIBUTING.md and doc/runtime-contracts.md. Apache 2.0 explicitly requested by the owner.

## Global constraints

- Repository: https://github.com/eukalpia/cinder.
- Work on release/1.0.0-stabilization; preserve upstream history and attribution.
- Do not infer stable readiness from skipped tests or analyzer success.
- Keep native terminal/manual checks and pub.dev publication status explicit.

## Task 1: Restore lifecycle contracts

**Files:** lib/src/foundation/{cancellation,resource_scope}.dart; lib/src/framework/{binding,build_owner,stateful_widget}.dart; lib/src/binding/terminal_binding.dart; test/foundation; test/binding.

- [x] Add regressions for concurrent disposal waiting, nested root disposal, backend cleanup, and disposed State resource access.
- [x] Observe failing tests with `dart test test/foundation test/binding`.
- [x] Fix resource ownership and traversal at the failing boundaries, preserving cleanup after errors.
- [x] Re-run lifecycle tests and investigate disabled error-recovery tests.

## Task 2: Repair disabled UI regressions

**Files:** test/layout/listview*; test/regression/listview_dynamic_add_bug_test.dart; test/input/{keyboard_navigation,navigation_demo}_test.dart; test/components/{rich_text,markdown_text}_test.dart; corresponding lib/src/components and navigation implementation.

- [x] Reproduce with `dart test --run-skipped test/layout test/input test/components test/regression test/process`: 15 failures.
- [x] Distinguish invalid fixtures from implementation defects without weakening the intended behavior assertions.
- [x] Fix failures, add focused edge cases for changed behavior, and remove resolved skips.
- [x] Run the complete root suite including skipped tests.

## Task 3: Validate package installation and CLI

**Files:** packages/cinder_{cli,provider,nested,bloc,riverpod,lucide,material_icons}.

- [x] Correct CLI dependencies and executable metadata; reproduce empty-log one-shot hang through a real WebSocket fixture.
- [x] Run dependency resolution, strict analysis, tests, and CLI executable smoke checks.
- [x] Verify external-consumer installation independently of local dependency overrides.

## Task 4: Repair browser/documentation delivery

**Files:** docs-site and packages/cinder_web, root README.md and CONTRIBUTING.md.

- [x] Run npm ci, lint, typecheck, export build, route verification and browser tests.
- [x] Repair compilation/runtime defects and align the /cinder deployment base path.
- [x] Keep compatibility modes truthful and verify generated examples.

## Task 5: Establish repeatable release validation

**Files:** .github/workflows, tool, justfile, pubspec.yaml, melos.yaml, LICENSE, NOTICE.md, THIRD_PARTY_LICENSES, doc/release.md.

- [x] Apply Apache-2.0 and preserve original third-party licenses.
- [x] Determine and test the actual minimum SDK and latest stable; correct metadata.
- [x] Replace unsafe partial version/tag mutations with explicit validation and documented release steps.
- [x] Add CI for native OS matrix, package suites, release packaging, browser export and deterministic renderer performance contracts.
- [ ] Review final diff; run release checks, push branch, inspect remote CI, integrate verified work and publish an appropriately labeled GitHub release.
