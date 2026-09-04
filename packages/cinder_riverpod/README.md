# cinder_riverpod

Riverpod support for cinder - A reactive caching and data-binding framework for terminal user interfaces.

## Features

- 🎯 **Full Riverpod Integration** - Use all Riverpod providers in your TUI apps
- 🔄 **Automatic Rebuilds** - Widgets rebuild automatically when providers change
- 📦 **State Management** - Manage complex state with providers
- 🔍 **Computed Values** - Create derived state with Provider
- ♻️ **Auto-Dispose** - Automatic cleanup of unused providers

## Installation

Add `cinder_riverpod` to your `pubspec.yaml`:

```yaml
dependencies:
  cinder_riverpod:
    path: packages/cinder_riverpod  # or from pub.dev when published
```

## Usage

### Basic Setup

Wrap your app with `ProviderScope`:

```dart
import 'package:cinder/cinder.dart';
import 'package:cinder_riverpod/cinder_riverpod.dart';

void main() {
  runApp(
    ProviderScope(
      child: MyApp(),
    ),
  );
}
```

### Creating Providers

```dart
// Simple provider
final greetingProvider = Provider<String>((ref) => 'Hello, World!');

// State provider for mutable state
final counterProvider = StateProvider<int>((ref) => 0);

// Computed provider
final doubledProvider = Provider<int>((ref) {
  final count = ref.watch(counterProvider);
  return count * 2;
});

// Notifier provider for mutable state
class Counter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

final counterNotifierProvider = NotifierProvider<Counter, int>(Counter.new);
```

### Using Providers in Widgets

```dart
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Watch - rebuilds when provider changes
    final greeting = context.watch(greetingProvider);
    final count = context.watch(counterProvider);
    
    return Column(
      children: [
        Text(greeting),
        Text('Count: $count'),
        // Read - doesn't rebuild
        Button(
          onPressed: () {
            // Modify state
            context.read(counterProvider.notifier).state++;
          },
          child: Text('Increment'),
        ),
      ],
    );
  }
}
```

### Listening to Changes

```dart
class ListenerWidget extends StatefulWidget {
  @override
  State<ListenerWidget> createState() => _ListenerWidgetState();
}

class _ListenerWidgetState extends State<ListenerWidget> {
  @override
  void initState() {
    super.initState();
    
    // Listen to provider changes
    context.listen(counterProvider, (previous, next) {
      print('Counter changed from $previous to $next');
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Text('Listening to changes...');
  }
}
```

### Provider Overrides

```dart
// Useful for testing or different configurations
ProviderScope(
  overrides: [
    counterProvider.overrideWith((ref) => 42),
  ],
  child: MyApp(),
)
```

## API Reference

### BuildContext Extensions

- `context.watch(provider)` - Read and subscribe to changes
- `context.read(provider)` - Read without subscribing
- `context.listen(provider, callback)` - Listen until the widget is removed; repeated calls replace its callback
- `context.subscribe(provider, callback)` - Create a subscription that the caller closes
- `context.refresh(provider)` - Refresh a provider
- `context.invalidate(provider)` - Invalidate a provider

### Supported Providers

All standard Riverpod providers are supported:
- `Provider`
- `StateProvider`
- `FutureProvider`
- `StreamProvider`
- `StateNotifierProvider`
- `NotifierProvider`
- `AsyncNotifierProvider`

## Example

See [counter_watch_demo.dart](example/counter_watch_demo.dart) for a keyboard-controlled counter demonstrating automatic rebuilds and derived state.

Run the example:

```bash
cd packages/cinder_riverpod
dart run example/counter_watch_demo.dart
```

## Testing

```bash
cd packages/cinder_riverpod
dart test
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

Same as cinder - see the main project for license details.
