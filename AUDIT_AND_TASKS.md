# 🔍 FoveaEngine — Complete Audit & 100 Priority Tasks

> Updated 2026-04-20 | Based on exhaustive analysis of `addons/foveacore/`

---

## 📊 AUDIT SUMMARY

### General Architecture

| Component | Status | Note |
|---|---|---|
| `FoveaCoreManager` (autoload) | ✅ Solid | Well-structured pipeline |
| `SplatRenderer` | ⚠️ Prototype | ImmediateMesh → not scalable for 100k+ splats |
| `SplatGenerator` | ✅ Complete | Clean barycentric sampling |
| `StyleEngine` | ✅ Excellent | FBM + Worley + 5 materials |
| `SurfaceExtractor` | ✅ Good | Backface culling + triangle extraction |
| `TemporalReprojector` | ✅ Good | Temporal coherence OK |
| `HybridRenderer` | ⚠️ Prototype | Setup OK, not yet connected to FoveaCoreManager |
| `EyeCuller` | ✅ | Exists, referenced |
| `OcclusionCuller` | ⚠️ Stub | Hi-Z block is a `pass` — nothing done |
| `SplatSorter` | ⚠️ CPU | CPU sort on `_current_splats` → bottleneck at 90 FPS |
| `GazeTrackerLinker` | ⚠️ Prototype | Reads XR tracker API — never tested on hardware |
| `FoveaXRInitializer` | ✅ Good | Clean OpenXR initialization |
| `ProxyFaceRenderer` | ⚠️ Partial | Looks for child named "Camera" — fragile |
| `StudioTo3D Panel` | ⚠️ Prototype | ROI = hardcoded `Rect2i(100,100,800,800)` |
| `ReconstructionBackend` | ❌ Simulated | `_simulate_command_execution` with `await 3.0` |
| `StudioProcessor` | ❌ Simulated | `_simulate_extraction` with `await 1.0` |
| `GDExtension (C++)` | ⚠️ Empty | `fovea_renderer.cpp` = empty shell, DLL compiled but not functional |
| PLY Loader | ❌ ABSENT | No file to load `.ply` 3DGS |
| `.fovea` Asset Format | ❌ ABSENT | Binary container not implemented |
| GPU Compute Culling | ⚠️ Shader exists but not connected | `gpu_culling.gdshader` exists but no RenderingDevice code |
| `xr_action_map.tres` | ❌ Empty | 114 bytes file — actions not configured |

---

### 🔴 Critical Issues (Blockers)

1. **~~No PLY loader~~** — Replaced by Rust fast-path loader (`.fovea`).
2. **Simulated reconstruction backend** — All phases (FFmpeg, COLMAP, 3DGS) execute with `await timer(3.0)`. Nothing runs for real.
3. **~~Empty GDExtension~~** — Rust extension now implemented (`FoveaAssetLoader` + Culling pipeline).
4. **~~OcclusionCuller not connected~~** — Replaced by `FoveaCompositorEffect` injecting Depth Buffer into Compute Shader.
5. **`xr_action_map.tres` not configured** — Referenced in `project.godot` but almost empty (114 bytes).
6. **`HybridRenderer` not integrated** — Instantiated in manager but never used to render anything.

### 🟠 Architectural Issues

7. **`SplatRenderer` uses `ImmediateMesh`** — Recreated each frame, no GPU instancing → impossible to reach 90 FPS with 100k splats.
8. **CPU-only splat sorting** — `SplatSorter.sort_by_depth()` in GDScript, O(n log n) on main thread.
9. **`ProxyFaceRenderer` looks for child by name "Camera"** — Will break on any real VR rig.
10. **ROI in `studio_to_3d_panel.gd`** — Hardcoded to `Rect2i(100, 100, 800, 800)`. No visual drawing interface.
11. **`FoveaSplattable.is_visible_to_camera()`** always returns `true` — TODO not implemented.
12. **`calculate_blur_score()`** in `StudioProcessor` always returns `1.0`.
13. **`run_reconstruction()` in `ReconstructionManager`** does not exist — `_on_run_pressed()` calls it but method is absent.
14. **Double `ReconstructionManager` creation** — Panel creates local instance AND there is an autoload.
15. **`_exit_tree()` in `plugin.gd`** does not remove `NeuralStyle` custom type (oversight).

