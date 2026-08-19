#!/usr/bin/env python3
"""Shared SHA-256 helper for reconstruction and proof scripts."""

from __future__ import annotations

import hashlib
from pathlib import Path


def sha256(path: Path | str, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(chunk_size), b""):
            digest.update(chunk)
    return digest.hexdigest()
