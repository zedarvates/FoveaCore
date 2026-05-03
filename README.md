# 👁️ FoveaEngine — Advanced 3DGS & Neural Reconstruction Engine

Welcome to **FoveaEngine**, a cutting-edge reconstruction and rendering pipeline for Godot 4.6+, specifically designed for high-fidelity VR experiences and artistic "Digital Painting" aesthetics.

---

> [!TIP]
> **🚀 WorldMirror 2.0 — Reconstruction in ~10 seconds**
> The pipeline now uses **WorldMirror 2.0** (Tencent Hunyuan) as the main backend: feed-forward video→3DGS+depth+cameras in a single forward pass.
> - **WorldMirror Mode**: ~2-10s (recommended, requires CUDA 12.4 + 8GB+ VRAM GPU)
> - **COLMAP + 3DGS Mode** (fallback): 30-90 min, requires CUDA
> See [DEPENDENCIES.md](./DEPENDENCIES.md) for configuration.

> [!IMPORTANT]
> **Dependencies**: FFmpeg (required) + COLMAP (fallback) + WorldMirror 2.0 (recommended).
> Check **[DEPENDENCIES.md](./DEPENDENCIES.md)** and run `scripts/setup_worldmirror.bat` for quick installation.

---

## 📸 Preview

![FoveaEngine Screenshot](ScreenShot/Screenshot%202026-05-03%20163554.png)

---

## 🚀 Current Status & Features

### ✅ Production-Ready

- **Core 3DGS Rendering**: PLY loading (binary), GPU bitonic sort, MultiMeshInstance3D billboard
- **GPU Compute Culling**: Backface culling + Hi-Z occlusion culling via compute shader
- **Fast-Path Rust**: Binary `.fovea` loading (16B/splat, VQ 1024 codebook)
- **WorldMirror 2.0 Bridge**: Feed-forward video→3DGS reconstruction (~10s, SOTA)
- **StudioTo3D Pipeline**: Real backend (FFmpeg extraction + WM2 inference or COLMAP SfM + 3DGS)
- **GPU Background Masking**: Compute shader `mask_background_gpu.glsl` (Studio White, Chroma, Smart)
- **Style Engine**: 6 procedural materials (stone, wood, metal, skin, fabric, glass) + FBM/Worley noise
- **Gaussian Splatting**: PLY parsing, splat rendering, export, floaters detection
- **Foveated Rendering**: 3-zone VR rendering (base/saturation/light/shadow per zone)
- **SplatBrush**: VR sculpting tool functional

### 🚧 In Progress

- **WM2 UI Controls**: WM2/COLMAP mode selector in panel (GDScript ready, .tscn added)
- **WorldMirror Camera Import**: OpenCV→Godot camera transform (code ready, partial integration)
- **Eye Tracking**: OpenXR API implemented, hardware testing required
- **Dynamic Lighting**: Calculations present, connection to Godot lights in progress
- **Hybrid Renderer**: Instantiated, pipeline integration in progress

### 📅 Roadmap

See **[ROADMAP.md](./ROADMAP.md)** for the complete plan. Key upcoming points:
- Anisotropic Splats (ellipses)
- MIP-Splatting & HLOD
- Spatial Chunking & Streaming
- Tile-Based Rasterization
- Spherical Harmonics Baking
- ComfyUI Bridge for AI generation
- WorldMirror 2.0 multi-GPU + prior injection

---

## 📂 Project Structure

| Folder | Content |
|---|---|
| `addons/foveacore/` | Core plugin (scripts, shaders, Rust, GDExtension) |
| `addons/foveacore/scenes/` | Prefabs (VR Rig, Playground, Workspace) |
| `addons/foveacore/scripts/reconstruction/` | StudioTo3D backend and UI |
| `addons/foveacore/scripts/advanced/` | High-performance rendering, VR interaction |
| `addons/foveacore/test/` | Unit tests and benchmark scenes |
| `plans/` | Detailed architecture, [Roadmap](ROADMAP.md), [WM2 integration](plans/integration_worldmirror2.md) |
| `scripts/` | Setup scripts (WorldMirror 2.0, dependencies) |
| `.github/workflows/` | CI/CD (GDScript lint, unit tests, Python validation) |

---

## 🛠️ Usage

