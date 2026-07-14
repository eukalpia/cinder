#!/usr/bin/env python3
"""Apply focused post-migration fixes that should be committed with Cinder 1.0."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_exact(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        # Idempotent: accept an already-applied replacement.
        if new in text:
            return
        raise RuntimeError(f"Expected text not found in {path}: {old!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def fix_riverpod_listener_test() -> None:
    path = ROOT / "packages/cinder_riverpod/test/watch_test.dart"
    replace_exact(
        path,
        "test('listen receives updates without rebuilding', () async {",
        "test('listen callback can request rebuilds', () async {",
    )
    replace_exact(
        path,
        "// Value updated but build count stays the same\n"
        "          expect(tester.terminalState, containsText('Last value: 1'));\n"
        "          expect(tester.terminalState, containsText('Build count: 1'));",
        "// The listener calls setState, so this widget rebuilds exactly once.\n"
        "          expect(tester.terminalState, containsText('Last value: 1'));\n"
        "          expect(tester.terminalState, containsText('Build count: 2'));",
    )
    replace_exact(
        path,
        "expect(tester.terminalState, containsText('Last value: 2'));\n"
        "          expect(tester.terminalState, containsText('Build count: 1'));",
        "expect(tester.terminalState, containsText('Last value: 2'));\n"
        "          expect(tester.terminalState, containsText('Build count: 3'));",
    )


def main() -> None:
    fix_riverpod_listener_test()
    print("Cinder post-migration fixes completed.")


if __name__ == "__main__":
    main()
