#!/usr/bin/env python3
"""One-shot breaking migration from Nocterm's public API to Cinder 1.0.

The migration intentionally does not preserve the legacy public API. It:
- rebrands package/library/import names from nocterm to cinder;
- renames the framework vocabulary from Component to Widget;
- removes the obsolete App/Frame runtime;
- keeps the original MIT license and adds explicit fork attribution.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

TEXT_SUFFIXES = {
    ".dart",
    ".yaml",
    ".yml",
    ".md",
    ".mdx",
    ".json",
    ".txt",
    ".html",
    ".js",
    ".css",
    ".sh",
    ".ps1",
}

SKIP_DIRS = {".git", ".dart_tool", "build", ".idea", ".vscode"}

FILE_REFERENCE_REPLACEMENTS: tuple[tuple[str, str], ...] = (
    ("stateful_component.dart", "stateful_widget.dart"),
    ("stateless_component.dart", "stateless_widget.dart"),
    ("component.dart", "widget.dart"),
)

IDENTIFIER_REPLACEMENTS: tuple[tuple[str, str], ...] = (
    (r"\bMultiChildRenderObjectComponent\b", "MultiChildRenderObjectWidget"),
    (r"\bSingleChildRenderObjectComponent\b", "SingleChildRenderObjectWidget"),
    (r"\bRenderObjectComponent\b", "RenderObjectWidget"),
    (r"\bStatefulComponent\b", "StatefulWidget"),
    (r"\bStatelessComponent\b", "StatelessWidget"),
    (r"\bComponentBuilder\b", "WidgetBuilder"),
    (r"\bdidUpdateComponent\b", "didUpdateWidget"),
    (r"\bnewComponent\b", "newWidget"),
    (r"\boldComponent\b", "oldWidget"),
    (r"\bComponent\b", "Widget"),
    (r"\bcomponent\b", "widget"),
)

BRAND_REPLACEMENTS: tuple[tuple[str, str], ...] = (
    ("package:nocterm", "package:cinder"),
    ("Nocterm", "Cinder"),
    ("NOCTERM", "CINDER"),
    ("nocterm", "cinder"),
)

LEGACY_FILES = (
    Path("lib/src/app.dart"),
    Path("lib/src/frame.dart"),
)

FRAMEWORK_FILE_RENAMES = {
    Path("lib/src/framework/component.dart"): Path("lib/src/framework/widget.dart"),
    Path("lib/src/framework/stateful_component.dart"): Path(
        "lib/src/framework/stateful_widget.dart"
    ),
    Path("lib/src/framework/stateless_component.dart"): Path(
        "lib/src/framework/stateless_widget.dart"
    ),
}


def iter_text_files() -> list[Path]:
    files: list[Path] = []
    for current_root, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        base = Path(current_root)
        for name in names:
            path = base / name
            if path.name == "LICENSE":
                continue
            if path.suffix.lower() in TEXT_SUFFIXES or path.name in {
                "pubspec.lock",
                "melos.yaml",
                "analysis_options.yaml",
            }:
                files.append(path)
    return files


def transform_text(path: Path) -> None:
    try:
        original = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return

    transformed = original

    for old, new in FILE_REFERENCE_REPLACEMENTS:
        transformed = transformed.replace(old, new)

    for old, new in BRAND_REPLACEMENTS:
        transformed = transformed.replace(old, new)

    if path.suffix.lower() in {".dart", ".md", ".mdx", ".txt"}:
        for pattern, replacement in IDENTIFIER_REPLACEMENTS:
            transformed = re.sub(pattern, replacement, transformed)

    transformed = transformed.replace(
        "https://github.com/Norbert515/cinder", "https://github.com/eukalpia/cinder"
    )
    transformed = transformed.replace(
        "https://docs.cinder.dev", "https://github.com/eukalpia/cinder"
    )

    if path.as_posix().endswith("lib/nocterm.dart") or path.as_posix().endswith(
        "lib/cinder.dart"
    ):
        transformed = re.sub(
            r"^export 'src/(?:app|frame)\.dart';\s*\n",
            "",
            transformed,
            flags=re.MULTILINE,
        )

    if transformed != original:
        path.write_text(transformed, encoding="utf-8")


def rename_path(source: Path, destination: Path) -> None:
    src = ROOT / source
    dst = ROOT / destination
    if not src.exists() or src == dst:
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        raise RuntimeError(f"Refusing to overwrite existing path: {dst}")
    src.rename(dst)


def rename_brand_paths() -> None:
    candidates = sorted(
        (
            path
            for path in ROOT.rglob("*")
            if ".git" not in path.parts
            and "nocterm" in path.name.lower()
            and path.name != "LICENSE"
        ),
        key=lambda p: len(p.parts),
        reverse=True,
    )
    for path in candidates:
        if not path.exists():
            continue
        new_name = re.sub("nocterm", "cinder", path.name, flags=re.IGNORECASE)
        destination = path.with_name(new_name)
        if destination.exists():
            if path.is_dir() and destination.is_dir():
                for child in list(path.iterdir()):
                    target = destination / child.name
                    if target.exists():
                        raise RuntimeError(f"Path collision during merge: {target}")
                    child.rename(target)
                path.rmdir()
                continue
            raise RuntimeError(f"Path collision during rebrand: {destination}")
        path.rename(destination)


def write_notice() -> None:
    notice = ROOT / "NOTICE.md"
    notice.write_text(
        "# Cinder attribution\n\n"
        "Cinder is a substantially modified fork of Nocterm.\n\n"
        "Original project copyright (c) 2025 Norbert Kozsir.\n"
        "Cinder modifications copyright (c) 2026 eukalpia contributors.\n\n"
        "The original MIT license is retained in `LICENSE`.\n",
        encoding="utf-8",
    )


def update_root_pubspec() -> None:
    pubspec = ROOT / "pubspec.yaml"
    text = pubspec.read_text(encoding="utf-8")
    text = re.sub(r"^name:\s*.*$", "name: cinder", text, count=1, flags=re.MULTILINE)
    text = re.sub(
        r"^description:\s*.*$",
        "description: A Flutter-style, high-performance terminal UI framework for Dart.",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^version:\s*.*$",
        "version: 1.0.0-dev.1",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^repository:\s*.*$",
        "repository: https://github.com/eukalpia/cinder",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^homepage:\s*.*$",
        "homepage: https://github.com/eukalpia/cinder",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^documentation:\s*.*$",
        "documentation: https://github.com/eukalpia/cinder#readme",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    pubspec.write_text(text, encoding="utf-8")


def assert_no_legacy_public_api() -> None:
    forbidden = (
        "class Component",
        "class StatelessComponent",
        "class StatefulComponent",
        "class RenderObjectComponent",
        "export 'src/app.dart'",
        "export 'src/frame.dart'",
        "package:nocterm",
    )
    failures: list[str] = []
    for path in iter_text_files():
        if ".github" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for token in forbidden:
            if token in text:
                failures.append(f"{path.relative_to(ROOT)} contains {token!r}")
    if failures:
        raise RuntimeError("Legacy API remains:\n" + "\n".join(failures[:100]))


def main() -> None:
    for legacy in LEGACY_FILES:
        path = ROOT / legacy
        if path.exists():
            path.unlink()

    for source, destination in FRAMEWORK_FILE_RENAMES.items():
        rename_path(source, destination)

    for path in iter_text_files():
        transform_text(path)

    rename_brand_paths()

    for path in iter_text_files():
        transform_text(path)

    update_root_pubspec()
    write_notice()
    assert_no_legacy_public_api()

    print("Cinder breaking migration completed.")


if __name__ == "__main__":
    main()
