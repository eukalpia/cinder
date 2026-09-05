"""Preparation must preserve command identity for toolchain dispatch shims."""
from pathlib import Path
import tempfile
import unittest

from prepare import executable


class ExecutableTest(unittest.TestCase):
    def test_preserves_rustup_style_symlink_name(self):
        with tempfile.TemporaryDirectory() as directory:
            manager = Path(directory) / 'rustup'
            manager.write_text('#!/bin/sh\nexit 0\n')
            manager.chmod(0o755)
            cargo = Path(directory) / 'cargo'
            cargo.symlink_to(manager)
            self.assertEqual(Path(executable(str(cargo))).name, 'cargo')


if __name__ == '__main__':
    unittest.main()
