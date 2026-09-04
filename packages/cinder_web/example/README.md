# Cinder Web Interactive Demo

This is a comprehensive interactive demo showcasing the capabilities of cinder running in a web browser.

## Features

The demo includes 4 interactive tabs:

### 1. Dashboard Tab
- **Simulated Metrics**: Generated CPU, memory, network, and request values
- **System Monitor**: Animated progress bars using demonstration data
- **CPU History**: Sparkline chart displaying generated CPU samples
- **Activity Feed**: Demonstration activity entries

### 2. Widgets Tab
- **Interactive Counter**: Clickable +/- buttons to increment/decrement
- **Toggle Switch**: ON/OFF toggle with visual feedback
- **Selection List**: Click to select from multiple options
- **Text Styles**: Showcase of bold, italic, underline, dim, and colored text

### 3. Animation Tab
- **Spinners**: Three different animated loading spinners
- **Progress Bars**: Linear progress bar and bouncing progress indicator
- **Wave Animation**: Sine wave animation using block characters
- **Color Gradient**: Animated RGB gradient

### 4. About Tab
- Information about cinder and its features
- ASCII art borders
- Feature list

## Navigation

- **Arrow Keys (←→)**: Switch between tabs
- **Number Keys (1-4)**: Jump directly to a specific tab
- **Mouse**: Click on buttons, toggles, and selection items

## Implementation Highlights

- **Stateful Widgets**: Uses `StatefulWidget` and `State` with lifecycle methods
- **Timers**: Real-time updates via `Timer.periodic`
- **Keyboard Input**: `Focusable` widget with `onKeyEvent` handling
- **Mouse Input**: `GestureDetector` with `onTap` callbacks
- **Reactive UI**: `setState()` triggers rebuilds automatically
- **Styling**: Tokyo Night color theme with rich text formatting
- **Layout**: Flex layouts with Row, Column, and Expanded

## Code Structure

```
lib/main.dart
├── InteractiveDemo (main app with tab navigation)
├── DashboardTab (live metrics and monitoring)
├── WidgetsTab (interactive UI components)
├── AnimationTab (animated elements)
└── AboutTab (info panel)
```

## Running the Demo

To build and run this demo in the browser:

```bash
# From the example directory, build the guest for the Flutter host
dart pub get
dart compile js lib/main.dart -O2 -o ../web/app.js
cd ..
flutter pub get
flutter run -d chrome
```

The Flutter host renders the guest using the Dart `xterm` widget. Its bridge must
be initialized before the guest JavaScript loads; opening the compiled script
alone does not create a terminal. The same source is also available through the
documentation site's example catalogue.

## Technologies

- **Dart**: Programming language
- **cinder**: TUI framework (Flutter-like for terminals)
- **xterm**: Dart terminal emulator used by the Flutter host
- **ANSI escape codes**: Terminal formatting and colors
