#!/usr/bin/env python3
"""FoveaEngine — Type Coverage Checker (item 187)
Counts untyped variables in GDScript files and enforces decreasing threshold.

Usage:
    python3 tools/check_typing.py [--threshold 50] [scripts/]
"""

import sys
import re
from pathlib import Path

DECLARATION_PATTERN = re.compile(r'^\s*(?:var|const)\s+\w+\b(?P<suffix>.*)$')


def count_untyped(directory: str) -> dict:
    """Count untyped var/const declarations in all .gd files."""
    results = {}
    total = 0
    
    for gd_file in sorted(Path(directory).rglob("*.gd")):
        untyped_lines = []
        try:
            with gd_file.open(encoding="utf-8") as file_handle:
                for i, line in enumerate(file_handle, 1):
                    declaration = DECLARATION_PATTERN.search(line)
                    if declaration and not declaration.group("suffix").lstrip().startswith(":"):
                        untyped_lines.append((i, line.strip()))
        except (OSError, UnicodeDecodeError) as error:
            raise RuntimeError("Cannot read %s as UTF-8: %s" % (gd_file, error)) from error
        
        if untyped_lines:
            results[str(gd_file)] = untyped_lines
            total += len(untyped_lines)
    
    return results, total


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else "addons/foveacore/scripts"
    threshold = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    
    print(f"Checking untyped variables in {directory}...")
    try:
        results, total = count_untyped(directory)
    except RuntimeError as error:
        print("ERROR: %s" % error, file=sys.stderr)
        sys.exit(2)
    
    for path, lines in sorted(results.items()):
        print(f"\n  {path}:")
        for line_num, line in lines[:3]:
            safe_line = line[:80].encode("ascii", "backslashreplace").decode("ascii")
            print(f"    L{line_num}: {safe_line}")
        if len(lines) > 3:
            print(f"    ... +{len(lines) - 3} more")
    
    print(f"\n{'='*50}")
    print(f"Total untyped vars: {total}")
    print(f"Threshold: {threshold}")
    
    if total > threshold:
        print(f"FAIL: {total} > {threshold}")
        sys.exit(1)
    else:
        print(f"PASS: {total} <= {threshold}")
        sys.exit(0)


if __name__ == "__main__":
    main()
