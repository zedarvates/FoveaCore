# FoveaEngine test fixtures

Deterministic reference data for the test suite. Regenerate with:

    godot --headless --path . -s res://test/fixtures/generate_fixtures.gd

| File | Kind | Verts | Purpose |
|---|---|---|---|
| `reference_3dgs.ply` | binary LE 3DGS | 8000 | Happy-path parse + round-trip source |
| `reference_3dgs.fovea` | golden compressed | 8000 | Round-trip / regression baseline (C3) |
| `pathological_nan.ply` | binary LE 3DGS | 64 | NaN/Inf sanitization (first 8 rows poisoned) |
| `truncated_header.ply` | malformed | 0 | Header parser must fail gracefully |

Layout of the PLY vertices (17 × float32, little-endian):
`x y z  nx ny nz  f_dc_0 f_dc_1 f_dc_2  opacity  scale_0 scale_1 scale_2  rot_0 rot_1 rot_2 rot_3`

Values are 3DGS-native: opacity is a logit (sigmoid on load), scales are in log
space (exp on load), colour is SH degree-0 (`0.5 + 0.28209 * f_dc`). Seed = 1234567.
