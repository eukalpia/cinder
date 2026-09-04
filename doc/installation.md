# Installation

Cinder 1.0 requires Dart 3.9 or later. The repository checks the latest patch
of the 3.9 line and Dart 3.12 on Linux, macOS, and Windows.

## Core from Git

```yaml
dependencies:
  cinder:
    git:
      url: https://github.com/eukalpia/cinder.git
      ref: main
```

For reproducible application builds, replace `main` with a published tag or a
commit hash that has passed the repository checks.

## Integration packages before pub.dev publication

Integration package manifests retain hosted version constraints for eventual
pub.dev publication. Until those versions are published, the consuming app must
override each transitive Cinder package it uses. Library-local overrides only
apply while developing the library itself.

For example, this installs BLoC and its Cinder dependencies from the same tree:

```yaml
dependencies:
  cinder:
    git:
      url: https://github.com/eukalpia/cinder.git
      ref: main
  cinder_bloc:
    git:
      url: https://github.com/eukalpia/cinder.git
      ref: main
      path: packages/cinder_bloc

dependency_overrides:
  cinder:
    git:
      url: https://github.com/eukalpia/cinder.git
      ref: main
  cinder_nested:
    git:
      url: https://github.com/eukalpia/cinder.git
      ref: main
      path: packages/cinder_nested
  cinder_provider:
    git:
      url: https://github.com/eukalpia/cinder.git
      ref: main
      path: packages/cinder_provider
```

Set the same ref for every package. Riverpod and icon packs require only
the `cinder` override; Provider requires `cinder` and `cinder_nested`; BLoC requires
all three overrides shown above.

For local paths, use the same dependency/override structure with `path:` entries
pointing at your checkout and its `packages/` directories.

## CLI from this checkout

```sh
cd packages/cinder_cli
dart pub get
dart run cinder --help
```

The CLI's local core override is for developing this checkout. A GitHub release
does not publish any package to pub.dev automatically.
