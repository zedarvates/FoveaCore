# 🔗 WorldMirror 2.0 Integration Plan — FoveaEngine

> **Date:** 2026-05-03 | **Author:** FoveaEngine Team
>
> Replace simulated/placeholder reconstruction backends with WorldMirror 2.0 (Tencent Hunyuan), a SOTA feed-forward model that reconstructs depth, normals, camera poses, point clouds, and 3DGS in a single forward pass.

---

## 1. CONTEXT: CURRENT RECONSTRUCTION STATE

### Current Pipeline (files involved)

```
reconstruction_manager.gd  ── orchestrates 3 phases
  ├── studio_processor.gd        Phase 1: frame extraction (real ffmpeg ✅) + GPU masking (real ✅)
  ├── reconstruction_backend.gd  Phase 2: COLMAP SfM (real ✅) OR star_bridge.py (SIMULATED ❌)
  └── reconstruction_backend.gd  Phase 3: 3DGS training (real ✅) → PLY → SplatRenderer ✅
```

### Identified Issues

| Component | Issue |
|---|---|
| `star_bridge.py:34-35` | DA3 model instantiated but **weights not loaded** — fallback heuristic (inverted luminance + Sobel) |
| `star_bridge.py:72` | Extrinsics = identity matrix, intrinsics = `[w, h, w/2, h/2]` hardcoded — **no real pose estimation** |
| `star_simulator.py` | Generates synthetic data (OK for tests, NOT for production) |
| `ply_loader.gd / studio_to_3d_panel.gd` | API mismatch: calls `load_ply()` on `PLYLoader` which exposes `load_gaussians_from_ply()` |
| COLMAP pipeline | Slow (30+ min for 10s video), requires NVIDIA GPU, manual configuration |

### What's Already Solid

- FFmpeg frame extraction and GPU masking ✅
- PLY parsing → GaussianSplat → MultiMeshInstance3D rendering ✅
- GPU bitonic depth sort + Hi-Z occlusion culling ✅
- Foveated rendering 3 zones (base/saturation/light/shadow) ✅
- `.fovea` compressed format (VQ 1024 codebook, 16B/splat) ✅
- OOM, timeout, hang detection in backend ✅

---

## 2. WORLD MIRROR 2.0 — WHAT IT BRINGS

### Technical Comparison

| Criterion | COLMAP + 3DGS (current) | WorldMirror 2.0 |
|---|---|---|
| **Reconstruction Time** | 30-90 minutes | ~2-10 seconds (single forward pass) |
| **Type** | Iterative optimization | Feed-forward (neural network) |
| **Input** | Multi-view images | Video OR multi-view images (1-32 frames) |
| **Outputs** | Sparse point cloud + 3DGS PLY | Depth maps, normals, camera poses (c2w+intrinsics), point cloud 3D, 3DGS attributes (means/scales/quats/opacities/SH) |
| **Camera Estimation** | COLMAP SfM (sometimes unstable) | Directly predicted by network |
| **Model** | Classical (SIFT + BA + densification) | Neural (~1.2B params, ViT backbone) |
| **GPU Required** | NVIDIA CUDA | CUDA 12.4 (or CPU, slow) |
| **VRAM** | 6-12 GB (3DGS training) | ~8-16 GB (depending on resolution and frame count) |
| **API** | CLI (Python scripts) | CLI + diffusers-like Python API + Gradio app |
| **Multi-GPU** | No | Yes (FSDP + Sequence Parallel + BF16) |
| **Model** | Proprietary (3DGS) + COLMAP (BSD) | Open-source (Apache/MIT-like) |
| **Maturity** | Production-proven | April 2026 release, partially open-source |

### Output Format Mapping

```
WM2 Output                    → FoveaEngine Equivalent
────────────────────────────────────────────────────────
gaussians.ply (standard PLY)  → PLYLoader.load_gaussians_from_ply() ✅ compatible
points.ply                    → EnhancedPointCloudViewer ✅ compatible
depth/*.npy                   → star_loader.gd (already designed for this) ✅
normal/*.png                  → StyleEngine / lighting ✅ minor addition
camera_params.json            → ReconstructionSession (4×4 poses) ✅ compatible
sparse/0/cameras.bin          → ColmapSparseImporter ✅ already implemented
```