### 🟡 Feature Gaps

16. No splat loading from file — Only procedural generation works.
17. No real-time masking preview — User doesn't see effect of threshold slider.
18. No binary `.fovea` format — No serialization/deserialization of assets.
19. ComfyUI Bridge — Mentioned in roadmap but non-existent.
20. Anisotropic splats — Only circles (2D covariance not used in shader).

---

## ✅ 100 TASKS — COMPLETE ACTION PLAN

Tasks are numbered and ordered by priority. **🔴 Critical** unblock the system, **🟠 Important** improve reliability, **🟡 Normal** enrich features.

---

### 🔴 CATEGORY 1 — CRITICAL BLOCKERS (Do First)

- [x] **1. Implement Fast-Path loader** (`fovea_fast_path.rs`)
  > Rust ultra-fast loader implemented as replacement for slow GDScript PLY parser.

- [x] **2. Connect Fast-Path loader to GPU pipeline**
  > `gpu_culler_pipeline.gd` and `fovea_splat_renderer.gd` connected for direct VRAM injection.

- [ ] **3. Implement `run_reconstruction()` in `ReconstructionManager`**
  > Method called by `_on_run_pressed()` but doesn't exist. Orchestrates all 3 phases.

- [ ] **4. Replace `_simulate_command_execution()` with `OS.create_process()`**
  > In `ReconstructionBackend`, replace `await timer(3.0)` with real external call. Read stdout via `Thread`.

- [ ] **5. Replace `_simulate_extraction()` with real FFmpeg call**
  > In `StudioProcessor`, call `OS.create_process("ffmpeg", [...])` to extract real frames.

- [x] **6. Implement real `OcclusionCuller` (Hi-Z GPU)**
  > `FoveaCompositorEffect` intercepts opaque pass and sends depth texture to Compute Shader.

- [ ] **7. Configure `xr_action_map.tres`**
  > File is 114 bytes. Create complete action map: `grip_press`, `trigger_press`, `thumbstick_axis`, `menu_press` for both hands.

- [ ] **8. Connect `HybridRenderer` into render pipeline**
  > Instantiated in Manager but never used. Connect `generate_splats_from_mesh()` or `_apply_mode()` in `_perform_culling()`.

- [ ] **9. Implement `FoveaSplattable.is_visible_to_camera()`**
  > Replace `return true` with real frustum AABB test against current camera.

- [ ] **10. Fix double `ReconstructionManager` instantiation**
  > `studio_to_3d_panel.gd._ready()` creates new instance but autoload exists. Use `/root/ReconstructionManager`.

---

### 🔴 CATEGORY 2 — CORE RENDERING (Performance Critical)

- [x] **11. Migrate `SplatRenderer` from `ImmediateMesh` to `MultiMesh`**
  > Implemented via `FoveaSplatRenderer` using `MultiMeshInstance3D` coupled with Compute Shader.

- [x] **12. Implement GPU Bitonic Sort in Compute Shader**
  > `splat_sort_compute.glsl` added and orchestrated by `GPUCullerPipeline`.

- [x] **13. Connect Compute Culling via `RenderingDevice`**
  > `gpu_culler_pipeline.gd` functional with backface and occlusion culling.

- [ ] **14. Pre-allocate splat buffers**
  > Pre-allocate `_current_splats` to `max_splats_per_frame` to avoid dynamic resizes.

- [ ] **15. Make `SplatSorter.minimize_overdraw()` operational**
  > Verify implementation. Implement spatial clustering (3D grid) to merge redundant nearby splats.

- [ ] **16. Implement anisotropic splat shader**
  > Modify `splat_render.gdshader` to use 2D covariance. Replace `length(uv)` with ellipse matrix.

- [ ] **17. Add LOD to splats (MIP-Splatting basic)**
  > 3 levels: <2m = micro (5 splats/tri), 2-10m = normal, >10m = macro (1 splat/tri, radius x3).

