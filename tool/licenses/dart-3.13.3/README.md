# Dart 3.13.3 native runtime notices

`NOTICES` is a conservative union of original third-party licenses and
attribution notices for the Dart native runtime used in Cinder's macOS,
Windows, and Linux distributions. The archive packager appends it to the
repository notices, the Dart SDK's own license, and the resolved Pub runtime
dependency licenses. The top-level SDK license alone does not contain these
native dependency notices.

This inventory is pinned to Dart SDK commit
`1d1a730ef918d602aedafc939a4cf5940e7589ab` (`3.13.3`). Its
[DEPS file](https://github.com/dart-lang/sdk/blob/1d1a730ef918d602aedafc939a4cf5940e7589ab/DEPS)
supplies the component revisions. `manifest.json` records the original source
URLs, complete source hashes, exact notice selections, selected-content hashes,
and the final bundle hash. Complete upstream license files retain their original
contents, including their own notices for additional components.

| Components | Why included |
| --- | --- |
| BoringSSL, ICU and Unicode data, zlib | Direct dependencies of the SDK's `dart_executable` and `dart_io` build templates, including `dartaotruntime_product` |
| double-conversion | Direct dependency of `libdart`, including its AOT runtime configuration |
| V8 regular-expression implementation | Original V8 copyright statements in Dart's checked-in regexp sources and the upstream BSD terms |
| Perfetto protozero and base | Runtime dependency when `dart_support_perfetto` is enabled; the SDK's product AOT runtime can retain it |
| zlib Chromium, ARM, and Intel optimizations | The zlib build selects architecture-specific SIMD and optimized compression sources whose attribution extends the upstream zlib license |
| LLVM libc++, libc++abi, libc, and compiler-rt | Conservative coverage for SDK C/C++ runtime and compiler support configurations; referenced contributor lists are retained |
| Ryu and Microsoft floating-point conversions | Additional Boost attribution in libc++'s floating-point conversion implementation |
| Crashpad and mini-Chromium | Conservative coverage for the optional Windows SDK crash-reporting configuration |

The relevant build definitions are
[runtime/bin/BUILD.gn](https://github.com/dart-lang/sdk/blob/1d1a730ef918d602aedafc939a4cf5940e7589ab/runtime/bin/BUILD.gn),
[runtime/BUILD.gn](https://github.com/dart-lang/sdk/blob/1d1a730ef918d602aedafc939a4cf5940e7589ab/runtime/BUILD.gn),
[runtime/vm/BUILD.gn](https://github.com/dart-lang/sdk/blob/1d1a730ef918d602aedafc939a4cf5940e7589ab/runtime/vm/BUILD.gn),
[runtime/runtime_args.gni](https://github.com/dart-lang/sdk/blob/1d1a730ef918d602aedafc939a4cf5940e7589ab/runtime/runtime_args.gni),
and [tools/gn.py](https://github.com/dart-lang/sdk/blob/1d1a730ef918d602aedafc939a4cf5940e7589ab/tools/gn.py).
The zlib SIMD source headers reference Chromium's BSD terms; that license text
is preserved from the pinned Chromium `145.0.7632.26` tag, alongside the original
copyright statements from Dart's pinned zlib revision.
V8 attribution is taken directly from all 36 V8-marked regexp source headers in
the pinned Dart tree. The upstream V8 BSD license is retained at commit
`946ada6f5c08b1c0977666ca5462e886a9c194e2`; this identifies the license text source,
not a claim that Dart bundles that V8 engine revision.

This union intentionally retains optional components and upstream license
sections that may not apply to every binary. It does not assert that each
component is linked into each platform's executable. Operating-system libraries
that are not shipped in these archives are outside this inventory.

Verify the checked-in bundle and its selected source sections offline:

```sh
python tool/licenses/dart-3.13.3/verify_sources.py
```

To additionally retrieve the pinned originals and verify their hashes and
notice selections, run the same command with `--fetch`. This makes read-only
requests to the recorded official source URLs. Normal archive packaging uses
the checked-in bundle and needs no network access for these notices.

When updating Dart, review the new runtime build graph, DEPS revisions, and
component-specific license files and source headers before producing a new
versioned bundle. Updating just a version string or bundle checksum is
insufficient. The packager rejects a missing bundle or a version/hash mismatch.