---

## 3. INTEGRATION PLAN — 4 PHASES

### Phase A: WorldMirror 2.0 Backend Bridge (week 1-2) 🔴 Highest Priority

**Objective:** Replace `star_bridge.py` with a functional WorldMirror 2.0 bridge.

#### Task A1: New Python Bridge `worldmirror_bridge.py`

```python
# Replaces addons/foveacore/scripts/reconstruction/star_bridge.py
# New file: addons/foveacore/scripts/reconstruction/worldmirror_bridge.py

"""
WorldMirror 2.0 bridge for FoveaEngine.
Drop-in replacement for the STAR bridge using Tencent Hunyuan's WorldMirror 2.0.
"""
import argparse, json, sys, os
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Directory of extracted frames")
    parser.add_argument("--output", required=True, help="Workspace output directory")
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--target_size", type=int, default=952)
    parser.add_argument("--fps", type=int, default=2)
    parser.add_argument("--save_depth", action="store_true", default=True)
    parser.add_argument("--save_normal", action="store_true", default=True)
    parser.add_argument("--save_gs", action="store_true", default=True)
    parser.add_argument("--save_camera", action="store_true", default=True)
    parser.add_argument("--save_points", action="store_true", default=True)
    parser.add_argument("--save_colmap", action="store_true", default=False)
    args = parser.parse_args()

    from hyworld2.worldrecon.pipeline import WorldMirrorPipeline

    pipeline = WorldMirrorPipeline.from_pretrained('tencent/HY-World-2.0')
    pipeline(
        input_path=args.input,
        output_path=args.output,
        target_size=args.target_size,
        save_depth=args.save_depth,
        save_normal=args.save_normal,
        save_gs=args.save_gs,
        save_camera=args.save_camera,
        save_points=args.save_points,
        save_colmap=args.save_colmap,
        strict_output_path=args.output,  # flat output, no timestamp subdirs
    )

if __name__ == "__main__":
    main()
```

**Specifications:**
- CLI compatible with current GDScript backend call: `python worldmirror_bridge.py --input <frames_dir> --output <workspace>`
- Outputs placed directly in `workspace/` (no timestamp subdirectories)

#### Task A2: Modify `reconstruction_backend.gd`

Add new method `_run_worldmirror_path()`:

```gdscript
func _run_worldmirror_path(session: ReconstructionSession) -> void:
    var args := PackedStringArray([
        "worldmirror_bridge.py",
        "--input", session.output_directory + "/input",
        "--output", session.output_directory,
        "--device", "cuda",
        "--target_size", str(_target_size),      # new @export
        "--fps", str(session.extraction_fps)
    ])
    var pid := OS.create_process(python_path, args)
    await _watch_process(pid, session)  # reuse existing async loop
```

#### Task A3: Modify `reconstruction_manager.gd`

- Replace `use_fast_sync` branch with `use_worldmirror` (new flag)
- Keep COLMAP+3DGS branch as fallback for compatibility
- Full pipeline becomes: `extract → worldmirror → done` (1 step instead of 3)

#### Task A4: Install Script & Dependency Checker

```bash
# New script: scripts/setup_worldmirror.sh (and .bat for Windows)
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124
pip install -r requirements_worldmirror.txt
# Optional: FlashAttention for performance
```

---

### Phase B: Format Bridge & Conversion (week 2-3) 🟠 High Priority

**Objective:** Ensure WM2 outputs are consumable by the entire FoveaEngine chain.

#### Task B1: Fix `PLYLoader` API Mismatch

Currently `studio_to_3d_panel.gd:475` calls `_PLYLoaderScript.load_ply()` which doesn't exist. Two options:
- **Option 1 (simple):** Add wrapper `static func load_ply(path) -> Dictionary` in `PLYLoader` that calls `load_gaussians_from_ply()` and returns compatible dict
- **Option 2 (clean):** Refactor panel to use `load_gaussians_from_ply()` directly

