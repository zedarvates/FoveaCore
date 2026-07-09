#!/usr/bin/env bash
# FoveaEngine — FIXME/TODO Scanner (item 188)
# Finds leftover TODO/FIXME/HACK markers in scripts.

echo "=== FIXME/TODO/HACK Scan ==="
grep -rn "TODO\|FIXME\|HACK\|XXX" addons/foveacore/scripts/ \
  --include="*.gd" \
  --exclude-dir=".git" 2>/dev/null \
  | grep -v "node_runner.gd" \
  | head -30

echo ""
echo "Total: $(grep -rn 'TODO\|FIXME\|HACK' addons/foveacore/scripts/ --include='*.gd' 2>/dev/null | wc -l) markers found"
