#!/usr/bin/env python3
"""Generate pure-Dart Cinder icon catalogs from Flutter and Lucide sources."""

from __future__ import annotations

import argparse
import collections
import re
import json
import urllib.request
from dataclasses import dataclass
from pathlib import Path

MATERIAL_URL = (
    "https://raw.githubusercontent.com/flutter/flutter/stable/"
    "packages/flutter/lib/src/material/icons.dart"
)
LUCIDE_TREE_URL = (
    "https://api.github.com/repos/lucide-icons/lucide/git/trees/main?recursive=1"
)

ROOT = Path(__file__).resolve().parents[1]
MATERIAL_OUT = ROOT / "packages/cinder_material_icons/lib/src/icons.dart"
LUCIDE_OUT = ROOT / "packages/cinder_lucide/lib/src/lucide_icons.dart"

DECLARATION = re.compile(
    r"static\s+const\s+IconData\s+([A-Za-z_$][\w$]*)\s*=\s*(.*?);",
    re.DOTALL,
)
ICON_DATA = re.compile(r"(?:const\s+)?IconData\s*\(\s*(0x[0-9a-fA-F]+|\d+)")
IDENTIFIER = re.compile(r"^([A-Za-z_$][\w$]*)$")


@dataclass(frozen=True)
class ParsedIcon:
    name: str
    code_point: int | None = None
    alias: str | None = None
    match_text_direction: bool = False


