#!/usr/bin/env python3
from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOCUS = ROOT / 'lib/src/components/focus.dart'
FOCUS_TEST = ROOT / 'test/focus/focus_system_test.dart'
TEXT_FIELD = ROOT / 'lib/src/components/text_field.dart'

SKIP_DIRS = {'.git', '.github', '.dart_tool', 'build'}


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise RuntimeError(f'Expected source fragment not found: {old!r}')
    return text.replace(old, new, 1)


def fix_focus_source() -> None:
    text = FOCUS.read_text(encoding='utf-8')
    text = replace_once(
        text,
        '  final ValueChanged<bool>? onFocusChange;',
        '  final void Function(bool hasFocus)? onFocusChange;',
    )
    text = replace_once(
        text,
        '  @internal\n  void _addChild(FocusNode node) {',
        '  void _addChild(FocusNode node) {',
    )
    text = replace_once(
        text,
        '  @internal\n  void _removeChild(FocusNode node) {',
        '  void _removeChild(FocusNode node) {',
    )
    FOCUS.write_text(text, encoding='utf-8')


def fix_focus_tests() -> None:
    text = FOCUS_TEST.read_text(encoding='utf-8')
    text = replace_once(
        text,
        "final skipped = FocusNode(debugLabel: 'skipped', skipTraversal: true);",
        "final skipped = FocusNode(debugLabel: 'skipped');",
    )
    text = replace_once(
        text,
        "Focus(focusNode: skipped, child: const Text('2'))",
        "Focus(\n"
        "                focusNode: skipped,\n"
        "                skipTraversal: true,\n"
        "                child: const Text('2'),\n"
        "              )",
    )
    FOCUS_TEST.write_text(text, encoding='utf-8')


def migrate_text_field_source() -> None:
    text = TEXT_FIELD.read_text(encoding='utf-8')

    text = replace_once(
        text,
        "    this.controller,\n"
        "    this.focused = false,\n"
        "    this.onFocusChange,",
        "    this.controller,\n"
        "    this.focusNode,\n"
        "    this.autofocus = false,\n"
        "    this.onFocusChange,",
    )
    text = replace_once(
        text,
        "  final TextEditingController? controller;\n"
        "  final bool focused;\n"
        "  final ValueChanged<bool>? onFocusChange;",
        "  final TextEditingController? controller;\n"
        "  final FocusNode? focusNode;\n"
        "  final bool autofocus;\n"
        "  final ValueChanged<bool>? onFocusChange;",
    )
    text = replace_once(
        text,
        "  late TextEditingController _controller;\n"
        "  bool _controllerIsInternal = false;\n"
        "  Timer? _cursorTimer;",
        "  late TextEditingController _controller;\n"
        "  bool _controllerIsInternal = false;\n"
        "  late FocusNode _focusNode;\n"
        "  bool _focusNodeIsInternal = false;\n"
        "  bool _hasFocus = false;\n"
        "  Timer? _cursorTimer;",
    )

    focus_helpers = """  void _initFocusNode() {
    _focusNodeIsInternal = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'TextField');
    _hasFocus = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChanged);
  }

  void _disposeFocusNode() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_focusNodeIsInternal) {
      _focusNode.dispose();
    }
  }

  void _handleFocusChanged() {
    final hasFocus = _focusNode.hasFocus;
    if (hasFocus == _hasFocus) return;

    _hasFocus = hasFocus;
    if (hasFocus && widget.showCursor) {
      _startCursorBlink();
    } else {
      _stopCursorBlink();
    }
    widget.onFocusChange?.call(hasFocus);
    if (mounted) setState(() {});
  }

"""
    text = replace_once(
        text,
        "  // Reference to the render object for cursor movement\n"
        "  RenderTextField? _renderTextField;\n\n"
        "  void _handleSelectionChangeFromRenderObject",
        "  // Reference to the render object for cursor movement\n"
        "  RenderTextField? _renderTextField;\n\n"
        + focus_helpers
        + "  void _handleSelectionChangeFromRenderObject",
    )
    text = replace_once(
        text,
        "    // Request focus if not already focused (e.g., user clicked in the field)\n"
        "    if (!widget.focused) {\n"
        "      widget.onFocusChange?.call(true);\n"
        "    }",
        "    // Mouse selection should focus the field, matching Flutter TextField.\n"
        "    if (!_focusNode.hasFocus) {\n"
        "      _focusNode.requestFocus();\n"
        "    }",
    )
    text = replace_once(
        text,
        "  void initState() {\n"
        "    super.initState();\n\n"
        "    if (widget.controller == null) {",
        "  void initState() {\n"
        "    super.initState();\n"
        "    _initFocusNode();\n\n"
        "    if (widget.controller == null) {",
    )
    text = replace_once(
        text,
        "    if (widget.focused && widget.showCursor) {\n"
        "      _startCursorBlink();\n"
        "    }",
        "    if (_hasFocus && widget.showCursor) {\n"
        "      _startCursorBlink();\n"
        "    }",
    )
    text = replace_once(
        text,
        "  void dispose() {\n"
        "    _stopCursorBlink();\n"
        "    _controller.removeListener(_handleControllerChanged);",
        "  void dispose() {\n"
        "    _stopCursorBlink();\n"
        "    _disposeFocusNode();\n"
        "    _controller.removeListener(_handleControllerChanged);",
    )
    text = replace_once(
        text,
        "    // Handle focus changes or blink rate changes\n"
        "    if (widget.focused != oldWidget.focused ||\n"
        "        widget.cursorBlinkRate != oldWidget.cursorBlinkRate) {\n"
        "      if (widget.focused && widget.showCursor) {\n"
        "        _startCursorBlink();\n"
        "      } else {\n"
        "        _stopCursorBlink();\n"
        "      }\n"
        "    }",
        "    final focusNodeChanged = !identical(widget.focusNode, oldWidget.focusNode);\n"
        "    if (focusNodeChanged) {\n"
        "      _disposeFocusNode();\n"
        "      _initFocusNode();\n"
        "    }\n\n"
        "    if (focusNodeChanged ||\n"
        "        widget.cursorBlinkRate != oldWidget.cursorBlinkRate ||\n"
        "        widget.showCursor != oldWidget.showCursor) {\n"
        "      if (_hasFocus && widget.showCursor) {\n"
        "        _startCursorBlink();\n"
        "      } else {\n"
        "        _stopCursorBlink();\n"
        "      }\n"
        "    }",
    )
    text = replace_once(
        text,
        "    final isFocused = widget.focused;",
        "    final isFocused = _hasFocus;",
    )
    text = replace_once(
        text,
        "    // Wrap with Focusable for keyboard input\n"
        "    return Focusable(\n"
        "      focused: isFocused,\n"
        "      onKeyEvent: _handleKeyEvent,\n"
        "      child: content,\n"
        "    );",
        "    // Focus owns traversal and keyboard dispatch for the field.\n"
        "    return Focus(\n"
        "      focusNode: _focusNode,\n"
        "      autofocus: widget.autofocus,\n"
        "      canRequestFocus: widget.enabled,\n"
        "      onKeyEvent: _handleKeyEvent,\n"
        "      child: content,\n"
        "    );",
    )

    TEXT_FIELD.write_text(text, encoding='utf-8')


