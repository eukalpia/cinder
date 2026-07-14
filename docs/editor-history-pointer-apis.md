# Editor, anchored history, and pointer APIs

## TextField

`TextField` handles editor-owned shortcuts before application shortcuts. It supports undo/redo, word deletion, per-document drafts through `TextDraftStore`, and configurable submit behavior through `TextFieldSubmitMode`.

For a chat composer, use `TextFieldSubmitMode.enter` for Enter-to-send and Shift+Enter-to-insert-newline. Pass a stable chat ID as `draftKey` and share a `MemoryTextDraftStore` or application-specific persistent store.

## AnchoredListView

`AnchoredListView` addresses large, variable-height histories. Items are identified by stable IDs, measured extents survive render-object eviction, and the controller preserves anchors across prepend, append, and late media relayout. `AnchoredListController` can save and restore independent positions for multiple chats and jump directly to an item ID.

Application state remains the source of truth for message IDs and selection; the viewport only owns measurements and mounted render objects.

## Pointer and context menus

`GestureDetector` exposes secondary and middle taps, raw pointer button state, and button-aware drag callbacks. `ContextMenuRegion` opens on right click or Shift+F10. `MenuAnchor` inserts the menu into the nearest overlay and clamps its measured bounds to the viewport.