- [ ] **18. Implement Spatial Chunking**
  > Divide space into 16³ chunks. Load/unload based on camera position. Necessary for large scenes.

- [ ] **19. Optimize `SurfaceExtractor` with threads**
  > Triangle traversal is single-threaded. Use `WorkerThreadPool` to parallelize per surface.

- [ ] **20. Frustum culling on CPU before GPU**
  > Fast AABB test in GDScript before sending to `_eye_culler`. Reduce nodes passed to fine culling.

---

### 🟠 CATEGORY 3 — STUDIOTO3D PIPELINE

- [ ] **21. Implement visual ROI interface**
  > Add `TextureRect` in panel to display first frame. Draw rectangle with mouse → `session.roi_rect`.

- [ ] **22. Add real-time masking preview**
  > When slider changes, extract frame, apply `mask_background()`, display result in preview.

- [ ] **23. Implement real blur detection (`calculate_blur_score()`)**
  > Replace `return 1.0` with Laplacian variance (3x3 kernel). Filter blurry frames before COLMAP export.

- [ ] **24. Detect FFmpeg/COLMAP and show missing paths**
  > At panel startup, `OS.execute("ffmpeg --version")`. Show error + download link if absent.

- [ ] **25. Implement backend error handling**
  > `error_occurred` not connected. Wire into `ReconstructionManager` and display in `log_text`.

- [ ] **26. Add per-phase progress bar**
  > 3 visual segments: Phase 1 (0-33%), Phase 2 (33-66%), Phase 3 (66-100%) with labels.

- [ ] **27. Save and restore sessions**
  > Serialize `ReconstructionSession` to JSON. Auto-save in `reconstructions/<name>/session.json`.

- [ ] **28. Implement full session reset**
  > `_on_reset_pressed()` resets UI but not `active_sessions`. Real cleanup: temp files + memory.

- [ ] **29. Add MKV and WebM video support**
  > Add mkv, webm, gif to `FileDialog` filter.

- [ ] **30. Implement full COLMAP export**
  > Verify `DatasetExporter` generates `images/` + `masks/` + `database.db` + `cameras.txt` correctly.

- [ ] **31. Integrate COLMAP "exhaustive matching" mode**
  > UI option: "exhaustive_matcher" (precise) vs "sequential_matcher" (fast for videos).

- [ ] **32. Implement async COLMAP stdout reading**
  > COLMAP shows progress. Read this stream via `Thread` to update progress bar.

- [ ] **33. Add "Dry Run" mode for testing**
  > Log parameters that would be sent without actually calling COLMAP.

- [ ] **34. Implement "Open folder" after reconstruction**
  > Button "Open folder" → `OS.shell_open(output_directory)` after reconstruction.

---

### 🟠 CATEGORY 4 — VR / EYE TRACKING

- [ ] **35. Test `FoveaXRInitializer` on real hardware**
  > Validate on Quest Pro or Vision Pro. Document errors, adjust fallbacks.

- [ ] **36. Implement desktop fallback (no headset)**
  > If OpenXR absent: orbit camera. `FoveaCoreManager` detects and adapts rendering.

- [ ] **37. Connect ray casting in `GazeTrackerLinker`**
  > `_calculate_gaze_world_hit()` projects `gaze_vec * 100.0`. Use `PhysicsDirectSpaceState3D.intersect_ray()`.

- [ ] **38. Implement Meta OpenXR eye tracking extension**
  > Support `XR_EXT_eye_gaze_interaction` for Quest Pro. Enable extension + Android permissions.

- [ ] **39. Add Apple Vision Pro eye tracking support**
  > Via ARKit or Apple OpenXR runtime. Separate code path from Meta.

- [ ] **40. Implement VRS (Variable Rate Shading) hardware**
  > Connect `_apply_foveation_settings()` to Godot 4.6 VRS texture.

- [ ] **41. Test and fix `fovea_vr_rig.tscn`**
  > Verify all nodes exist: `XRCamera3D`, two `XRController3D`.

- [ ] **42. Implement VR controllers in `splat_brush_playground.tscn`**
  > Physical input for `SplatBrush` with VR controllers.

- [ ] **43. Implement haptic vibration on SplatBrush**
  > `XRController3D.trigger_haptic_pulse()` when brush touches a splat.

