# Build and distribute native applications

`cinder build` compiles a Dart entry point into a native executable, with debugging
information saved separately by default. Build on macOS, Windows, or Linux with
the Dart SDK installed. The resulting application includes the Dart runtime and
does not require an SDK on the destination machine. Applications using additional
native libraries still need those libraries. See Dart's
[executable format](https://dart.dev/tools/dart-compile#exe).

## Build your application

Install the CLI from a Cinder checkout:

```sh
git clone https://github.com/eukalpia/cinder.git
dart pub global activate --source path cinder/packages/cinder_cli
```

Keep that checkout while using this installation. If `cinder` is not on your
`PATH`, use `dart pub global run cinder_cli:cinder_cli` in its place. Dart documents
the platform-specific [Pub executable path](https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path).

From your application's directory:

```sh
dart pub get
cinder build bin/main.dart
```

Without an entry argument, Cinder looks for `bin/<pubspec-name>.dart`, followed by
`bin/main.dart`. Otherwise, supply an entry explicitly. The default output is
`build/cinder/<os>-<arch>/<pubspec-name>` with `.exe` appended on Windows.

Choose an output filename with `--output` or `-o`:

```sh
cinder build bin/main.dart --output build/my-app
```

On Windows, use `--output build/my-app.exe`. This creates the executable and
`build/symbols/my-app.debug` (or `my-app.exe.debug`). Keep the matching symbols
with your release records for diagnosing crashes. `--no-split-debug-info` keeps
debugging information in the executable instead. Cinder creates missing output
directories.

The standalone Cinder CLI distributed by this repository can run `--help`
without an SDK; its build and development commands require Dart on `PATH`.
Builds accept executable version-manager shims on `PATH`. Set `DART_SDK` to the
SDK root directory to select a specific SDK explicitly.

## Select a platform

By default, the target matches the installed Dart SDK. These are the supported
build relationships:

| Target | Build host |
| --- | --- |
| macOS arm64 | macOS with an arm64 Dart SDK |
| macOS x64 | macOS with an x64 Dart SDK |
| Windows x64 | Windows with an x64 Dart SDK |
| Linux x64, arm64, arm, or riscv64 | A supported 64-bit Linux, macOS, or Windows host |

For example, build a Linux arm64 executable from a Mac:

```sh
cinder build bin/main.dart --target-os linux --target-arch arm64 --output build/linux-arm64/my-app
```

Cinder follows Dart's [Linux cross-compilation support](https://dart.dev/tools/dart-compile#cross-compilation).
Cross-compilation may download additional SDK tools. macOS and Windows targets
require a matching host OS and SDK architecture; use CI runners for those builds.
Linux cross-compilation does not execute the result or verify the destination's
system libraries. Test the executable on its target system before distributing it.

`cinder build` currently wraps `dart compile exe`. Packages requiring native build
hooks need Dart's [native asset build workflow](https://dart.dev/tools/dart-build);
this command does not bundle hook-produced libraries.

## Build your app on GitHub Actions

Save this as `.github/workflows/native.yml` in your application. Set `APP_ENTRY`
to your entry point. It builds on three native runners and uploads an application
archive and a separate symbol archive for each platform. The CLI checkout uses
`main`; pin `ref` to a reviewed Cinder commit or release containing `cinder build`
for reproducible releases.

```yaml
name: Native application
on:
  push:
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - runner: ubuntu-latest
            target: linux-x64
            arch: x64
            extension: ''
          - runner: windows-latest
            target: windows-x64
            arch: x64
            extension: '.exe'
          - runner: macos-15
            target: macos-arm64
            arch: arm64
            extension: ''
    runs-on: ${{ matrix.runner }}
    env:
      APP_ENTRY: bin/main.dart
      TARGET: ${{ matrix.target }}
      EXE_EXTENSION: ${{ matrix.extension }}
    defaults:
      run:
        shell: bash
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - uses: actions/checkout@v4
        with:
          repository: eukalpia/cinder
          ref: main
          path: .cinder-cli
          persist-credentials: false
      - uses: dart-lang/setup-dart@v1
        with:
          sdk: 3.13.3
          architecture: ${{ matrix.arch }}
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - run: dart pub global activate --source path .cinder-cli/packages/cinder_cli
      - run: dart pub get
      - run: >-
          dart pub global run cinder_cli:cinder_cli build "$APP_ENTRY"
          --output "build/native/app$EXE_EXTENSION"
      - name: Archive application and symbols separately
        shell: python
        run: |
          import hashlib
          import os
          from pathlib import Path
          import shutil
          import zipfile
          output = Path('build/packages')
          output.mkdir(parents=True, exist_ok=True)
          name = 'app-' + os.environ['TARGET']
          binary = Path('build/native/app' + os.environ['EXE_EXTENSION'])
          with zipfile.ZipFile(output / (name + '.zip'), 'w', zipfile.ZIP_DEFLATED) as archive:
              archive.write(binary, binary.name)
          shutil.make_archive(str(output / (name + '-symbols')), 'zip', 'build/native/symbols')
          for archive in output.glob('*.zip'):
              digest = hashlib.sha256(archive.read_bytes()).hexdigest()
              archive.with_suffix('.zip.sha256').write_text(digest + '  ' + archive.name + '\n')
      - uses: actions/upload-artifact@v4
        with:
          name: app-${{ matrix.target }}
          path: build/packages/*
          if-no-files-found: error
          compression-level: 0
```

The inner ZIP files retain Unix executable modes when extracted with a compatible
archive tool. Add your application's required license notices and runtime assets
to its archive before publishing. This starter workflow compiles your application;
add its own tests or terminal smoke checks.

## This repository's native distributions

The [native build workflow](../.github/workflows/build.yml) builds the Cinder CLI
and `example/task_manager_demo.dart` with Dart 3.13.3:

| Platform | GitHub runner |
| --- | --- |
| Linux x64 | `ubuntu-latest` |
| Linux arm64 | `ubuntu-24.04-arm` |
| Windows x64 | `windows-latest` |
| macOS arm64 | `macos-15` |
| macOS x64 | `macos-15-intel` |

These labels follow GitHub's [hosted runner catalogue](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
Each build runs the standalone CLI's `--help`. POSIX builds also exercise demo
rendering, keyboard input, quit, and terminal restoration in a PTY. Windows builds
compile the demo and run the CLI; the workflow does not automate a Windows
interactive terminal test.

PRs, pushes to `main`, and manual runs produce downloadable Actions artifacts.
Publishing a GitHub release runs the same matrix and attaches assets only after
all five builds succeed and the event tag is confirmed to point to the built
commit. An existing identical asset is retained; different bytes under the same
name cause failure instead of replacement.

Each platform produces four files, using the root `pubspec.yaml` version:

```text
cinder-<version>-<os>-<arch>.tar.gz
cinder-<version>-<os>-<arch>.tar.gz.sha256
cinder-<version>-<os>-<arch>-symbols.tar.gz
cinder-<version>-<os>-<arch>-symbols.tar.gz.sha256
```

Windows uses `.zip` instead of `.tar.gz`. The runtime archive contains `bin/cinder`
and `bin/cinder-demo` (`.exe` on Windows). Each archive includes `LICENSE`, `NOTICE`,
`THIRD_PARTY_LICENSES`, and a manifest recording the source commit, Dart version,
platform, file sizes, SHA256 digests, and modes. Symbol files stay in the separate
archive. The archive's `THIRD_PARTY_LICENSES` preserves the repository notices and
adds the Dart SDK license and the union of both programs' resolved runtime
dependency licenses. It also includes the SDK's embedded native library notices
from a versioned [source and checksum inventory](../tool/licenses/dart-3.13.3/README.md).
Dependency names, versions, and license hashes are recorded
in the manifest. Dependencies used only by development tools are excluded; the
inventory conservatively includes runtime dependencies removed by tree shaking.
Missing license files fail packaging. These are command-line archives, without installer packaging or release
code signing.

Verify a downloaded archive with `sha256sum -c <archive>.sha256` on Linux or
`shasum -a 256 -c <archive>.sha256` on macOS. On Windows, compare
`Get-FileHash <archive>.zip -Algorithm SHA256` with its `.sha256` file. Extract the
archive and run `bin/cinder-demo` in your terminal.

To reproduce this repository's packaging locally, first build both programs and
their separate symbols as shown in the workflow, then run:

```sh
python tool/package_native.py build --target-os macos --target-arch arm64 --dart-version 3.13.3
python tool/package_native.py verify build/packages
```

Use your actual platform and SDK version; pass `--commit` with the source commit
when building outside Actions (where `GITHUB_SHA` supplies it). The packager uses
`dart` on `PATH` to read the resolved dependency graphs and SDK license; set
`--dart-executable` to the compiler path if necessary. It checks that the SDK
version matches `--dart-version`. The packager verifies archive and
payload checksums, required notices, symbol separation, and executable permissions
without extracting files. It refuses to overwrite an existing distribution;
choose another `--output` directory for a repeat build.

Changing the distribution SDK also requires updating its native runtime notice
bundle and source inventory under `tool/licenses/`. Packaging checks the bundle's
SDK version and SHA256 before including it.
