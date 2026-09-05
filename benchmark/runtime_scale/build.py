#!/usr/bin/env python3
"""Build an AOT monitor with a recorded source fingerprint (standard library)."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT_ENTRIES = ("lib", "example/scale_monitor.dart", "pubspec.yaml", "pubspec.lock",
                    "test/integration/scale_monitor_test.dart", "benchmark/runtime_scale",
                    "doc/scale-monitor.md", "LICENSE", "NOTICE.md")


def snapshot_fingerprint():
    digest = hashlib.sha256()
    for name in SNAPSHOT_ENTRIES:
        entry = ROOT / name
        paths = sorted(entry.rglob("*")) if entry.is_dir() else [entry]
        for path in paths:
            if path.is_file() and "__pycache__" not in path.parts:
                digest.update(str(path.relative_to(ROOT)).encode() + b"\0")
                digest.update(path.read_bytes())
    return digest.hexdigest()


def source_fingerprint():
    paths = sorted(path for path in (ROOT / "lib").rglob("*.dart") if path.is_file())
    paths += [ROOT / "example/scale_monitor.dart", ROOT / "pubspec.yaml", ROOT / "pubspec.lock"]
    digest = hashlib.sha256()
    for path in paths:
        digest.update(str(path.relative_to(ROOT)).encode() + b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", default="dart")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    source_hash = source_fingerprint()
    snapshot_hash = snapshot_fingerprint()
    snapshot_path = Path(str(output) + ".source.tar.gz")
    with tarfile.open(snapshot_path, "w:gz") as archive:
        for name in SNAPSHOT_ENTRIES:
            archive.add(ROOT / name, arcname=name, filter=lambda info: None if "__pycache__" in info.name else info)
    command = [args.dart, "compile", "exe", f"-Dscale.source_hash={source_hash}",
               "example/scale_monitor.dart", "-o", str(output)]
    subprocess.run(command, cwd=ROOT, check=True)
    if source_fingerprint() != source_hash or snapshot_fingerprint() != snapshot_hash:
        raise RuntimeError("Sources changed during compilation; rebuild before measuring")
    metadata = {
        "command": command, "source_sha256": source_hash,
        "source_snapshot": str(snapshot_path),
        "snapshot_contents_sha256": snapshot_hash,
        "snapshot_archive_sha256": hashlib.sha256(snapshot_path.read_bytes()).hexdigest(),
        "binary_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "dart": subprocess.check_output([args.dart, "--version"], text=True).strip(),
        "git_revision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "git_status": subprocess.check_output(["git", "status", "--short"], cwd=ROOT, text=True),
    }
    Path(str(output) + ".build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata))


if __name__ == "__main__":
    main()
