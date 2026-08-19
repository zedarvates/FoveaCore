#!/usr/bin/env python3
"""Unit tests for the shared reconstruction digest helper."""

from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
HELPER_DIR = ROOT / "addons" / "foveacore" / "scripts" / "reconstruction"
sys.path.insert(0, str(HELPER_DIR))

from file_digest import sha256  # noqa: E402


class FileDigestTests(unittest.TestCase):
    def test_sha256_matches_stdlib(self) -> None:
        payload = b"fovea-engine-digest" * 4096
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "payload.bin"
            path.write_bytes(payload)
            self.assertEqual(sha256(path), hashlib.sha256(payload).hexdigest())


if __name__ == "__main__":
    unittest.main()
