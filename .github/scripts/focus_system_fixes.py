#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOCUS = ROOT / 'lib/src/components/focus.dart'


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        if new in text:
            return text
        raise RuntimeError(f'Expected focus source fragment not found: {old!r}')
    return text.replace(old, new, 1)


def main() -> None:
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


if __name__ == '__main__':
    main()