1. **Install Plugin**: Enable `FoveaCore` in project settings.
2. **Setup Dependencies**: Run `scripts/setup_worldmirror.bat` (Windows) or `.sh` (Linux/macOS).
3. **Reconstruction**: Open `StudioTo3D` panel, select a video, check "WorldMirror 2.0", click "▶ Run".
4. **VR Rendering**: Use `FoveaSplattable` node to capture meshes and display as splats.
5. **Testing**: Launch `test/test_style_engine_desktop.tscn` for desktop testing without VR.

---

## 🤝 Acknowledgments

This project deeply benefits from open-source work that unlocked critical pipeline problems:

### ![heart](my%20icone/Earthandcheck.png) Tencent Hunyuan — HY-World-2.0

The **[Tencent Hunyuan](https://github.com/Tencent-Hunyuan/HY-World-2.0)** team developed **WorldMirror 2.0**, a revolutionary feed-forward model replacing the entire COLMAP + 3DGS pipeline with a single neural inference. Their open-source work was the keystone enabling us to move from a simulated pipeline (placeholder DA3) to real reconstruction in ~10 seconds. Their diffusers-like approach, exemplary documentation, and permissive license made this integration possible.

- **Repo**: https://github.com/Tencent-Hunyuan/HY-World-2.0
- **Paper**: https://arxiv.org/abs/2604.14268
- **Model**: https://huggingface.co/tencent/HY-World-2.0

### 3D Gaussian Splatting (Inria / Université Côte d'Azur)

The reference **[3DGS](https://github.com/graphdeco-inria/gaussian-splatting)** implementation defines the standard we follow for rendering and PLY format.

### COLMAP

The **[COLMAP](https://github.com/colmap/colmap)** Structure-from-Motion pipeline remains our reliable fallback for users without WorldMirror 2.0 compatible GPUs.

### Godot Engine

The **[Godot Foundation](https://godotengine.org/)** for their open-source engine enabling real-time VR rendering with compute shaders and GDExtension.

### Eyeline Labs / Netflix — Vista4D (CVPR 2026 Highlight)

**[Vista4D](https://github.com/Eyeline-Labs/Vista4D)** introduces *video reshooting* via 4D point clouds and video diffusion — a complementary approach to WorldMirror for novel viewpoint synthesis and 4D scene editing. Their work on point cloud editing (duplicate/remove/insert) and dynamic scene expansion directly inspires FoveaEngine's future VR editing capabilities.

### Shanghai AI Lab / CUHK — AnyRecon

**[AnyRecon](https://github.com/OpenImagingLab/AnyRecon)** proposes 3D reconstruction from sparse arbitrary views with a global memory cache and 4-step distillation — paving the way for long trajectory reconstructions (>200 frames) and fast inference for FoveaEngine.

### DiffSynth-Studio Ecosystem

All three projects (HY-World-2.0, Vista4D, AnyRecon) share **[DiffSynth-Studio](https://github.com/modelscope/DiffSynth-Studio)** and **[Wan 2.1](https://github.com/Wan-Video/Wan2.1)** as their common foundation. FoveaEngine now integrates a [unified DiffSynth bridge](addons/foveacore/scripts/reconstruction/diffsynth_bridge.py) enabling runtime backend selection. [Comparative analysis →](plans/analyse_vista4d_anyrecon.md)

---

## 📈 Progress Status

| Phase | Status |
|---|---|
| Phase 1 : Core Rendering | ✅ Completed |
| Phase 2 : GPU Pipeline | ✅ Completed |
| Phase 3 : Rust Fast-Path | ✅ Completed |
| Phase 4 : StudioTo3D + WorldMirror 2.0 | 🔄 In Progress |
| Phase 5 : VR & Eye Tracking | 🔄 In Progress |

### ✅ Completed

- Binary `.fovea` loading (Rust GDExtension, 16B/splat)
- Compute Shaders: Backface, Hi-Z Culling, Bitonic Sort
- Architecture Manager/Culler/Generator/Renderer/Composite
- StudioTo3D interface with ROI painting and GPU masking
- WorldMirror 2.0 bridge (feed-forward reconstruction)
- 25+ StyleEngine unit tests
- GitHub Actions CI/CD (lint + tests + Python validation)

### 🔄 In Progress

- WorldMirror 2.0 cameras → Godot Camera3D integration
- VR hardware validation
- Dynamic lighting connected to Godot light sources
- Artist layer rendering

### ❌ Not Implemented

- Multiplayer Sync
- Splat Decals / MIP-Splatting
- ComfyUI Bridge (Phase 4 roadmap)

---

## 🛡️ License

FoveaEngine is released under the **MIT License**.
