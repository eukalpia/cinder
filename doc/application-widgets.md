# First-party application widgets

Cinder's application widget layer is designed for IDEs, AI agents, Git clients,
operations dashboards, chat applications, and other large terminal programs. The
widgets are exported by `package:cinder/cinder.dart` and use the same
`Widget`/`State`/controller patterns as the rest of Cinder.

All string values that may come from a model, process, file, repository, server,
or user are rendered through Cinder's terminal sanitization boundary. Interactive
controls remain trusted widget-tree actions; text that merely looks like a button
is never actionable.

## Foundation: the five primary widgets

### `VirtualListView`

`VirtualListView` is the default list for large data sets. It keeps only the
visible range plus cache extent mounted by delegating to Cinder's lazy list
renderer.

```dart
VirtualListView.builder(
  itemCount: messages.length,
  itemExtent: 3,
  cacheExtent: 8,
  itemBuilder: (context, index) => MessageCard(messages[index]),
)
```

Use `VirtualListView.separated` for dividers and `VirtualListView.infinite` when
the builder decides where an unbounded data source ends. `VirtualListController`
adds exact fixed-extent index navigation.

### `SplitView` and `ResizablePane`

```dart
SplitView(
  controller: SplitViewController(ratio: 0.28),
  minFirstExtent: 20,
  minSecondExtent: 40,
  first: const FileTree(nodes: files),
  second: const EditorWorkspace(),
)
```

The divider supports mouse drag, double-click reset, arrow-key resizing, and
minimum pane extents. Horizontal and vertical splits are supported.

### `TreeView`

`TreeView<T>` provides lazy visible-row construction, expansion state, selection,
keyboard navigation, activation, disabled nodes, custom leading widgets, and a
custom row builder.

```dart
final controller = TreeViewController<FileNode>();

TreeView<FileNode>(
  controller: controller,
  nodes: projectTree,
  autofocus: true,
  onActivated: openFile,
)
```

Arrow keys navigate and expand/collapse; Enter activates; Space toggles a branch.

### `DiffView`

`DiffView` parses unified diffs into files/hunks/lines and renders unified or
side-by-side layouts. The controller tracks the selected hunk and exposes
approve/reject callbacks suitable for agent review workflows.

```dart
DiffView.fromUnifiedDiff(
  patch,
  mode: DiffViewMode.sideBySide,
  onApproveHunk: approve,
  onRejectHunk: reject,
)
```

### `CommandPalette`

`CommandPalette` offers fuzzy search, keyboard selection, command categories,
shortcuts, enable/visibility predicates, and async execution.

```dart
CommandPalette(
  commands: [
    CommandPaletteItem(
      id: 'workspace.openFile',
      label: 'Open file',
      shortcut: 'Ctrl+P',
      onSelected: openFilePicker,
    ),
  ],
  onDismiss: closePalette,
)
```

## Navigation and windows

- `Tabs`, `TabBar`, and `TabsController`;
- `Drawer`;
- `Dialog` and `BottomSheet`;
- `Popover` and `Tooltip`;
- `ContextMenu` and `MenuBar`;
- `DropdownMenu`;
- `Toast`, `ToastController`, and severity levels;
- `NotificationCenter` and `NotificationCenterController`.

These components use focus scopes, overlays/stacks, real gesture hit regions, and
safe text rendering. Application data never defines executable callbacks.

## Data widgets

- `DataTable` for small data sets;
- `VirtualDataGrid` for large row sets;
- `SortableTable` with interactive sortable headers;
- `FilterableTable` with a controlled filter field;
- `PropertyInspector` with lifecycle-safe editable values;
- `Timeline`;
- `LogView` and `LogViewController`;
- `SearchableList`;
- `InfiniteList`.

The virtual grid allows fixed row extent, cache extent, row selection, keyboard
navigation, optional headers/dividers, and fixed or flexible column widths.

## AI and developer widgets

- `ChatView`, `ChatViewController`, and `StreamingMessage`;
- `ToolCallCard` and `ThinkingBlock`;
- `ApprovalDialog` with risk/scope/reversibility fields and real trusted actions;
- `DiffView`;
- `FileTree`;
- `CodeView`;
- `TerminalView`;
- `AgentStatus`;
- `ContextMeter` and `TokenUsageBar`;
- `TaskGraph`;
- `MarkdownView`.

### Streaming chat

`ChatViewController.appendDelta` batches model deltas to frame cadence instead of
notifying for every token:

```dart
final chat = ChatViewController(
  maxMessages: 10000,
  streamBatchInterval: const Duration(milliseconds: 16),
);

chat.add(const ChatMessage(
  id: 'answer',
  role: ChatRole.assistant,
  content: '',
  streaming: true,
));

modelStream.listen((delta) => chat.appendDelta('answer', delta));
```

`ChatView` uses a virtualized transcript and repaint boundaries around messages.
Model/tool content remains inert display data.

### Approvals

`ApprovalDialog` separates trusted control chrome from sanitized command/path
values. Only callbacks attached by application code can approve or reject a tool.
A model response containing `[Approve]`, box drawing, or a fake dialog has no hit
region and cannot trigger an action.

### Embedded terminal

`TerminalView` wraps `TerminalXterm`, whose PTY output is parsed into an internal
screen model. Host title, bell, clipboard, image, and private OSC effects remain
ignored unless an application explicitly adds a permission-gated policy.

## Forms and controls

- `Form`, `FormController`, and `FormField`;
- `Validation` and composable validators;
- `Autocomplete` and `TypeAhead`;
- `MultiSelect`;
- `Checkbox`, `Radio`, `Switch`, and `Slider`;
- `KeyRecorder`;
- `ShortcutEditor`.

Controllers own values, validation results, reset/submit behavior, and listener
lifetimes. Editable property and form text controllers are created once and
properly disposed, never allocated during every build.

## Performance rules

Application widgets follow these rules:

- large collections use lazy/virtual lists;
- fixed extents are preferred when known;
- streaming deltas are coalesced;
- static transcript/tool/diff regions use repaint boundaries;
- controllers notify only when observable state changes;
- visible text is sanitized before layout and again at cell/diff boundaries;
- no component writes ANSI or image protocol bytes directly;
- expensive filtering/parsing should be moved off the UI isolate for very large
  inputs and delivered as immutable results.

## Testing

`test/application/application_widgets_test.dart` covers virtualization, split
keyboard resizing, tree navigation, diff actions, palette execution, tabs,
notices, safe data grids, streaming chat, tool/approval surfaces, forms,
autocomplete, and shortcut recording.

Security-specific guarantees are covered in `test/security/` and documented in
[`security.md`](security.md).
