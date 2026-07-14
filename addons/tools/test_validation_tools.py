#!/usr/bin/env python3
"""Portable smoke tests for the repository's Python validation tools."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CHECK_TYPING = REPOSITORY_ROOT / "addons" / "tools" / "check_typing.py"
VALIDATE_RULES = REPOSITORY_ROOT / "addons" / "tools" / "validate_rules.py"


def run_tool(command: list[str], encoding: str) -> None:
    environment = os.environ.copy()
    environment["PYTHONIOENCODING"] = encoding
    completed = subprocess.run(
        command,
        cwd=REPOSITORY_ROOT,
        env=environment,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if completed.returncode != 0:
        raise AssertionError(
            "Validation command failed with %d under %s:\n%s\n%s"
            % (completed.returncode, encoding, completed.stdout, completed.stderr)
        )


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary_directory:
        fixture = Path(temporary_directory) / "unicode_fixture.gd"
        fixture.write_text("# Unicode: cafe\u0301\nvar typed_value: int = 1\n", encoding="utf-8")
        for encoding in ("utf-8", "cp1252"):
            run_tool([sys.executable, str(CHECK_TYPING), temporary_directory, "0"], encoding)
            run_tool([sys.executable, str(VALIDATE_RULES), temporary_directory], encoding)
    print("PASS: Validation tools support UTF-8 and cp1252 consoles")


if __name__ == "__main__":
    main()
