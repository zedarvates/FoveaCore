# FoveaCore 🔷

[![Godot](https://img.shields.io/badge/Godot-4.6+-478CBF?logo=godot-engine&logoColor=white)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)]()
[![Status](https://img.shields.io/badge/status-active-brightgreen.svg)]()
[![VR](https://img.shields.io/badge/VR-OpenXR-orange)]()

**Next-generation hybrid rendering engine for Godot 4** — combining structural low-poly meshes with real-time 3D Gaussian Splatting (3DGS), feed-forward neural reconstruction, and a procedural style engine. Designed for expressive, high-performance VR on accessible hardware.

---

> [!TIP]
> **WorldMirror 2.0 — 3DGS Reconstruction in ~10 seconds**
> The pipeline uses Tencent Hunyuan WorldMirror 2.0 as the main backend: feed-forward video → 3DGS + depth + cameras in a single forward pass.
> - **WorldMirror Mode**: ~2-10s (recommended, requires CUDA 12.4 + 8GB+ VRAM)
> - **COLMAP + 3DGS Mode** (fallback): 30-90 min
> See [DEPENDENCIES.md](./DEPENDENCIES.md) for setup.

---

## Preview

![FoveaEngine Screenshot](ScreenShot/Screenshot%202026-05-03%20163554.png)

---

## Core Innovation Areas

### 🔷 Hybrid Mesh + 3DGS Rendering
- **Structural low-poly geometry** with dynamic LOD
- **Real-time Gaussian Splatting** — PLY, `.fovea` binary (Rust fast-path), GPU compute pipeline
- **Foveated rendering** for VR — OpenXR eye tracking, neural foveation, layered LOD
- **GPU compute culling** — backface culling (compute shader) + Hi-Z occlusion culling
- **Anisotropic splats** — true ellipses via covariance codebook texture + Gaussian exp() alpha

### 🔷 StudioTo3D — Video → 3DGS Pipeline
A complete pipeline to turn video footage into Gaussian Splat assets:

1. **Smart masking** — white/chroma/luma background removal + ROI lasso tool
2. **WorldMirror 2.0** — feed-forward reconstruction (CUDA, ~10s)
3. **COLMAP fallback** — SfM + 3DGS training (30-90 min)
4. **GPU cleaning** — NaN/Inf removal, floater filtering via spatial hash grid, decimation
5. **SplatBrush** — VR sculpting and deformation in real time

### 🔷 Advanced GPU Pipeline
- **GPU bitonic sort** — depth sorting fully on compute shader (0 CPU overhead)
- **Temporal & interleaved sorting** — distributed over N frames to eliminate CPU-GPU stalls
- **FP16 depth keys** — pre-computed depth keys before sorting (~4-6× bandwidth reduction)
- **Motion-adaptive LOD** — kinematic LOD: stretch splats and reduce density during fast camera movement
- **Vectorized splat dispatcher** — all assets in a single GPU dispatch with subgroup ballot (32× less contention)
- **Spatial chunking & streaming** — Morton-code block culling + file RAM caching
- **Coplanar splat merging** — ~20-40% overdraw reduction via centroid fusion

### 🔷 Vector Quantization & Compression
- **8-bit color palette** (256 colors) with Floyd-Steinberg dithering
- **1024-cluster covariance codebook** via K-Means++
- **Spatial quantization** — XYZ → 16-bit local grid (AABB-mapped)
- **`.fovea` binary format** — native container for GPU direct-memory upload (Rust)

### 🔷 Artistic Style Engine
- **6 procedural materials** — stone, wood, metal, skin, fabric, glass
- **FBM/Worley noise** generation via GPU compute
- **Artistic shaders** — Oil Painting (posterized + brush edges), Watercolor (soft falloff + granulation), Crosshatch (dual-oriented hatching)
- **Neural style bridge** — ComfyUI integration for AI-assisted texturing

### 🔷 VR & Interaction
- **OpenXR** initialization and lifecycle management
- **Foveated rendering** — layered LOD controller, gaze tracking
- **Proxy face rendering** — parallax depth simulation for billboard faces
- **Splat interaction** — FoveaClayDeformer for real-time splat deformation
- **Fast-Path Rust** GDExtension for splat baking

---

## Architecture

```
FoveaCore (Godot 4 Addon)
├── addons/foveacore/
│   ├── scenes/                    # Prefabs (VR Rig, Playground, Workspace)
│   │   ├── fovea_vr_rig.tscn
│   │   ├── studio_workspace.tscn
│   │   └── splat_brush_playground.tscn
│   ├── scripts/
│   │   ├── foveacore_manager.gd      # High-level orchestrator (175 lines)
│   │   ├── fovea_vr_subsystem.gd     # OpenXR lifecycle
│   │   ├── fovea_foveated_subsystem.gd  # Foveated rendering
│   │   ├── fovea_splat_subsystem.gd  # Splat orchestration
│   │   ├── fovea_splat_renderer.gd   # GPU splat rendering
│   │   ├── fovea_splat_cleaner.gd    # NaN/Inf/floater removal
│   │   └── ... (50+ scripts)
│   ├── scripts/reconstruction/       # StudioTo3D backend
│   │   ├── reconstruction_manager.gd
│   │   ├── worldmirror_bridge.py     # Python backend
│   │   └── studio_to_3d_panel.gd    # UI panel
│   ├── scripts/advanced/             # High-performance rendering
│   │   ├── layered_splat_generator.gd
│   │   ├── splat_brush_engine.gd
│   │   ├── neural_style_bridge.gd
│   │   └── game_ready_optimizer.gd
│   ├── shaders/                      # GLSL + Godot shaders
│   │   ├── splat_render.gdshader
│   │   ├── splat_render_artistic.gdshader  # Oil/Watercolor/Crosshatch
│   │   ├── gpu_culling_compute.glsl
│   │   ├── sort_bitonic_keyed.glsl   # GPU bitonic sort
│   │   ├── depth_precompute.glsl     # FP16 depth keys
│   │   └── ... (20+ shaders)
│   ├── gdextension/                  # C++ GDExtension
│   │   └── src/fovea_renderer.cpp
│   ├── rust/                         # Rust fast-path
│   │   └── splat_sorter/
│   │       └── src/lib.rs
│   └── test/                         # Benchmarks + unit tests
├── plans/                            # Architecture docs, roadmaps
├── scripts/                          # Setup scripts
│   ├── setup_worldmirror.sh
│   └── setup_diffsynth.sh
└── tutorials/
    └── get_started.md
```

---

## Quick Start

**Requirements:** Godot 4.6+, FFmpeg. For reconstruction: CUDA 12.4 + 8GB+ VRAM GPU.

```bash
# Clone
git clone https://github.com/zedarvates/FoveaCore.git

# Enable the addon in Godot 4:
#   Project Settings → Plugins → FoveaCore → Enable

# For reconstruction (WorldMirror 2.0 — recommended):
bash scripts/setup_worldmirror.sh

# For reconstruction (DiffSynth — alternative):
bash scripts/setup_diffsynth.sh

# Open a test scene:
#   test/test_foveacore.tscn          — Basic splat rendering
#   addons/foveacore/scenes/studio_workspace.tscn — StudioTo3D pipeline
#   addons/foveacore/scenes/splat_brush_playground.tscn — VR sculpting
```

### Basic Usage (GDScript)

```gdscript
# Add a FoveaSplattable node
var splattable = FoveaSplattable.new()
splattable.ply_path = "res://path/to/model.ply"
add_child(splattable)

# The splat loads automatically. Toggle visibility:
splattable.show_splats = true
splattable.show_mesh = false  # Hide original mesh, show splats only
```

---

## Feature Status

| Area | Status | Details |
|------|--------|---------|
| **Core 3DGS Rendering** | ✅ Production | PLY loading, GPU bitonic sort, MultiMeshInstance3D |
| **GPU Compute Culling** | ✅ Production | Backface + Hi-Z occlusion culling |
| **Fast-Path Rust** | ✅ Production | Binary `.fovea` loading (16B/splat, VQ 1024 codebook) |
| **WorldMirror 2.0** | ✅ Production | Feed-forward video→3DGS (~10s) |
| **StudioTo3D Pipeline** | ✅ Production | FFmpeg + WM2/COLMAP reconstruction UI |
| **GPU Background Masking** | ✅ Production | White/Chroma/Smart compute shader |
| **Style Engine** | ✅ Production | 6 materials + FBM/Worley noise |
| **Artistic Shaders** | ✅ Production | Oil painting, watercolor, crosshatch |
| **Motion-Adaptive LOD** | ✅ Production | Kinematic LOD with decay |
| **SplatBrush (VR)** | ✅ Production | Interactive splat deformation |
| **Vectorized Splat Dispatch** | ✅ Production | Single GPU dispatch, subgroup ballot |
| **Coplanar Splat Merging** | ✅ Production | ~20-40% overdraw reduction |
| **Spatial Chunking & Streaming** | ✅ Production | Morton-code + RAM caching |
| **VQ Compression** | ✅ Production | 8-bit color + 1024-cluster codebook |
| **Splat Cleaning** | ✅ Production | NaN/Inf/floater removal in GPU pipeline |
| **Anisotropic Splats** | ✅ Production | True ellipses via covariance |
| **Layered Splatting** | 🚧 Prototype | Structure exists, rendering layer not wired |
| **Dynamic Lighting** | 🚧 Prototype | Calculations done, Godot light connection pending |
| **Hybrid Renderer** | 🚧 Prototype | Instantiated, pipeline integration underway |
| **ComfyUI Bridge** | 🗺️ Planned | AI generation directly from Godot |
| **MIP-Splatting / HLOD** | 🗺️ Planned | Dynamic LOD system |
| **Tile-Based Rasterization** | 🗺️ Planned | Screen tiles for local sorting/blending |
| **Multiplayer VR Sync** | 🗺️ Planned | Shared scene across network |

---

## Development Phases

✅ **Phase 1 — Core Rendering** → Mesh/splat rendering, GPU pipeline  
✅ **Phase 2 — GPU Compute** → Bitonic sort, occlusion culling, Rust fast-path  
✅ **Phase 3 — Visual Fidelity** → Anisotropic splats, VQ, artistic shaders, LOD  
🔄 **Phase 4 — StudioTo3D** → WorldMirror 2.0, UI, masking  
🔄 **Phase 5 — VR & Eye Tracking** → OpenXR, foveation, interaction  
🗺️ **Phase 6 — AI & Cloud** → ComfyUI bridge, auto-ROI, compression

---

## Related Projects

- [Hermes Brain](https://github.com/zedarvates/hermes-brain) — Cognitive architecture
- [CogniARC](https://github.com/zedarvates/cogniarc) — ARC-AGI-3 solver
- [Ultra Pipeline Framework](https://github.com/zedarvates/ultra-pipeline-framework) — DAG orchestration
- [StoryCore Engine](https://github.com/zedarvates/storycore-engine) — Media pipeline

---

## License

MIT
