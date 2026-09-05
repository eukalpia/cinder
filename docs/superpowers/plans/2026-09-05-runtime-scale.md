# Runtime scale implementation plan

> **For agentic workers:** Use superpowers:executing-plans and independent-domain
> delegation through superpowers:dispatching-parallel-agents. Check each deliverable
> before integration.

**Goal:** Improve sustained-load correctness and resource bounds, broaden comparison,
and ship verified changes with reproducible evidence.

**Architecture:** Optional output-drain capability controls frame production;
bounded input and process histories control retention. Native process transport,
comparison tooling, and the reference application are independent work streams.

**Tech Stack:** Dart 3.9.4/3.13.3, existing FFI, Python PTY tooling, native CI,
Rust/C++/Python/JavaScript/Go comparison adapters.

**Spec:** ../specs/2026-09-05-runtime-scale-design.md

## Global constraints

Keep the public Dart framework and Apache-2.0/upstream notices. Preserve RC2 tags
and evidence. Do not run compilation or tests during final timed comparisons.
Do not infer a global ranking from selected workloads on one machine.

## Runtime flow control (root)

- [x] Add a blocked-output regression backend in test/binding; assert one in-flight
      output batch, latest-state rendering after drain, responsive input, cleanup.
- [x] Add optional TerminalOutputDrain in terminal_backend.dart; implement native
      stdout/socket draining and scheduler gating in terminal_binding.dart.
- [x] Verify errors and completion after shutdown cannot restart the binding.
- [x] Replace input prefix shifts with bounded byte storage; verify burst ordering,
      split Unicode/escape input, parser limits and linear consumption cost.
- [x] Measure and fix additional resource retention only after reproduction.

## Native process transport (native_pty worker)

- [x] Reproduce child window size and live resize failures using actual child output.
- [x] Implement native Unix PTY / Windows ConPTY with lifecycle and quoting tests.
- [x] Bound PtyController partial and complete output storage and eviction cost.
- [x] Validate supported SDKs; update transport documentation and notices if needed.

## Comparison suite (competitor_suite worker)

- [x] Add pinned Ratatui, FTXUI, Textual adapters and preparation metadata.
- [x] Add shared data-driven state/actions and exact visible-state validation.
- [x] Test driver/config validation; correctness-smoke all adapters before timing.
- [x] Add independent 4 ms / 20 ms arrivals with coalesced state visibility,
      shared clocks, deadlines, exact final-state verification and send lateness.
- [ ] Prepare clean source binaries, run serial trials, preserve raw output/results.

## Reference and sustained validation (scale_reference worker)

- [x] Build example/scale_monitor.dart with large data, virtualized viewport,
      search/selection/Unicode, bounded background work and deterministic disposal.
- [x] Add integration tests for visible work bounds and failure/restart behavior.
- [x] Provide benchmark/runtime_scale automation and doc/scale-monitor.md.
- [x] Run sustained AOT stress and separate diagnostic heap attribution.
      Preserve distinct source identities: two hours on the original candidate,
      twenty minutes on 0f20f0c, and sixty seconds on e72fc0c; do not label the
      older long runs as final-release runs.

## Integration (root)

- [ ] Review each independent deliverable and run targeted/full required checks.
- [ ] Run quiet, serial performance experiments and sustained-load verification.
- [ ] Document measurements, regressions, limits, commands and source identities.
- [ ] Commit/push, review PR, check all supported platforms and native archives,
      integrate and publish the verified release evidence.
