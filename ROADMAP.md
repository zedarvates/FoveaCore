# 🗺️ FoveaEngine Roadmap: Future Vision

This document outlines the roadmap to transform FoveaCore into a world-class hybrid (Mesh/3DGS) rendering engine, optimized for VR.

---

## 🟢 Phase 1: UX & Workflow (In Progress)
*Objective: Make the StudioTo3D pipeline accessible and robust.*

- [x] **Smart Studio Masking**: Intelligent white/black background handling.
- [x] **ROI (Region of Interest)**: Lasso system to isolate the object.
- [x] **Visual ROI Tool**: Direct drawing interface (Brush/Eraser) on preview.
- [x] **STAR Integration**: Fast pipeline (DA3 Depth) inspired by InSpatio-World.
- [x] **WorldMirror 2.0 Integration**: SOTA feed-forward backend replacing simulated STAR + slow COLMAP. [Detailed plan →](plans/integration_worldmirror2.md)
  - [x] **Python WorldMirror Bridge**: `worldmirror_bridge.py` (~60 lines) with diffusers-like API
  - [x] **GDScript Backend**: New `_run_worldmirror_path()` method in backend
  - [x] **Format Compatibility**: Verification of PLY/depth/cameras outputs → FoveaEngine pipeline
  - [ ] **Installation Script**: Setup script + CUDA 12.4 dependency checker
  - [ ] **UI Mode Selector**: COLMAP vs WorldMirror 2.0 radio in panel
- [ ] **Real-time Mask Preview**: Instant feedback of cutout settings.
- [ ] **Reset & Session Management**: Facilitate iterative testing.

## 🟠 Phase 2: Performance & Native Power (The RUST 🦀 Leap)
*Objective: Achieve stable 90 FPS in VR with millions of points.*

- [x] **Rust GDExtension**: Fast-Path pipeline implemented (ultra-fast loading without CPU parsing).
- [x] **GPU Bitonic Sorting**: Depth sorting offloaded to compute shader.
- [ ] **Multithreading**: Parallelize surface extraction across all CPU cores.
- [x] **Hi-Z Optimization**: Native Occlusion Culler branching via `CompositorEffect`.

## 🔵 Phase 3: Visual Fidelity & Stylization
*Objective: Create a unique "Digital Painting" aesthetic.*

- [ ] **Anisotropic Splats**: Move from circles to ellipses for photographic fidelity.
- [x] **Parallax Proxy Rendering**: (STAR prototype implemented) Depth simulation on simplified surfaces.
- [ ] **Vectorized Splat Dispatcher**: Batch processing (SIMD) for maximum GPU saturation.
- [ ] **Spatial Chunking & Streaming**: Divide models into spatial chunks for progressive loading (Priority to "first line" in front of camera).
- [ ] **Splat Pattern Compression (Vector Quantization)**: Use codebooks (K-means) to group redundant colors, rotations, and scales into indexed patterns.
- [ ] **Spatial Quantization (Fixed-Point Math)**: Map XYZ positions to local 16-bit grid to drastically reduce memory bandwidth.
- [ ] **Coplanar Splat Merging & Quad Simplification**: Algorithmic fusion of splats sharing same depth/surface to generate unified quads and eliminate GPU overdraw.
- [ ] **Spherical Harmonics (SH) Baking**: Bake view-dependent complex reflections into diffuse colors for matte materials (80% color weight reduction).
- [x] **Splat Backface Culling**: Compute Shader implemented (`gpu_culling_compute.glsl`) to instantly eliminate back-facing splats.
- [ ] **Temporal & Interleaved Sorting**: Asynchronous sorting of distant splats spread over multiple frames to guarantee strict 11ms GPU execution time in VR.
- [ ] **Tile-Based Rasterization**: Divide screen into tiles (16x16) in compute shader to limit sorting and blending to purely local splats (standard 3DGS approach).
- [ ] **FP16 Compute Pipeline**: Migrate compute buffers from float32 to float16 to double VRAM bandwidth and saturate modern ALUs.
- [ ] **Global Splat Instancing (Mega-Buffer)**: Render thousands of copies of same asset (e.g., forests, crowds) with single VRAM copy, via multi-transform compute shader.
- [ ] **Delta-Splat Variants (Morphs & Overrides)**: Create lightweight variants of instanced objects (color tints, local deformations) by storing and computing only the "difference" (Delta).
- [ ] **GPU-Driven Indirect Draw**: Eliminate CPU-GPU synchronizations (`rd.sync`) by letting compute shader write its own render commands (Draw indirect buffer).
- [ ] **Out-of-Core VRAM Streaming**: Load spatial chunks directly from SSD to VRAM (DirectStorage style) for infinite open worlds without saturating RAM.
- [ ] **Motion-Adaptive Splatting (Kinematic LOD)**: Directional stretching and density reduction of splats during fast motion (native motion blur) to save fillrate.
- [ ] **Artistic Shaders**: Oil painting, watercolor, and hatching effects on splats.
- [ ] **MIP-Splatting & HLOD**: Dynamic LOD system (Mesh at distance, Macro-splats at mid-distance, Micro-splats up close).
- [x] **Fast-Path Binary Asset Format (`.fovea`)**: Native container ready for GPU (Direct Memory Upload) without CPU parsing, implemented in Rust.
- [ ] **Dynamic Lighting**: Dynamic shadows adapting to Godot light sources.
- [ ] **Static vs Dynamic Splat Separation**: Differential processing (Baking/Octree for static decor, Compute Skinning & Deformation for mobile entities).

## 🟣 Phase 4: Artificial Intelligence & Cloud
*Objective: Automate asset creation.*

- [ ] **ComfyUI Bridge**: Direct API connection for generating sources from Godot.
- [ ] **Auto-ROI**: Automatic main object detection by AI.
- [ ] **Gaussian Compression**: Ultra-light file format for VR streaming.

---

*"The future of rendering is not just about displaying triangles, but about painting with volumes of light."*
