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
  - [x] **Installation Script**: Setup script + CUDA 12.4 dependency checker
  - [x] **UI Mode Selector**: COLMAP vs WorldMirror 2.0 radio in panel
- [x] **DVLT (Déjà View) Integration**: Unified multi-view unposed reconstruction backend with a configurable refinement loop (K-steps) via the DiffSynth bridge.
- [x] **Real-time Mask Preview**: Instant feedback of cutout settings.
- [x] **Reset & Session Management**: Facilitate iterative testing.


## 🟠 Phase 2: Performance & Native Power (The RUST 🦀 Leap)
*Objective: Achieve stable 90 FPS in VR with millions of points.*

- [x] **Rust GDExtension**: Fast-Path pipeline implemented (ultra-fast loading without CPU parsing).
- [x] **GPU Bitonic Sorting**: Depth sorting offloaded to compute shader.
- [x] **Multithreading**: Parallelize surface extraction across all CPU cores via `FoveaThreadPool` (N threads, chunk-based decode, pre-allocated buffers).
- [x] **Hi-Z Optimization**: Native Occlusion Culler branching via `CompositorEffect`.

## 🔵 Phase 3: Visual Fidelity & Stylization
*Objective: Create a unique "Digital Painting" aesthetic.*

- [x] **Anisotropic Splats**: True ellipses via covariance codebook texture + Gaussian exp() alpha in fragment shader (real 3DGS math, graceful isotropic fallback).
- [x] **Parallax Proxy Rendering**: (STAR prototype implemented) Depth simulation on simplified surfaces.
- [x] **Vectorized Splat Dispatcher**: Multi-asset mega-buffer: tous les assets regroupés en UN SEUL dispatch GPU (`FoveaSplatDispatcher`). Subgroup Ballot: 1 atomicAdd/warp au lieu de 1/thread (~32× moins de contention). Asset-id tagging en `layer_id` byte → AABB lookup per-splat dans l'AssetData SSBO.
- [x] **Spatial Chunking & Streaming**: CPU-side block culling (4096 Morton splats) against camera frustum + file RAM caching to avoid disk read bottlenecks.
- [x] **Splat Pattern Compression (Vector Quantization)**: 8-bit color index palette (256 colors) + 1024-cluster covariance codebook via K-Means++ and Floyd-Steinberg dithering.
- [x] **Spatial Quantization (Fixed-Point Math)**: Raw XYZ coordinates mapped to 16-bit local grid mapped by AABB in both Culling Compute and Fragment shaders.
- [x] **Coplanar Splat Merging & Quad Simplification**: CPU pass `FoveaSplatCleaner.merge_coplanar()` : groupe les splats (qx/xy_bucket, qy/xy_bucket, qz/z_bucket, normale octahédrale) et fusionne les groupes en un centroïde — réduction typique 20-40% de l'overdraw GPU. Configurable via `enable_coplanar_merge` + `coplanar_z_bucket` + `coplanar_min_group`.
- [x] **Spherical Harmonics (SH) Baking**: Voir l'item ci-dessous — approach simplifiée via palette couleur 8-bit (réduction 80% des données couleur) et texture covariance codebook.
- [x] **Splat Backface Culling**: Compute Shader implemented (`gpu_culling_compute.glsl`) to instantly eliminate back-facing splats.
- [x] **Temporal & Interleaved Sorting**: GPU sort distribued over N frames via `frame_mask/frame_id` + single compute-list submit (eliminates O(log²N) CPU-GPU stalls). Configurable via `sort_interleave_factor` export (1/2/4).
- [ ] **Tile-Based Rasterization**: Divide screen into tiles (16x16) in compute shader to limit sorting and blending to purely local splats (standard 3DGS approach).
- [x] **FP16 Compute Pipeline (Depth Keys)**: Pré-calcul des clés de profondeur (`depth_precompute.glsl`) en O(N) avant le tri bitonique. `sort_bitonic_keyed.glsl` lit 1 float/comparaison au lieu de décoder 3×uint16+10 ALU → ~4-6× réduction de bande passante sur les comparaisons non-swap (majorité dans les étapes finales du bitonic).
- [x] **Global Splat Instancing**: Render thousands of copies of same asset (e.g., forests, crowds) with single VRAM copy, via GPU-driven frustum culler (`FoveaInstancedCuller`).
- [ ] **Delta-Splat Variants (Morphs & Overrides)**: Create lightweight variants of instanced objects (color tints, local deformations) by storing and computing only the "difference" (Delta).
- [ ] **GPU-Driven Indirect Draw**: Eliminate CPU-GPU synchronizations (`rd.sync`) by letting compute shader write its own render commands (Draw indirect buffer).
- [ ] **Out-of-Core VRAM Streaming**: Load spatial chunks directly from SSD to VRAM (DirectStorage style) for infinite open worlds without saturating RAM.
- [x] **Motion-Adaptive Splatting (Kinematic LOD)**: Suivi de la vélocité caméra par frame dans `FoveaSplatRenderer._process()`. Au-delà du seuil `motion_speed_threshold` : (a) réduction linéaire de `lod_ratio` vers `motion_lod_minimum`, (b) étirement des splats dans la direction de vélocité vue (`motion_stretch_factor`, GLSL). Récupération progressive (decay 15%/frame) au retour à l'arrêt.
- [x] **Artistic Shaders**: Shader `splat_render_artistic.gdshader` avec 3 modes : Oil Painting (postérisation + bords pinceau + bruit de peinture), Watercolor (falloff doux + boost saturation central + granulation aquarelle), Crosshatch (hachures doubles orientées avec densité tonale). Compatible motion-stretch + fovea LOD.
- [x] **GPU Water Splat Particles**: Shader-based simulation of volatile and recycled water splats with advection, obstacle collision/bounce, and decay. Supports local flow direction painting via `FLOW` brush mode.
- [x] **MIP-Splatting & HLOD**: Dynamic LOD system (Mesh at distance, Macro-splats at mid-distance, Micro-splats up close).
- [x] **Fast-Path Binary Asset Format (`.fovea`)**: Native container ready for GPU (Direct Memory Upload) without CPU parsing, implemented in Rust.
- [x] **Dynamic Lighting**: Dynamic shadows adapting to Godot light sources.
- [ ] **Static vs Dynamic Splat Separation**: Differential processing (Baking/Octree for static decor, Compute Skinning & Deformation for mobile entities).
- [x] **Splat Soft-Surface Physics & Interactions** *(partial)*:
  - [x] Localized spring-mass-damper deformations (squish & bounce) via `FoveaSplatCloth3D`
  - [x] Surface wave ripples (Gerstner waves, noise field, capillary ripples) via `FoveaSurfaceDeformer`
  - [x] Volume conservation — Poisson's ratio (compress normal axis, expand tangent plane)
  - [x] Analytical slope derivatives for per-splat orientation alignment on dynamic surfaces
  - [ ] **Splat Cutting & Tearing**: Dynamic mesh topology splits when force exceeds a threshold