- [ ] **44. Fix `ProxyFaceRenderer` to find correct camera**
  > Replace `get_node_or_null("Camera")` with `get_viewport().get_camera_3d()`.

---

### 🟠 CATEGORY 5 — GDEXTENSION / C++ / RUST

- [x] **45. Implement Bitonic Sort on GPU**
  > Moved entirely to Compute Shader rather than C++ to avoid CPU/GPU transfers.

- [x] **46. Implement Fast-Path Binary in Rust**
  > Reading `.fovea` via aligned 16-octet struct (`fovea_fast_path.rs`).

- [x] **47. Expose AssetLoader via Rust GDExtension**
  > Class `FoveaAssetLoader` properly declared and compiled with Cargo.

- [x] **48. Set up Rust GDExtension structure**
  > Cargo.toml configured with `godot-rust/gdext` dependency.

- [x] **49. Migrate sorting to GPU**
  > Replaced by `splat_sort_compute.glsl`.

- [ ] **50. Migrate `SurfaceExtractor.gd` to Rust with SIMD**
  > Triangle traversal embarrassingly parallel. `extract_visible_triangles_native()`.

- [ ] **51. Create CI/CD to compile GDExtension**
  > GitHub Actions: `foveacore.dll` (Windows), `libfoveacore.so` (Linux), `libfoveacore.dylib` (macOS).

---

### 🟡 CATEGORY 6 — `.fovea` ASSET FORMAT

- [ ] **52. Define binary `.fovea` format**
  > Specify: magic bytes, version, sections (mesh, splats, style, metadata). Doc in `plans/fovea_format_spec.md`.

- [ ] **53. Implement `.fovea` serializer**
  > `fovea_asset_writer.gd`: Mesh + Array[GaussianSplat] + FoveaStyle → binary file.

- [ ] **54. Implement `.fovea` deserializer**
  > `fovea_asset_loader.gd`: Reconstruct data from file. Register via `ResourceFormatLoader`.

- [ ] **55. Register `.fovea` as ResourceFormatLoader in Godot**
  > `plugin.gd`: `ResourceLoader.add_resource_format_loader()` so Godot recognizes `.fovea`.

---

### 🟡 CATEGORY 7 — ARTISTIC FEATURES

- [ ] **56. Finalize Splat Layers (BASE/SATURATION/LIGHT/SHADOW)**
  > `LayerType` defined but not used in rendering. Implement render pass per layer.

- [ ] **57. Implement interactive SplatBrush functional**
  > Splat collision detection (octree), modify color/opacity/radius, undo/redo stack.

- [ ] **58. Implement real `TexturedSplatGenerator`**
  > Load textures Sponge/DryBrush/Stipple, assign to splats, UV mapping on quads.

- [ ] **59. Finalize Soft Matter (Manga-style liquids)**
  > Simulation: external forces → velocity integration → position update. Max 1000 deformable splats.

- [ ] **60. Implement `SplatLightingAnimator` real**
  > Detect `DirectionalLight3D`, compute shadow direction, move SHADOW splats each frame.

- [ ] **61. Implement dynamic specular reflections**
  > Pass `light_direction` to shader. Compute `specular_intensity` per splat based on view-light angle.

- [ ] **62. Implement `HierarchicalSplatGenerator` complete**
  > 3 LOD: LOD0 (near, micro), LOD1 (mid, standard), LOD2 (far, macro) by distance.

- [ ] **63. Create Splat Decal Tool (weathering)**
  > `splat_decal.gd`: spray rust/moss/snow on surfaces. `RayCast3D` + procedural pattern.

- [ ] **64. Implement watercolor shader**
  > `artistic_watercolor.gdshader`: edge darkening, granulation, wet-in-wet. For SATURATION layer.

- [ ] **65. Implement hatching shader**
  > `artistic_hatching.gdshader`: triplanar UV + hatching texture. Orient by surface normal.

- [ ] **66. Add GLASS support in `StyleEngine`**
  > `MaterialType.GLASS` in enum but ignored. Implement `_compute_glass_color()` with fake refraction.

---

