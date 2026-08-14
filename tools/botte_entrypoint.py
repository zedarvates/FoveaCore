#!/usr/bin/env python3
"""Portable entry point for FoveaEngine's optional Botte integration."""

from __future__ import annotations

import os
from pathlib import Path
import runpy
import sys


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ENV = "BOTTE_SOURCE_ROOT"
MODULES = {
    "mcp": "skills.llm_mcp.server",
    "preflight": "skills.preflight.hook",
    "checkup": "skills.checkup.cli",
}


def resolve_botte_source() -> Path:
    """Resolve an explicit, embedded, or per-user Botte source checkout."""
    candidates: list[Path] = []
    configured = os.environ.get(SOURCE_ENV, "").strip()
    if configured:
        candidates.append(Path(configured).expanduser())
    candidates.extend(
        [
            PROJECT_ROOT / "botte-secrete",
            Path.home() / "botte-secrete",
        ]
    )

    for candidate in candidates:
        resolved = candidate.resolve()
        if (resolved / "skills" / "__init__.py").is_file():
            return resolved

    checked = ", ".join(str(candidate) for candidate in candidates)
    raise SystemExit(
        "Botte source not found. Initialize the botte-secrete submodule or set "
        f"{SOURCE_ENV}. Checked: {checked}"
    )


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in {*MODULES, "check"}:
        modes = ", ".join([*MODULES, "check"])
        raise SystemExit(f"Usage: {Path(sys.argv[0]).name} <{modes}> [arguments]")

    mode = sys.argv[1]
    source_root = resolve_botte_source()
    if mode == "check":
        print(f"Botte source ready: {source_root}")
        return

    os.environ["BOTTE_PROJECT_ROOT"] = str(PROJECT_ROOT)
    os.chdir(source_root)
    sys.path.insert(0, str(source_root))
    module = MODULES[mode]
    arguments = sys.argv[2:]
    if mode == "checkup" and not arguments:
        arguments = [str(PROJECT_ROOT)]
    sys.argv = [module, *arguments]
    runpy.run_module(module, run_name="__main__", alter_sys=True)


if __name__ == "__main__":
    main()