def fetch(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "cinder-icon-generator/1.0"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read().decode("utf-8")


DART_RESERVED = {
    "abstract", "as", "assert", "async", "await", "base", "break", "case",
    "catch", "class", "const", "continue", "covariant", "default", "deferred",
    "do", "dynamic", "else", "enum", "export", "extends", "extension", "external",
    "factory", "false", "final", "finally", "for", "Function", "get", "hide",
    "if", "implements", "import", "in", "interface", "is", "late", "library",
    "mixin", "new", "null", "of", "on", "operator", "part", "required", "rethrow",
    "return", "sealed", "set", "show", "static", "super", "switch", "sync", "this",
    "throw", "true", "try", "type", "typedef", "var", "void", "when", "while", "with",
    "yield",
}


def dart_identifier(icon_name: str) -> str:
    parts = [part for part in re.split(r"[^A-Za-z0-9]+", icon_name) if part]
    if not parts:
        return "icon"
    result = parts[0].lower() + "".join(part[:1].upper() + part[1:] for part in parts[1:])
    if result[0].isdigit():
        result = "icon" + result[:1].upper() + result[1:]
    if result in DART_RESERVED:
        result += "Icon"
    return result


def fetch_lucide_icons() -> list[ParsedIcon]:
    payload = json.loads(fetch(LUCIDE_TREE_URL))
    names: set[str] = set()
    for item in payload.get("tree", []):
        path = item.get("path", "")
        if not path.startswith("icons/") or not path.endswith(".svg"):
            continue
        name = path.removeprefix("icons/").removesuffix(".svg")
        if "/" in name:
            continue
        names.add(name)

    parsed: list[ParsedIcon] = []
    used_identifiers: set[str] = set()
    for index, name in enumerate(sorted(names)):
        identifier = dart_identifier(name)
        if identifier in used_identifiers:
            suffix = 2
            while f"{identifier}{suffix}" in used_identifiers:
                suffix += 1
            identifier = f"{identifier}{suffix}"
        used_identifiers.add(identifier)
        normalized_name = name.lower()
        parsed.append(
            ParsedIcon(
                name=identifier,
                code_point=0xE000 + index,
                match_text_direction=(
                    "arrow-left" in normalized_name
                    or "arrow-right" in normalized_name
                    or "chevron-left" in normalized_name
                    or "chevron-right" in normalized_name
                    or "move-left" in normalized_name
                    or "move-right" in normalized_name
                ),
            )
        )
    return parsed


def parse_icons(source: str) -> list[ParsedIcon]:
    parsed: "collections.OrderedDict[str, ParsedIcon]" = collections.OrderedDict()
    for match in DECLARATION.finditer(source):
        name = match.group(1)
        expression = " ".join(match.group(2).split())
        icon_match = ICON_DATA.search(expression)
        if icon_match:
            code_point = int(icon_match.group(1), 0)
            parsed[name] = ParsedIcon(
                name=name,
                code_point=code_point,
                match_text_direction=("matchTextDirection: true" in expression),
            )
            continue

        alias_match = IDENTIFIER.match(expression)
        if alias_match:
            parsed[name] = ParsedIcon(name=name, alias=alias_match.group(1))

    return list(parsed.values())


UNICODE_EXACT = {
    "home": "⌂",
    "house": "⌂",
    "search": "⌕",
    "menu": "☰",
    "close": "×",
    "x": "×",
    "check": "✓",
    "done": "✓",
    "add": "+",
    "plus": "+",
    "remove": "−",
    "minus": "−",
    "warning": "⚠",
    "info": "ⓘ",
    "star": "★",
    "favorite": "♥",
    "heart": "♥",
    "play_arrow": "▶",
    "play": "▶",
    "pause": "Ⅱ",
    "stop": "■",
    "refresh": "↻",
    "sync": "↻",
    "settings": "⚙",
    "lock": "▣",
    "visibility": "◉",
    "edit": "✎",
    "delete": "⌫",
    "download": "⇩",
    "upload": "⇧",
    "expand_more": "⌄",
    "expand_less": "⌃",
    "chevron_left": "‹",
    "chevron_right": "›",
    "arrow_back": "←",
    "arrow_forward": "→",
    "arrow_upward": "↑",
    "arrow_downward": "↓",
}


def normalized(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower())


def fallback_for(name: str) -> tuple[str | None, str]:
    key = normalized(name)
    if key in UNICODE_EXACT:
        glyph = UNICODE_EXACT[key]
        return glyph, _ascii_for_glyph(glyph)

    words = set(filter(None, key.split("_")))
    compact = key.replace("_", "")

    if "arrow" in words or "chevron" in words or compact.startswith("arrow"):
        if "left" in words or compact.endswith("left"):
            return "←", "<"
        if "right" in words or compact.endswith("right"):
            return "→", ">"
        if "up" in words or "upward" in words or compact.endswith("up"):
            return "↑", "^"
        if "down" in words or "downward" in words or compact.endswith("down"):
            return "↓", "v"
    if {"add", "plus"} & words:
        return "+", "+"
    if {"remove", "minus"} & words:
        return "−", "-"
    if {"check", "done", "tick"} & words:
        return "✓", "v"
    if {"close", "cancel", "x"} & words:
        return "×", "x"
    if "menu" in words:
        return "☰", "="
    if "search" in words:
        return "⌕", "?"
    if {"home", "house"} & words:
        return "⌂", "H"
    if "star" in words:
        return "★", "*"
    if {"heart", "favorite"} & words:
        return "♥", "<3"
    if "play" in words:
        return "▶", ">"
    if "pause" in words:
        return "Ⅱ", "||"
    if "stop" in words:
        return "■", "#"
    if {"warning", "alert"} & words:
        return "⚠", "!"
    if "info" in words:
        return "ⓘ", "i"
    if {"refresh", "rotate", "sync"} & words:
        return "↻", "r"
    if "circle" in words:
        return "○", "o"
    if {"square", "box"} & words:
        return "□", "#"

    return None, "?"


def _ascii_for_glyph(glyph: str) -> str:
    return {
        "⌂": "H",
        "⌕": "?",
        "☰": "=",
        "×": "x",
        "✓": "v",
        "−": "-",
        "⚠": "!",
        "ⓘ": "i",
        "★": "*",
        "♥": "<3",
        "▶": ">",
        "Ⅱ": "||",
        "■": "#",
        "↻": "r",
        "⚙": "*",
        "▣": "#",
        "◉": "o",
        "✎": "e",
        "⌫": "x",
        "⇩": "v",
        "⇧": "^",
        "⌄": "v",
        "⌃": "^",
        "‹": "<",
        "›": ">",
        "←": "<",
        "→": ">",
        "↑": "^",
        "↓": "v",
    }.get(glyph, "?")


def dart_string(value: str) -> str:
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def resolve_aliases(icons: list[ParsedIcon]) -> list[ParsedIcon]:
    by_name = {icon.name: icon for icon in icons}
    resolved: list[ParsedIcon] = []

    def resolve(icon: ParsedIcon, seen: set[str]) -> ParsedIcon | None:
        if icon.code_point is not None:
            return icon
        if icon.alias is None or icon.alias in seen:
            return None
        target = by_name.get(icon.alias)
        if target is None:
            return None
        target_resolved = resolve(target, seen | {icon.name})
        if target_resolved is None:
            return None
        return ParsedIcon(
            name=icon.name,
            code_point=target_resolved.code_point,
            alias=icon.alias,
            match_text_direction=(
                icon.match_text_direction or target_resolved.match_text_direction
            ),
        )

    for icon in icons:
        item = resolve(icon, set())
        if item is not None:
            resolved.append(item)
    return resolved


def generate_catalog(
    icons: list[ParsedIcon],
    *,
    class_name: str,
    font_family: str,
    font_package: str | None,
    source_url: str,
) -> str:
    icons = resolve_aliases(icons)
    lines = [
        "// GENERATED FILE - DO NOT EDIT.",
        f"// Source: {source_url}",
        "// Generated by tool/generate_icon_packs.py.",
        "// ignore_for_file: constant_identifier_names",
        "import 'package:cinder/cinder.dart';",
        "",
        f"/// Generated icon identifiers for {class_name}.",
        f"abstract final class {class_name} {{",
        f"  static const int count = {len(icons)};",
        "",
    ]

    for icon in icons:
        unicode_fallback, ascii_fallback = fallback_for(icon.name)
        args = [f"0x{icon.code_point:x}", f"fontFamily: {dart_string(font_family)}"]
        if font_package is not None:
            args.append(f"fontPackage: {dart_string(font_package)}")
        args.append(f"name: {dart_string(icon.name)}")
        if unicode_fallback is not None:
            args.append(f"unicodeFallback: {dart_string(unicode_fallback)}")
        args.append(f"asciiFallback: {dart_string(ascii_fallback)}")
        if icon.match_text_direction:
            args.append("matchTextDirection: true")
        joined = ", ".join(args)
        lines.append(f"  static const IconData {icon.name} = IconData({joined});")

    lines.extend(["}", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--material-source", type=Path)
    parser.add_argument("--lucide-source", type=Path)
    args = parser.parse_args()

    material_source = (
        args.material_source.read_text(encoding="utf-8")
        if args.material_source
        else fetch(MATERIAL_URL)
    )
    material = parse_icons(material_source)
    lucide = (
        parse_icons(args.lucide_source.read_text(encoding="utf-8"))
        if args.lucide_source
        else fetch_lucide_icons()
    )

    if len(material) < 1000:
        raise SystemExit(f"Material parser found only {len(material)} icons")
    if len(lucide) < 1000:
        raise SystemExit(f"Lucide parser found only {len(lucide)} icons")

    MATERIAL_OUT.write_text(
        generate_catalog(
            material,
            class_name="Icons",
            font_family="MaterialIcons",
            font_package=None,
            source_url=MATERIAL_URL,
        ),
        encoding="utf-8",
    )
    LUCIDE_OUT.write_text(
        generate_catalog(
            lucide,
            class_name="LucideIcons",
            font_family="Lucide",
            font_package="cinder_lucide",
            source_url=LUCIDE_TREE_URL,
        ),
        encoding="utf-8",
    )

    print(f"Generated {len(material)} Material icons")
    print(f"Generated {len(lucide)} Lucide icons")


if __name__ == "__main__":
    main()