### 🟡 CATEGORY 8 — ARTIFICIAL INTELLIGENCE

- [ ] **67. Create basic ComfyUI Bridge**
  > `neural_style_bridge.gd`: HTTP to ComfyUI (port 8188), send workflow JSON, poll result.

- [ ] **68. Implement Auto-ROI by AI**
  > SAM2/rembg model for main object detection and generate `roi_rect`. Call via Python.

- [ ] **69. Create Python script `auto_roi.py`**
  > Script in `tools/` using `rembg`. Returns bbox of object. Called by Bridge.

- [ ] **70. Integrate ONNX Runtime for local inference**
  > Package lightweight ONNX model (MobileNet-SAM). Offline segmentation in StudioTo3D.

---

### 🟡 CATEGORY 9 — MULTIPLAYER / SYNC

- [ ] **71. Design splat sync protocol**
  > `plans/multiplayer_sync_spec.md`: delta encoding, batching, foveal zone priority.

- [ ] **72. Implement `network_interpolator.gd` complete**
  > Verify and wire to Manager to interpolate received splat positions via network.

- [ ] **73. Implement SplatBrush interaction sync**
  > Broadcast splat modifications to all peers via `MultiplayerSynchronizer`.

---

### 🟡 CATEGORY 10 — TOOLING & EDITOR UX

- [ ] **74. Create real-time stats panel**
  > Plugin panel `FoveaStats`: FPS, splat count, extraction time, GPU memory, reprojection ratio.

- [ ] **75. Add 3D gizmos for `FoveaSplattable` nodes**
  > Gizmo: bounding box, splat density (gradient), culling priority.

- [ ] **76. Create initial configuration wizard**
  > On first activation: detect FFmpeg/COLMAP, configure paths, suggest downloads.

- [ ] **77. Implement `.ply` drag-and-drop**
  > Drag `.ply` into scene → auto-create `FoveaSplattable` with loaded splats.

- [ ] **78. Create context menu for `FoveaSplattable`**
  > Right-click → "Generate Splats Now", "Export to .fovea", "Preview Masking", "Open in StudioTo3D".

- [ ] **79. Implement undo/redo for SplatBrush**
  > Use Godot `UndoRedo` to maintain modification stack.

- [ ] **80. Create custom inspector for `FoveaStyle`**
  > Live preview sphere when `MaterialStyleConfig` params change.

- [ ] **81. Add style presets in panel**
  > Dropdown: Photorealistic, Ghibli, Digital Painting, Oil Paint, Sketch. Auto-configure `StyleEngine`.

- [ ] **82. Create integrated benchmark tool**
  > `tools/benchmark.gd`: measure FPS at 1k/10k/100k splats, generate JSON report.

- [ ] **83. Improve StudioTo3D panel logs**
  > Color logs: ✅ success, ❌ error, ⚠️ warning. "Copy logs" and "Export .txt" buttons.

---

### 🟡 CATEGORY 11 — TESTS & VALIDATION

- [ ] **84. Create unit tests for `StyleEngine`**
  > `addons/foveacore/test/`: verify colors in [0,1], FBM convergence, Worley ∈ [0, √3].

- [ ] **85. Create unit tests for `SurfaceExtractor`**
  > Primitive meshes: cube (12 triangles), verify backface culling eliminates correct faces.

- [ ] **86. Create unit tests for `TemporalReprojector`**
  > Test: fade-in/fade-out, invalidation on movement, cleanup after `max_history_frames`.

- [ ] **87. Create non-VR desktop test scene**
  > `test_desktop.tscn`: orbit camera, various `FoveaSplattable` (cube/sphere/Suzanne). No headset required.

- [ ] **88. Create automated performance test**
  > Generate N `FoveaSplattable` with M triangles, measure frame time over 1000 frames, log JSON.

- [ ] **89. Validate StudioTo3D pipeline on real asset**
  > Real turntable → FFmpeg → COLMAP → 3DGS. Document in `tutorials/`.

- [ ] **90. Create integration tests for plugin**
  > Verify activation/deactivation OK, autoloads created/destroyed, custom types available.

---

### 🟡 CATEGORY 12 — DOCUMENTATION