def _matching_paren(text: str, open_index: int) -> int | None:
    depth = 0
    i = open_index
    quote: str | None = None
    triple = False
    line_comment = False
    block_comment = False

    while i < len(text):
        if line_comment:
            if text[i] == '\n':
                line_comment = False
            i += 1
            continue
        if block_comment:
            if text.startswith('*/', i):
                block_comment = False
                i += 2
            else:
                i += 1
            continue
        if quote is not None:
            marker = quote * (3 if triple else 1)
            if text.startswith(marker, i):
                quote = None
                triple = False
                i += len(marker)
                continue
            if text[i] == '\\':
                i += 2
            else:
                i += 1
            continue

        if text.startswith('//', i):
            line_comment = True
            i += 2
            continue
        if text.startswith('/*', i):
            block_comment = True
            i += 2
            continue
        if text.startswith("'''", i) or text.startswith('"""', i):
            quote = text[i]
            triple = True
            i += 3
            continue
        if text[i] in "'\"":
            quote = text[i]
            triple = False
            i += 1
            continue
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def migrate_text_field_call_sites() -> None:
    pattern = re.compile(r'(?<![A-Za-z0-9_])TextField\s*\(')
    for current_root, dirs, names in os.walk(ROOT):
        dirs[:] = [name for name in dirs if name not in SKIP_DIRS]
        for name in names:
            if not name.endswith('.dart'):
                continue
            path = Path(current_root) / name
            if path == TEXT_FIELD:
                continue
            text = path.read_text(encoding='utf-8')
            cursor = 0
            output: list[str] = []
            changed = False
            while True:
                match = pattern.search(text, cursor)
                if match is None:
                    output.append(text[cursor:])
                    break
                open_index = text.find('(', match.start())
                close_index = _matching_paren(text, open_index)
                if close_index is None:
                    output.append(text[cursor:])
                    break
                output.append(text[cursor:open_index + 1])
                body = text[open_index + 1:close_index]
                migrated = re.sub(r'\bfocused\s*:\s*true', 'autofocus: true', body)
                migrated = re.sub(r'\bfocused\s*:\s*false', 'autofocus: false', migrated)
                changed = changed or migrated != body
                output.append(migrated)
                output.append(')')
                cursor = close_index + 1
            if changed:
                path.write_text(''.join(output), encoding='utf-8')


def main() -> None:
    fix_focus_source()
    fix_focus_tests()
    migrate_text_field_source()
    migrate_text_field_call_sites()


if __name__ == '__main__':
    main()
