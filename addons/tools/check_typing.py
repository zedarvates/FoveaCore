#!/usr/bin/env python3
"""FoveaEngine — Type Coverage Checker (item 187)
Counts untyped variables in GDScript files and enforces decreasing threshold.

Usage:
    python3 tools/check_typing.py [--threshold 50] [scripts/]
"""

import sys
import re
import os
from pathlib import Path

UNTYPED_PATTERN = re.compile(r'^\s*(var|const)\s+(\w+)\s*(?!=|=)\s*(?![\w.]+:)')


def count_untyped(directory: str) -> dict:
    """Count untyped var/const declarations in all .gd files."""
    results = {}
    total = 0
    
    for gd_file in sorted(Path(directory).rglob("*.gd")):
        untyped_lines = []
        with open(gd_file) as f:
            for i, line in enumerate(f, 1):
                if UNTYPED_PATTERN.search(line):
                    untyped_lines.append((i, line.strip()))
        
        if untyped_lines:
            results[str(gd_file)] = untyped_lines
            total += len(untyped_lines)
    
    return results, total


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else "addons/foveacore/scripts"
    threshold = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    
    print(f"Checking untyped variables in {directory}...")
    results, total = count_untyped(directory)
    
    for path, lines in sorted(results.items()):
        print(f"\n  {path}:")
        for line_num, line in lines[:3]:
            print(f"    L{line_num}: {line[:80]}")
        if len(lines) > 3:
            print(f"    ... +{len(lines) - 3} more")
    
    print(f"\n{'='*50}")
    print(f"Total untyped vars: {total}")
    print(f"Threshold: {threshold}")
    
    if total > threshold:
        print(f"❌ FAIL: {total} > {threshold}")
        sys.exit(1)
    else:
        print(f"✅ PASS: {total} <= {threshold}")
        sys.exit(0)


if __name__ == "__main__":
    main()