Recommended: Option 1 for backward compatibility, Option 2 as follow-up.

#### Task B2: Import WM2 Cameras → Godot

Create `worldmirror_camera_importer.gd`:

```gdscript
class_name WorldMirrorCameraImporter
extends Node

static func import_cameras(json_path: String) -> Array[Camera3D]:
    # Read camera_params.json (WM2 format)
    # Create Camera3D nodes with extrinsics 4×4 + intrinsics
    # Convention: OpenCV → Godot (Y-up → -Y)
```

#### Task B3: Load WM2 Depth Maps into Pipeline

Modify `star_loader.gd` (or create equivalent) to load WM2 `.npy` depth maps:
- WM2 format: `float32 [H, W]`, Z-depth values
- Apply to `star_proxy.gdshader` (parallax mapping already exists)

#### Task B4: Map 3DGS Attributes

Verify WM2 PLY format compatibility with `PLYLoader.load_gaussians_from_ply()`:
- WM2 produces `gaussians.ply` in standard format (x, y, z, opacity, scale_0/1/2, rot_0/1/2/3, f_dc_0/1/2)
- `PLYLoader` parses exactly these properties → **100% compatible**
- Only check needed: property order in PLY header

---

### Phase C: UI & UX (week 3-4) 🟡 Medium Priority

#### Task C1: New "WorldMirror 2.0 (Fast)" Option in UI

In `studio_to_3d_panel.gd`, add radio button or dropdown:
- `Mode COLMAP + 3DGS` (fallback, slow, no model required)
- `Mode WorldMirror 2.0` (recommended, ~10s, requires CUDA 12.4 + HF model)

#### Task C2: Real-time 3D Preview

Inspired by WM2 Gradio app, add interactive 3D preview in Godot:
- Depth map visualization (false color)
- Point cloud preview before full import
- Normal map overlay

#### Task C3: WM2-Adapted Progress Bar