- [ ] **91. Write PLY format specification**
  > `plans/ply_format_spec.md`: `x y z`, `f_dc_0/1/2`, `opacity`, `scale_0/1/2`, `rot_0/1/2/3`.

- [ ] **92. Create COLMAP setup guide**
  > `tutorials/colmap_setup.md`: download, install, PATH, first reconstruction.

- [ ] **93. Create 3DGS training guide**
  > `tutorials/3dgs_training.md`: Python, `gaussian-splatting` repo, CUDA, training from COLMAP.

- [ ] **94. Document all signals and public API**
  > Complete docstrings: `FoveaCoreManager` API, `ReconstructionManager` signals, `FoveaSplattable` events.

- [ ] **95. Update README with real status**
  > Phases 1-4 marked ✅ but incomplete. Be honest about prototype vs production.

- [ ] **96. Create CONTRIBUTING.md**
  > Conventions: GDScript snake_case, PascalCase classes, PR guide, GDExtension compilation.

- [ ] **97. Create tutorial videos or GIFs**
  > GIF: StudioTo3D in action, SplatBrush VR, toggle foveated rendering.

- [ ] **98. Write `plans/architecture_overview.md`**
  > Complete diagram: Video → StudioProcessor → DatasetExporter → COLMAP → 3DGS → PLY → FoveaSplattable → SurfaceExtractor → SplatGenerator → FoveatedController → SplatSorter → SplatRenderer.

---

### 🟡 CATEGORY 13 — HOUSEKEEPING

- [ ] **99. Fix `plugin.gd._exit_tree()`: add `remove_custom_type("NeuralStyle")`**
  > Custom type added in `_enter_tree()` but never removed. Godot warning on every reload.

- [ ] **100. Clean up remaining TODOs in code**
  > Audit `# TODO`, `# FIXME`, `# placeholder`:
  > - `fovea_splattable.gd:58` → `is_visible_to_camera()`
  > - `test_foveacore.gd:106` → `_set_style()` actually calls StyleEngine
  > - `reconstruction_backend.gd:47` → real `OS.create_process()`
  > - `studio_processor.gd:65` → real FFmpeg call
  > - `foveacore_manager.gd:170` → Hi-Z occlusion
  > - `hybrid_renderer.gd:146` → default color → StyleEngine

---

## 🗺️ RECOMMENDED PRIORITY ORDER

| Sprint | Tasks | Objective |
|---|---|---|
| Sprint 1 | #1-10, #99, #100 | Unblock system — nothing truly works without this |
| Sprint 2 | #11-20, #44 | Core Rendering — reach 90 FPS with real splats |
| Sprint 3 | #21-34 | StudioTo3D — functional video→3D pipeline |
| Sprint 4 | #35-43 | VR/XR — complete hardware validation |
| Sprint 5 | #45-51 | GDExtension — native performance |
| Sprint 6 | #52-73 | Artistic features + AI + fovea format |
| Sprint 7 | #74-98 | Polish, tools, docs, tests |

---

## 💡 DEDUCTION — WHAT'S MISSING

Here are the **structural omissions** preventing end-to-end functionality:

| # | Omission | Impact |
|---|---|---|
| 🔴 | **No PLY reader** | Cannot load real Gaussian Splats. All rendering is procedural from Godot meshes. |
| 🔴 | **FFmpeg/COLMAP backend not connected** | StudioTo3D UI "works" but does nothing real. Video→3D loop is broken. |
| 🟠 | **`run_reconstruction()` missing** | Method called by "Run" button doesn't exist. |
| 🟠 | **Systems not wired together** | `HybridRenderer`, `OcclusionCuller`, `ProxyFaceRenderer` instantiated but never used in real pipeline. |
| 🟠 | **Eye tracking never tested** | Code is correct (XR tracker API) but no hardware validation. |
| 🟡 | **No VR-free test scene** | Cannot test engine without XR headset. Desktop scene essential for daily work. |
| 🟡 | **No test data included** | No demo `.ply`. New contributors can't test anything. |

---

*"A rendering engine is like a car engine — all components may exist, but if the cables aren't connected, it won't start."*
