[![CI](https://github.com/norbert515/cinder/actions/workflows/ci.yml/badge.svg)](https://github.com/norbert515/cinder/actions/workflows/ci.yml)
[![Pub Version](https://img.shields.io/pub/v/cinder)](https://pub.dev/packages/cinder)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Website](https://img.shields.io/badge/web-cinder.dev-blue)](https://cinder.dev)
[![Documentation](https://img.shields.io/badge/docs-docs.cinder.dev-blue)](https://github.com/eukalpia/cinder)

<p align="center">
<a href="https://cinder.dev"><strong>Website</strong></a> |
<a href="https://github.com/eukalpia/cinder"><strong>Docs</strong></a> |
<a href="https://pub.dev/packages/cinder"><strong>pub.dev</strong></a> |
<a href="#quick-start"><strong>Quick Start</strong></a>
</p>

**If you know Flutter, you know Cinder.** Build terminal UIs with the same patterns—`StatefulWidget`, `setState()`, `Column`, `Row`, and hot reload.

![Cinder Demo](doc/assets/demo.gif)


## Installation

```yaml
dependencies:
  cinder: ^0.8.0
```

## Quick Start

```dart
import 'package:cinder/cinder.dart';

void main() {
  runApp(const Counter());
}

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Focusable(
      focused: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.space) {
          setState(() => _count++);
          return true;
        }
        return false;
      },
      child: Center(
        child: Text('Count: $_count'),
      ),
    );
  }
}
```

Run with hot reload:

```bash
dart --enable-vm-service your_app.dart
```

## Testing

Test your TUI components just like Flutter widgets:

```dart
await testCinder('counter test', (tester) async {
  await tester.pumpComponent(Counter());
  await tester.sendKey(LogicalKey.space);

  expect(tester.terminalState, containsText('Count: 1'));
});
```

## Documentation

See the [full documentation](https://github.com/eukalpia/cinder) for guides on components, state management, testing, and more.

## Community

### Packages

| Package | Description |
|---------|-------------|
| [cinder_bloc](https://pub.dev/packages/cinder_bloc) | Bloc state management for Cinder |
| [cinder_lints](https://pub.dev/packages/cinder_lints) | IDE assists — wrap with, swap, move, convert to stateful/stateless |

### Built with Cinder

| Project | Description |
|---------|-------------|
| [vide_cli](https://github.com/Norbert515/vide_cli) | Multi-agent coding IDE for the terminal |
| [cinder_3d](https://github.com/eukalpia/cinder_3d) | Experimental 3D renderer for the terminal |
| [cow](https://github.com/jolexxa/cow) | Local LLM chat client powered by llama.cpp |
| [snake](https://github.com/mrgnhnt96/snake) | Classic Snake for the command line |
| [minesweeper](https://github.com/mrgnhnt96/minesweeper) | Classic Minesweeper for the command line |
| [simutil](https://github.com/dungngminh/simutil) | Quick launch iOS simulators / Android emulators and more |

> Built something with Cinder? [Open an issue](https://github.com/norbert515/cinder/issues) to get it listed here!

## Contributing

### Git Hooks

We use [hooksman](https://pub.dev/packages/hooksman) to manage git hooks. To install the hooks, run:

```bash
dart run hooksman
```

## License

MIT