WM2 pipeline has no "percentage" like COLMAP (it's a single forward pass). Display:
- "Downloading model..." (first use, from HuggingFace)
- "Running WorldMirror 2.0..." (forward pass, ~2-10s)
- "Post-processing..." (format conversion, ~1s)

---

### Phase D: Advanced (week 5+) 🟢 Long Term

#### Task D1: Panorama Generation (HY-Pano 2.0)

When HY-Pano 2.0 opens, integrate for:
- 360° skybox generation for VR scenes
- Text-to-panorama → WorldStereo 2.0 → complete 3D world

#### Task D2: Multi-GPU Optimized

Enable FSDP + BF16 for heavy scenes (>32 frames, >500k pixels):
```python
torchrun --nproc_per_node=2 -m hyworld2.worldrecon.pipeline \
    --input_path frames/ --use_fsdp --enable_bf16
```

#### Task D3: Prior Injection for Max Quality

Allow user to inject:
- Known camera intrinsics (e.g., from VR headset calibration)
- LiDAR or COLMAP depth map (fusion with WM2)
- Via `--prior_cam_path` and `--prior_depth_path`

#### Task D4: ComfyUI Bridge (Phase 4 from ROADMAP.md)

When World Generation opens (WorldNav + WorldStereo 2.0 + WorldMirror 2.0):
- ComfyUI → WorldMirror 2.0 connection for procedural generation
- Text/Image → complete 3D world, directly in Godot

#### Task D5: WM2 as Local Service

HTTP wrapper around WM2 for:
- Background execution (no Godot blocking)
- Model cache in RAM (persistent VRAM)
- Reconstruction queue (batch processing)

---

## 4. IMPACT ON EXISTING CODE

### Modified Files

| File | Modification |
|---|---|
| `reconstruction_backend.gd` | +30 lines: new `_run_worldmirror_path()` method |
| `reconstruction_manager.gd` | +20 lines: `use_worldmirror` flag, backend call |
| `reconstruction_session.gd` | +2 fields: `use_worldmirror` (bool), `target_size` (int) |
| `studio_to_3d_panel.gd` | +50 lines: WM2 mode radio, adapted UI |
| `studio_dependency_checker.gd` | +15 lines: CUDA 12.4 + HF model check |

### Replaced Files

| Old File | New File | Reason |
|---|---|---|
| `star_bridge.py` (108 lines, simulated) | `worldmirror_bridge.py` (~60 lines, real) | Functional model vs placeholder |
| `star_simulator.py` (53 lines) | Kept for tests | Simulator useful for CI without GPU |

### Kept Files (Compatibility)

| File | Preserved Role |
|---|---|
| `studio_processor.gd` | Frame extraction + masking (still needed before WM2) |
| `dataset_exporter.gd` | Export frames/masks (still needed) |
| `reconstruction_backend.gd` | Backend process execution (reused for WM2) |
| `ply_loader.gd` | PLY parsing from output (WM2 produces standard PLY) |
| `splat_renderer.gd` | 3DGS rendering in Godot |
| `splat_sorter.gd` | GPU splat sorting |
| `floaters_detector.gd` | Post-reconstruction cleanup (WM2 can generate outliers) |

---

## 5. DEPENDENCIES & PREREQUISITES

### New Python Dependencies

```
torch==2.4.0+cu124
torchvision==0.19.0+cu124
# hyworld2 installs from cloned GitHub repo
# requirements_worldmirror.txt provided by repo
```

### GPU Required

| Configuration | Min VRAM | Estimated Time |
|---|---|---|
| NVIDIA GPU (CUDA 12.4) | 8 GB | 2-5s (8 frames) |
| NVIDIA GPU (CUDA 12.4) | 16 GB | 5-10s (32 frames, target_size=1904) |
| CPU fallback | 16 GB RAM | 30-120s (not recommended) |

### Model Storage

- WorldMirror 2.0 model: ~5 GB (auto-downloaded from HuggingFace)
- HF cache default: `~/.cache/huggingface/hub/`

---

## 6. RISKS & MITIGATIONS

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| WM2 doesn't run on AMD/Intel GPU | Medium | Medium | CPU fallback (slow) + keep COLMAP |
| WM2 API changes (still in dev) | Medium | Low | Pin version commit hash, not `main` |
| HF model unavailable/slow download | Low | High | Local mirror + cache + COLMAP fallback |
| PLY format incompatibility (non-standard props) | Low | Low | Adapt `ply_loader.gd` for variants |
| VRAM insufficient for high target_size | Medium | Medium | `disable_heads` to save VRAM |
| License incompatibility | Low | High | Verify model license (Apache/MIT-like per repo) |

---

## 7. KPIs & SUCCESS METRICS

### Technical Metrics

| Metric | Before (COLMAP+3DGS) | After (WM2) | Target |
|---|---|---|---|
| Reconstruction time (10s video) | 30-90 min | 2-10s | <15s |
| Camera pose accuracy | Variable (SfM) | Predicted (SOTA) | ATE < 0.02 |
| Point cloud completeness | Medium | High (feed-forward) | F1 > 0.40 |
| 3DGS quality | Good (7000 iter) | Good (direct) | PSNR > 28 dB |
| VRAM peak | 6-12 GB | 8-16 GB | <16 GB |
| Fallback available | Yes (COLMAP) | Yes (COLMAP kept) | 100% |

### User Metrics

-  1 click from video to viewable 3D model
- Interactive 3D preview before final import
- No manual configuration (COLMAP params hidden)

---

## 8. REFERENCES

- **WorldMirror 2.0 repo:** https://github.com/Tencent-Hunyuan/HY-World-2.0
- **WorldMirror 2.0 paper:** https://arxiv.org/abs/2604.14268
- **HuggingFace model:** https://huggingface.co/tencent/HY-World-2.0
- **WorldMirror 1.0 (legacy):** https://github.com/Tencent-Hunyuan/HunyuanWorld-Mirror
- **WorldStereo (background):** https://github.com/FuchengSu/WorldStereo
- **HY-World-2.0 product page:** https://3d.hunyuan.tencent.com/sceneTo3D

---

*Plan written 2026-05-03 — Ready for implementation.*
