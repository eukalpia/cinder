# Application platform

Cinder's application layer standardizes commands, controls, large data views,
semantics, and diagnostics on top of the Widget/Element/RenderObject runtime.

## Actions, shortcuts, and commands

`Intent` describes what the user wants to do. `Action` performs it. `Shortcuts`
converts keyboard input into intents, while `Command` provides metadata shared
by command palettes, menus, and toolbars.

```dart
Actions(
  actions: <Type, Action<dynamic>>{
    SaveIntent: CallbackAction<SaveIntent>(
      onInvoke: (_) => save(),
    ),
  },
  child: Shortcuts(
    shortcuts: <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKey.keyS, control: true):
          const SaveIntent(),
    },
    child: const Editor(),
  ),
)
```

`CommandPalette` searches command labels, identifiers, descriptions, categories,
and keywords, then dispatches the selected intent through the nearest action
scope.

## Shared widget states

Interactive components resolve styling from a shared state vocabulary:

- hovered;
- focused;
- pressed;
- dragged;
- selected;
- disabled;
- error.

Use `WidgetStateProperty.resolveWith` or `WidgetStateMapper` to define one style
contract instead of duplicating state logic in every component.

## Production controls

The application package includes:

- `Button` and `Button.text`;
- `Checkbox` and `Switch`;
- `TabBar` and `Tabs`;
- `Menu`;
- `Dialog` and `AlertDialog`;
- `Tooltip`;
- `StatusBadge`;
- `EmptyState`, `ErrorState`, and `Skeleton`.

Controls support focus traversal, Enter/Space activation, pointer input,
disabled states, themes, and semantic metadata.

## Virtualized data views

`VirtualizedDataTable<T>` supports typed columns, sorting, stable selection,
keyboard navigation, and lazy row creation. `TreeView<T>` flattens only expanded
branches and renders visible rows through the same lazy viewport.

Neither component creates one Element for every item in a large dataset.

## Semantics and non-interactive representations

`Semantics` annotates the render tree with roles, labels, values, and states.
`SemanticsSnapshot` can export the mounted application as plain text or JSON.
This gives CI systems, scripts, and accessibility tooling a stable description
that does not depend on ANSI output. `renderPlainWidget` renders an ordinary
Widget tree in memory without enabling raw mode, alternate screen, mouse tracking,
or terminal control sequences.

```dart
final snapshot = SemanticsSnapshot.capture();
stdout.writeln(snapshot.toPlainText());
stdout.writeln(snapshot.toJsonString(pretty: true));

final result = await renderPlainWidget(
  const StatusScreen(),
  size: const Size(80, 24),
);
stdout.writeln(result.text);
```

Applications can expose this through `--plain` and serialize
`PlainOutputResult.toJson()` for `--json`.

## Diagnostics

`CinderDiagnostics.capture()` records:

- Widget and Element structure;
- RenderObject structure and dirty flags;
- focus tree and primary focus;
- semantics tree;
- differential renderer metrics when a terminal binding is active.

The result is serializable and can power an external inspector without changing
production rendering semantics.
