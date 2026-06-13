# FoveaEngine — Performance Benchmark (C6)

A reproducible FPS harness for the `FoveaSplat3D` render path.

## Running

```powershell
# Windowed, foreground desktop session (NOT over RDP / headless / CI):
pwsh scripts/run_benchmark.ps1 -Splats 1000000 -Duration 12
```

or directly:

```bash
godot --path . -s res://addons/foveacore/test/fps_benchmark.gd -- \
    --splats=1000000 --duration=12 --out=user://benchmark_report.json
```

The harness generates N seeded splats, drops a `FoveaSplat3D` into a live scene,
orbits a camera for `--duration` seconds (after a fixed frame warmup so the
one-time PLY load + HLOD generation is excluded), samples real frame times, and
writes JSON:

```json
{ "splats": 1000000, "fps_avg": 0.0, "fps_1pct_low": 0.0,
  "frame_ms_avg": 0.0, "frame_ms_p99": 0.0, "meets_90fps": false,
  "gpu": "..." }
```

## Important: run it in a real foreground window

The benchmark **must** run in a normal desktop session with a visible, focused
window. Launched from CI, a background/automation shell, or `--headless`, the GPU
swap-chain is throttled or replaced by a dummy/software path and the numbers are
meaningless (we have measured multi-second "frames" that way). This is why C6 is
a **manual pre-release tool**, not a CI gate.

## Official number

> _To be filled from a foreground desktop run._

| Path | Splats | Resolution | GPU | fps_avg | fps_1pct_low | Date |
|---|---|---|---|---|---|---|
| native / instanced (`.fovea`) | 1,000,000 | 1080p | — | _TBD_ | _TBD_ | — |

**Target:** 90 FPS @ 1,000,000 splats, 1080p desktop.

## Known limitation surfaced by this harness

The headline target applies to the **native / instanced (`.fovea`) path**. The
current `.ply` path through `FoveaCoreSplatRenderer` calls
`load_and_render_splats()` on **every frame the camera moves** more than
`sort_distance_threshold` (see `fovea_core_splat_renderer.gd`, `_process`). With a
continuously orbiting camera — i.e. essentially every real virtual-production or
VR shot — this re-processes the whole cloud each frame instead of relying on the
GPU compute cull/sort. Decoupling per-frame camera motion from a full reload is a
Phase 2 rendering-performance task; until then, benchmark the `.fovea` instanced
path for representative numbers.
