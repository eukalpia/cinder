#!/usr/bin/env python3
from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKIP_DIRS = {'.git', '.github', '.dart_tool', 'build'}
TEXT_FIELD_SOURCE = ROOT / 'lib/src/components/text_field.dart'


def matching_paren(text: str, open_index: int) -> int | None:
    depth = 0
    index = open_index
    quote: str | None = None
    triple = False
    line_comment = False
    block_comment = False

    while index < len(text):
        if line_comment:
            if text[index] == '\n':
                line_comment = False
            index += 1
            continue
        if block_comment:
            if text.startswith('*/', index):
                block_comment = False
                index += 2
            else:
                index += 1
            continue
        if quote is not None:
            marker = quote * (3 if triple else 1)
            if text.startswith(marker, index):
                quote = None
                triple = False
                index += len(marker)
                continue
            index += 2 if text[index] == '\\' else 1
            continue
        if text.startswith('//', index):
            line_comment = True
            index += 2
            continue
        if text.startswith('/*', index):
            block_comment = True
            index += 2
            continue
        if text.startswith("'''", index) or text.startswith('"""', index):
            quote = text[index]
            triple = True
            index += 3
            continue
        if text[index] in "'\"":
            quote = text[index]
            index += 1
            continue
        if text[index] == '(':
            depth += 1
        elif text[index] == ')':
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return None


def migrate_file(path: Path) -> None:
    pattern = re.compile(r'(?<![A-Za-z0-9_])TextField\s*\(')
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
        close_index = matching_paren(text, open_index)
        if close_index is None:
            output.append(text[cursor:])
            break

        output.append(text[cursor:open_index + 1])
        body = text[open_index + 1:close_index]
        migrated = re.sub(r'\bfocused\s*:', 'autofocus:', body)
        changed = changed or migrated != body
        output.append(migrated)
        output.append(')')
        cursor = close_index + 1

    if changed:
        path.write_text(''.join(output), encoding='utf-8')


def main() -> None:
    for current_root, dirs, names in os.walk(ROOT):
        dirs[:] = [name for name in dirs if name not in SKIP_DIRS]
        for name in names:
            if not name.endswith('.dart'):
                continue
            path = Path(current_root) / name
            if path != TEXT_FIELD_SOURCE:
                migrate_file(path)

    new_test = ROOT / 'test/focus/text_field_focus_test.dart'
    if new_test.exists():
        text = new_test.read_text(encoding='utf-8')
        text = text.replace(
            "expect(secondController.text, isEmpty);",
            "expect(secondController.text, '');",
        )
        new_test.write_text(text, encoding='utf-8')


if __name__ == '__main__':
    main()
