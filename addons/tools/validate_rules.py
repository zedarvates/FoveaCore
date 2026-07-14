#!/usr/bin/env python3
"""FoveaEngine — CLAUDE.md Rule Validator (item 190)
Checks all Phase 7 scripts against coding rules:
- No blocking _ready() calls
- No set_instance_* loops
- Null guards for Vulkan
"""

import sys
import re
from pathlib import Path

RULES = [
    ("Blocking _ready()", r'_ready\(\)[\s\S]{0,200}await\s+(create_timer|get_tree\(\).create_timer)'),
    ("set_instance_* loop", r'for\s+\w+\s+in\s+range\([^)]+\)[\s\S]{0,50}set_instance_'),
    ("Missing null guard", r'RenderingDevice\(\)'),
]

def check_scripts(directory: str) -> list:
    issues = []
    for gd_file in sorted(Path(directory).rglob("*.gd")):
        try:
            content = gd_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            raise RuntimeError("Cannot read %s as UTF-8: %s" % (gd_file, error)) from error
        for rule_name, pattern in RULES:
            if re.search(pattern, content, re.DOTALL):
                issues.append((str(gd_file), rule_name))
    return issues

def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else "addons/foveacore/scripts/animation"
    try:
        issues = check_scripts(directory)
    except RuntimeError as error:
        print("ERROR: %s" % error, file=sys.stderr)
        sys.exit(2)
    
    if issues:
        print(f"\nFAIL: Rule violations found ({len(issues)}):")
        for path, rule in issues:
            print(f"  {path}: {rule}")
        sys.exit(1)
    else:
        print(f"PASS: All rules pass ({directory})")
        sys.exit(0)

if __name__ == "__main__":
    main()
