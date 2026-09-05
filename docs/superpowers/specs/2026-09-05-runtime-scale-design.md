# Runtime scale and comparative validation

The user approved this next phase after reviewing the performance strategy.
Continue the Dart implementation and retain the immutable RC2 measurements.
The deliverable is tested runtime improvements, a realistic reference application,
broader reproducible comparisons, and published evidence with explicit limits.

## Runtime

Use an optional backend output-drain capability so existing custom backends remain
source compatible. Native stdout uses its nonblocking sink. The frame scheduler
waits for the previous output batch to drain and coalesces intervening state changes;
it never discards ANSI diffs or queues whole rendered frames. Input and shutdown
remain available while the output consumer is slow. Test draining, errors,
resize, disposal, and rescheduling during frame callbacks.

Avoid shifting the entire pending input buffer per parsed event. Keep bounded byte
storage and incremental consumption, preserving split Unicode and escape parsing.
Validate actual operation counts or scaling separately from scheduler latency.
Bound retained PTY output by both lines and message storage, including unterminated
lines. Use real Unix PTY window sizing and Windows ConPTY through existing native
facilities, with child-process lifecycle and platform integration tests.

## Workloads and measurement

Add pinned Ratatui, FTXUI, and Textual adapters through normal public APIs. Keep the
old ASCII workloads identifiable and add a deterministic data-driven workload
with equivalent displayed state and actions. Record source, tools, locks, output,
CPU, RSS, and latency measurement boundaries. Separate uncapped or internal timing
from the existing capped closed-loop experiment.

A reference monitor exercises a large virtualized collection, Unicode, filtering,
selection, bounded background history, resizing, cancellation, and shutdown.
Provide automation for sustained stress and memory profiling. Profile VM/heap
separately from AOT process RSS; do not attribute all RSS to framework cells.

## Release gates

- Dart >=3.9.4; native macOS, Linux, Windows; existing web compilation retained.
- Existing public APIs remain compatible; new limits are documented.
- Apache-2.0 plus all required upstream notices remain intact.
- Regression tests, strict analyzer, packages, benchmark correctness, native builds,
  and terminal restoration pass before integration.
- Timed comparisons run serially after builds/tests stop, with raw evidence.
- Report observed results, including losses. Twofold CPU advantage, minimum RSS,
  and global leadership are ambitions, not release promises or test assumptions.
- Physical terminal/font/IME behavior and code signing cannot be certified by CI.
