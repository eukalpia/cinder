# Cinder performance comparison and optimization

User objective: maximize Cinder's performance and compare it against production TUI frameworks on Node.js, Bun, and Go. Minimize resident memory, installation size, and disk writes as well as CPU cost. Preserve the existing Dart widget API and release correctness gates. Avoid unbounded caches and record resource tradeoffs explicitly.

Baseline: Cinder commit 8964efee387c8f083dacaf5e2402f1a3e0b9e1db. Cross-framework comparisons compile both Cinder revisions with Dart 3.13.3 AOT; initial text operation measurements used Dart 3.12.0 AOT and are reported separately. Comparison candidates are Ink 7.1.1 on Node 24.20.0 LTS, OpenTUI core 0.5.10 on Bun 1.4.0 (including its native Zig renderer), and Bubble Tea 2.0.9 compiled with Go 1.27.1. Pin all dependency versions and record machine, OS, runtime flags, and commit IDs.

Use real persistent applications and the same visible workloads. Start with a 120-column by 40-row ASCII terminal surface: sparse cell updates, dense text updates, and scrolling text/table rows. Add Unicode/CJK/style cases to prevent an ASCII-only speedup from hiding regressions. Give each library its documented efficient rendering options. Validate resulting screen contents and output completion; submission of an update is not proof that it rendered.

Separate two measurement boundaries:

1. End-to-end input to completed ANSI output in a PTY, at identical 60 FPS limits where applicable. Record p50/p95/p99 latency, CPU time, memory, bytes written, and lost/coalesced updates. Terminal-emulator GPU/display latency is outside this measurement.
2. Renderer/build CPU cost without frame pacing, only where each library exposes comparable complete-frame execution and output. Otherwise publish the library's supported layer separately; do not rank partial rendering against complete application frames.

Run timed workloads serially after setup/compilation, with a common six-second terminal capability settling period, frame warmup, and repeated independent samples. Report uncertainty and raw results. Keep framework overhead, app data generation, and output-volume measurements explicit. No general claim of beating a runtime or every application follows from one benchmark.

Profile Cinder's existing AOT renderer/text/layout benchmarks first. Optimize measured hot paths with failing-before/passing-after correctness regressions, preserve Unicode/cell/style behavior, and add deterministic work/allocation bounds where possible. Re-run the same comparison with the baseline and optimized Cinder builds, then all release gates and hosted CI before integration.

The already verified release remains an immutable baseline. Optimization work uses a separate branch and produces its own reviewed changes and performance report.

The user also requested convenient macOS, Windows, and Linux builds. Add a
`cinder build` command that resolves an entry point and installed Dart compiler,
validates native and supported Linux cross targets, forwards compiler errors,
and separates debugging information by default. Keep the deployed executable
independent of an installed SDK. Publish verified native CLI/demo archives for
macOS arm64/x64, Linux arm64/x64, and Windows x64 after hosted builds pass, with
checksums, source metadata, and complete required notices. Preserve the existing
release tag and use a new release candidate for these changes.
