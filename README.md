<div align="center">

# Cinder

**A Flutter-style terminal UI framework for Dart.**

Build interactive terminal applications with familiar widgets, stateful lifecycles,
focus traversal, navigation, animation, testing, and first-party state-management
integrations — without bringing Flutter or Node.js into your CLI runtime.

[![CI](https://github.com/eukalpia/cinder/actions/workflows/ci.yml/badge.svg)](https://github.com/eukalpia/cinder/actions/workflows/ci.yml)
[![Benchmark](https://github.com/eukalpia/cinder/actions/workflows/benchmark.yml/badge.svg)](https://github.com/eukalpia/cinder/actions/workflows/benchmark.yml)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.5-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Quick start](#quick-start) · [Focus](#focus-and-keyboard-input) · [State management](#state-management) · [Testing](#testing) · [Architecture](#architecture)

</div>

> [!IMPORTANT]
> Cinder `1.0.0-dev.1` is a breaking development line. The legacy Nocterm
> `Component`, `App`, `Frame`, and manual `TextField(focused: ...)` APIs are not
> retained.

## Why Cinder?

Cinder brings Flutter's declarative programming model to terminal applications:

- immutable `Widget` configurations;
- persistent `Element` instances;
- `StatelessWidget`, `StatefulWidget`, and `State<T>`;
- `BuildContext`-based dependency lookup;
- render-object layout and painting;
- frame scheduling and coalesced rebuilds;
- keyboard, mouse, gestures, focus, selection, and navigation;
- deterministic widget tests with a virtual terminal;
- Provider, Riverpod, and BLoC integrations.

A Flutter developer should recognize the core programming model immediately.
Terminal-specific concepts still matter — cells instead of pixels, keyboard-first
interaction, terminal capabilities, and alternate-screen behavior — but the
framework itself does not require learning a completely different UI paradigm.

## Project status

The current development line is **Cinder 1.0**.

| Area | Status |
| --- | --- |
| Flutter-style widget and element API | Available |
| Stateful lifecycle and `setState` | Available |
| Render-object layout and painting | Available |
| Keyboard, mouse, gestures, and selection | Available |
| `FocusNode` / `FocusManager` traversal | Available |
| `TextField` with `focusNode` and `autofocus` | Available |
| Provider integration | Available |
| Riverpod 3 integration | Available |
| BLoC integration | Available |
| Widget testing utilities | Available |
| Renderer V2 dirty-region pipeline | Planned |
| Stable `1.0.0` release | Planned |

## Installation

Until the stable packages are published, depend on the repository directly:

```yaml
dependencies:
  cinder:
    git:
      url: https://github.com/eukalpia/cinder.git
      ref: main
```

Then install dependencies:

```bash
dart pub get
```

For framework development:

```bash
git clone https://github.com/eukalpia/cinder.git
cd cinder
dart pub get
```

## Quick start

```dart
import 'package:cinder/cinder.dart';

void main() {
  runApp(const CounterApp());
}

class CounterApp extends StatefulWidget {
  const CounterApp({super.key});

  @override
  State<CounterApp> createState() => _CounterAppState();
}

class _CounterAppState extends State<CounterApp> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.space) {
          setState(() => count++);
          return true;
        }
        return false;
      },
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Press Space to increment'),
            Text('Count: $count'),
          ],
        ),
      ),
    );
  }
}
```

Run the application:

```bash
dart run bin/main.dart
```

## Core programming model

### Stateless widgets

```dart
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      child: Text(label),
    );
  }
}
```

### Stateful widgets

```dart
class Toggle extends StatefulWidget {
  const Toggle({super.key});

  @override
  State<Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<Toggle> {
  bool enabled = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.enter) {
          setState(() => enabled = !enabled);
          return true;
        }
        return false;
      },
      child: Text(enabled ? 'Enabled' : 'Disabled'),
    );
  }
}
```

Cinder supports the familiar lifecycle methods:

- `initState()`
- `didChangeDependencies()`
- `didUpdateWidget()`
- `deactivate()`
- `activate()`
- `dispose()`
- `reassemble()`

## Focus and keyboard input

Cinder uses a real focus tree rather than coordinating interactive widgets with
boolean flags.

```dart
class SearchBox extends StatefulWidget {
  const SearchBox({super.key});

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final focusNode = FocusNode(debugLabel: 'Search field');
  final controller = TextEditingController();

  @override
  void dispose() {
    focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      placeholder: 'Search…',
      onSubmitted: (value) {
        // Execute the search.
      },
    );
  }
}
```

Available focus primitives include:

- `FocusManager.instance.primaryFocus`
- `FocusNode.requestFocus()` and `unfocus()`
- `FocusNode.nextFocus()` and `previousFocus()`
- `FocusScope` and `FocusScopeNode`
- autofocus
- Tab and Shift+Tab traversal
- `skipTraversal`
- `canRequestFocus`
- descendant focus and traversal controls

## Layout and widgets

Cinder includes terminal-oriented equivalents of familiar Flutter building
blocks:

- `Row`, `Column`, `Stack`, `Center`, `Container`, and `Spacer`;
- text, rich text, Markdown, ASCII text, and selection widgets;
- `ListView`, `SingleChildScrollView`, scroll controllers, and scrollbars;
- `TextField`, keyboard listeners, focus scopes, and modal barriers;
- overlays, routes, navigator observers, and navigation;
- mouse regions, gesture detectors, taps, and long presses;
- progress indicators, dividers, clipping, themes, and debug overlays;
- terminal image protocols, xterm, and PTY-oriented components.

Browse [`example/`](example/) for runnable applications and focused demos.

## State management

The monorepo contains first-party integrations:

| Package | Purpose | Upstream dependency |
| --- | --- | --- |
| `cinder_nested` | Composable single-child widget infrastructure | — |
| `cinder_provider` | Provider-style dependency injection and state | Cinder native |
| `cinder_riverpod` | Riverpod containers, watches, listeners, overrides, refresh, and invalidation | Riverpod `3.3.2` |
| `cinder_bloc` | BLoC-style providers, builders, listeners, consumers, selectors, and context extensions | BLoC `9.2.1` |

During monorepo development, reference packages by path:

```yaml
dependencies:
  cinder:
    path: ../cinder
  cinder_bloc:
    path: ../cinder/packages/cinder_bloc
```

### BLoC

```dart
BlocProvider(
  create: (_) => CounterCubit(),
  child: BlocBuilder<CounterCubit, int>(
    builder: (context, count) => Text('Count: $count'),
  ),
)
```

### Riverpod

```dart
final counterProvider = StateProvider<int>((ref) => 0);

ProviderScope(
  child: Builder(
    builder: (context) {
      final count = context.watch(counterProvider);
      return Text('Count: $count');
    },
  ),
)
```

### Provider

```dart
Provider<ApiClient>(
  create: (_) => ApiClient(),
  child: Builder(
    builder: (context) {
      final client = context.read<ApiClient>();
      return Text(client.status);
    },
  ),
)
```

## Animation and scheduling

Cinder provides a frame scheduler and Flutter-style animation primitives:

- `Ticker` and ticker providers;
- `Animation<T>` and `AnimationController`;
- `Tween`, curves, and chained animatables;
- `AnimatedWidget`, `AnimatedBuilder`, and `ListenableBuilder`;
- transient, persistent, and post-frame callbacks;
- configurable frame-rate limiting.

```dart
SchedulerBinding.instance.setTargetFps(60);
```

## Testing

Cinder tests render into an in-memory terminal, so keyboard interaction and
screen output can be verified deterministically.

```dart
import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

void main() {
  test('counter increments', () async {
    await testCinder('counter', (tester) async {
      await tester.pumpWidget(const CounterApp());
      await tester.sendKey(LogicalKey.space);

      expect(tester.terminalState, containsText('Count: 1'));
    });
  });
}
```

Useful tester APIs include:

- `pumpWidget()`
- `pump()` and `pumpAndSettle()`
- `sendKeyEvent()`, `sendKey()`, and `enterText()`
- mouse press, release, hover, movement, and tap helpers
- terminal snapshots and text matchers
- widget and state lookup

Run the root suite:

```bash
dart test
```

Run formatting and analysis:

```bash
dart format --output=none --set-exit-if-changed lib test example benchmark packages
dart analyze lib test example benchmark
```

## Architecture

```text
Widget tree
    ↓
Element tree
    ↓
RenderObject tree
    ↓
Layout
    ↓
Paint
    ↓
Terminal buffer
    ↓
Differential terminal output
```

Repository layout:

```text
cinder/
├── lib/
│   └── src/
│       ├── binding/         # Application, scheduler, and terminal bindings
│       ├── framework/       # Widgets, elements, state, and render-object glue
│       ├── rendering/       # Layout, painting, hit testing, and diagnostics
│       ├── components/      # Terminal UI widgets
│       ├── animation/       # Tickers, controllers, tweens, and builders
│       ├── navigation/      # Navigator, routes, overlays, and observers
│       ├── gestures/        # Pointer and gesture recognition
│       └── test/            # Virtual terminal test infrastructure
├── packages/
│   ├── cinder_nested/
│   ├── cinder_provider/
│   ├── cinder_riverpod/
│   └── cinder_bloc/
├── example/
├── test/
├── benchmark/
└── docs-site/
```

## Branch model

Cinder uses three long-lived branches:

| Branch | Role |
| --- | --- |
| `dev` | Active development and feature integration |
| `test` | Release-candidate validation and stabilization |
| `main` | Reviewed, tested, publishable project state |

Promotion flow:

```text
feature/* → dev → test → main
```

Direct feature work should not target `main`.

## Migration from Nocterm

Cinder is an independent continuation of the Nocterm codebase and intentionally
does not include a legacy compatibility layer.

```text
package:nocterm/nocterm.dart  → package:cinder/cinder.dart
Component                     → Widget
StatelessComponent            → StatelessWidget
StatefulComponent             → StatefulWidget
InheritedComponent            → InheritedWidget
TextField(focused: ...)       → TextField(focusNode: ..., autofocus: ...)
```

Applications should migrate directly to the new API instead of mixing runtimes
or maintaining aliases.

## Performance

Benchmarks live in [`benchmark/`](benchmark/) and run in GitHub Actions. Cinder
already coalesces repeated state changes and input events into scheduled frames.

The planned Renderer V2 will focus on:

- reusable flat front/back buffers;
- dirty-region painting;
- repaint boundaries and cached layers;
- row-span output diffs;
- terminal scroll-region optimization;
- synchronized output where supported.

Performance claims should always be tied to reproducible workloads, viewport
sizes, terminals, and benchmark configurations.

## Roadmap

- [x] Flutter-style widget vocabulary
- [x] remove the parallel legacy runtime
- [x] Provider integration
- [x] Riverpod 3 integration
- [x] BLoC integration
- [x] `FocusManager`, `FocusNode`, and traversal
- [x] migrate `TextField` to focus nodes
- [ ] Renderer V2
- [ ] broader production widget kit
- [ ] semantics and non-interactive output mode
- [ ] stable `1.0.0` release

## Contributing

1. Create a feature or fix branch from `dev`.
2. Add or update tests for behavioral changes.
3. Run formatting, analyzer, tests, and relevant benchmarks.
4. Open a pull request into `dev`.
5. Promote validated changes through `test` before `main`.

Install repository-managed Git hooks with:

```bash
dart run hooksman
```

Keep public APIs Flutter-like where appropriate for a terminal environment, and
document deliberate differences.

## License and attribution

Cinder is distributed under the [MIT License](LICENSE).

The project is derived from Nocterm. Original copyright and fork attribution are
preserved in [`NOTICE.md`](NOTICE.md), the license files, and repository history.
