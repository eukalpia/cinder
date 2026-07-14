#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOCUS = ROOT / 'lib/src/components/focus.dart'
FOCUS_TEST = ROOT / 'test/focus/focus_system_test.dart'


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise RuntimeError(f'Expected focus source fragment not found: {old!r}')
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


def main() -> None:
    fix_focus_source()
    fix_focus_tests()


if __name__ == '__main__':
    main()
