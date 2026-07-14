#!/usr/bin/env python3
from __future__ import annotations

import base64
import gzip
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[2]
payload = root / '.github/phase2_payload/patch.gz.b64'
patch = gzip.decompress(base64.b64decode(payload.read_text(encoding='utf-8')))
patch_path = root / '.github/phase2_payload/renderer_v2_layers.patch'
patch_path.write_bytes(patch)

subprocess.run(
    [
        'git',
        'apply',
        '--whitespace=nowarn',
        '--exclude=.github/workflows/renderer_v2.yml',
        str(patch_path),
    ],
    cwd=root,
    check=True,
)

patch_path.unlink()
print('Renderer V2 cached-layer patch applied.')