## 🟣 Phase 4: Artificial Intelligence & Cloud
*Objective: Automate asset creation.*

- [x] **ComfyUI Bridge**: Direct API connection for generating sources from Godot.
- [ ] **Auto-ROI**: Automatic main object detection by AI.
- [ ] **Gaussian Compression**: Ultra-light file format for VR streaming.
- [ ] **Pont Agents Autonomes (Hermes) & Blender** : Création d'une passerelle entre des agents autonomes (tels que Hermes) et Blender/Godot pour la génération et l'orchestration automatique d'assets 3D. *(Réflexion et conception sérieuses planifiées d'ici 2 mois)*


## 🔴 Phase 5: Dynamic Avatars & Live Interaction (Markerless Mocap)
*Objective: Drive real-time high-fidelity 3DGS avatars via standard video feeds.*

- [ ] **Splat Markerless Mocap Bridge**: Python-based pipeline (MediaPipe / RTMPose / WHAM) to extract body poses (Skeleton3D) and facial blendshapes (Apple ARKit 52 Blendshapes) from video/webcam.
- [ ] **Fovea Live Link Receiver**: Godot UDP/WebSockets server to receive real-time facial and skeletal motion data from mobile devices and local bridges.
- [ ] **GPU Compute Skinning Shader**: GLSL compute shader (`gpu_skinning_compute.glsl`) to compute Linear Blend Skinning (LBS) or Dual Quaternion Skinning (DQS) on millions of splats at 90 FPS in VR.
- [ ] **GPU Morph Target Blendshapes**: GPU-based deformation framework for driving facial expressions of 3DGS assets via blendshapes.
- [ ] **Mocap Capture & Retargeting UI**: Editor interface to calibrate neutral pose, record mocap feeds, and bake animations directly to Godot `AnimationPlayer` tracks.
- [ ] **Automatic Weights Painting**: Tool to automatically assign skinning weights to splats based on mesh/skeleton distance, with support for manual touch-ups.

---

*"The future of rendering is not just about displaying triangles, but about painting with volumes of light."*
