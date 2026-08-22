# Changelog — feat/worldmirror2-integration

> Branch `feat/worldmirror2-integration` — 17 commits, 33 files changed
> Merges into `main`

---

## 🩹 v0.3.1 — Release pipeline and headless stability (proposed)

### Added
- Add the provider-neutral Fovea CLI contract v1 for bounded status, unsaved
  `FoveaSplat3D` creation, and validation without a listener or file writes.
- Add real Godot 4.7 bridge tests and an optional cross-repository CLI replay
  using a temporary GDScript-only project and a one-splat PLY fixture.
- Add a content-addressed `.fovea` asset registry with SHA-256 identities,
  semantic schema versioning, ownership, biome, physics, and permission
  metadata.
- Add a transport-neutral Delta-Splat v1 codec and a revision-checked state
  owned entirely by the Godot player client. Optional external synchronization
  does not transfer splat rendering or GPU ownership away from Godot.
- Add client-side renderer packing, dynamic VRAM admission, priority-aware LRU
  eviction, and real Godot RID lifecycle management for Delta-Splat buffers.
- Promote the local Furby turntable as FoveaEngine's real-camera object stress
  case: 60 views, 18,774 trained Gaussians, and a sanitized 17,013-splat
  D3D12 runtime proof. The README, translated README, demo record, and feature
  matrix preserve its motion artifacts and non-redistributable media boundary;
  public clones continue to use the checked-in CC0 synthetic-video fallback.

### Fixes
- Restore the tracked `godot-cpp` submodule declaration so clean checkouts and release builds can initialize it.
- Make GDScript-only CI disable the native manifest before importing the project.
- Fail CI on semantic `SCRIPT ERROR` output that Godot can emit while returning success.
- Fix DVLT export typing and COLMAP image metadata serialization.
- Make cloud and lattice animation use a consistent bulk `MultiMesh` buffer in headless and Compatibility modes.
- Mark GPU skinning as GPU-only and repair cloth, cloud, lattice, and animation stress fixtures.
- Fix DeltaManager binary round-trips: the instance header is 16 bytes and
  each indexed position/color record is 32 bytes, including alpha.
- Make the master test runner reject semantic `[FAIL]` markers even when a
  generic Node wrapper exits successfully.
- Keep simulation-only segmentation away from null headless viewport textures,
  and classify renderer-dependent demos/tests outside the non-GPU gate.
- Load native flipbook frames through the canonical `.fovea` loader instead of
  relying on global ResourceLoader registration.
- Reset `FoveaSplat3D.QualityPreset.AUTO` to neutral local density and culling
  priority after an explicit preset so global manager settings take precedence.
- Reconcile stale core-specification evidence states with the validated public
  node, manager facade, and subsystem wiring contracts.
- Let the asset lifecycle smoke release `RefCounted` loaders naturally, and make
  the master runner fail closed on script and parse errors.

### Validation
- Godot compile check: 261 scripts loaded, 0 failed.
- Public-node/delegate contract: 26 assertions passed; CLI regression: 23 passed.
- Core specification/reference guard: 40 assertions passed; lifecycle smoke and
  runner semantic classifier passed 1/1 and 5/5 respectively.
- Non-GPU test gate: 58 suites passed, 0 failed, 17 GPU/integration suites skipped.
- Client MMO/Delta gates: asset registry 16/16, wire protocol 23/23,
  revisioned client state 22/22, renderer bridge 12/12, and VRAM budget 20/20.
- Focused D3D12 RID lifecycle: 17/17 on an NVIDIA GeForce RTX 5060 Ti,
  including buffer readback, LRU eviction, explicit release, and cleanup.
- The exhaustive GPU shader probe remains open: `gpu_culling_legacy.glsl`
  exposes no SPIR-V and `splat_animate_advanced.glsl` reports a stage-4
  diagnostic. These experimental shader gaps are not hidden by the focused
  RID proof.
- Public documentation gate: 86 Markdown files and 195 local links passed;
  validation-tool encoding regression passed and Botte Secrète reported no drift.
- Rust fast-path gate: 5/5 locked workspace tests, local release build, Clippy
  with warnings denied, and byte-identical reproduction of the 208-byte v2
  fixture; .NET build also passes locally.

> Do not reuse tag `v0.3.0`: it was created without a valid submodule declaration and still packaged `0.2.1` metadata.

## ✨ v0.3.0-dev — Phase 7: Dynamic Splat Animation (CPU foundation)

### New — Animation Subsystem
- **`FoveaAnimationSubsystem`**: orchestrator for all splat animation modes.
  Register/unregister animators, global intensity & time scale, CPU/GPU/AUTO backend
  selector.
- **`FoveaFlowFieldAnimator`**: curl-noise driven flow field with WIND, WATER, ORGANIC
  presets, layer-weighted per-splat displacement, foveated amplitude cutoff.
- **`FoveaMorphCovarianceAnimator`**: PULSE (uniform log-space scaling), BREATHE
  (dominant axis extend / minor contract), WOBBLE (per-splat quaternion jitter).
- **`FoveaMaterialOscillation`**: animates splat color, opacity, emission with
  configurable frequency, base/target color lerp and alpha oscillation.
- **`FoveaLodStretchAnimator`**: LOD-dependent scale stretch driven by distance
  curve (optional `Curve` resource).
- **`FoveaFlipbookAnimator`**: multi-frame splat playback with configurable FPS,
  looping, crossfade, and frame/phase metadata export.
- **`FoveaNeuralOffsetField`**: 3D grid of offset vectors with trilinear sampling,
  `bake_from_numpy()` for Python/NumPy import, optional temporal frames.
- **`FoveaBoneSkinAnimation`**: Linear Blend Skinning via `Skeleton3D`, 4-bone
  distance heuristic binding, heat-diffusion fallback.

### Tests
- 8 new test suites covering all Phase 7 animators (auto-discovered by runner).

### Changed
- `run_all_tests.gd` auto-discovers `test_*.gd` — no registration needed.
- New directory `scripts/animation/` for all animation subsystems.

## 🩹 v0.2.1 — Stability & import polish (July 2026)

### Fixes
- **Thread safety**: guard every `wait_to_finish()` join with `is_started()`
  (thread pool, floaters detector, surface extractor, streaming manager,
  dependency installer) — prevents `Condition "!thread.is_started()" is true`
  when a `start()` fails.
- **`SplatSorter` "free invalid ID"**: free the GPU uniform set before its
  storage buffers (freeing a buffer auto-invalidates the dependent set).
- **StudioTo3D log highlighter**: `CodeHighlighter` regions must start with a
  symbol — emoji/word prefixes replaced by `add_keyword_color` for ERROR/WARNING.
- **`fovea_lattice_animator.gd`**: `:=` on Variant dictionary access → `: float`
  (was a hard parse error that stopped the script from loading).

### Import
- **`FoveaSplat3D` file picker** now offers `*.splat` (J1 already supported it).

### Tooling
- **Delta Splat Painter** activated via a registration wrapper addon
  (`addons/fovea_delta_painter`) so its 3D brush toolbar actually appears.

*Repo health at release: 0 parse/type errors, startup smoke green.*

---

## 🚀 v0.2.0 — Phase 0 Foundation + Phase 1 Capture (June 2026)

### Public API & packaging (Phase 0)
- **`FoveaSplat3D`** — single public node: drop it in a scene, assign a `.fovea`/`.ply`/`.spz`/`.splat` source, done. Minimal surface (`source_path`, `enabled`, `quality_preset`, `generate_collisions`, `opacity`, `is_static`); advanced config via `get_advanced()`.
- **Table-driven plugin registration** with symmetric cleanup; experimental tools split into the optional **`fovea_labs`** plugin.
- **"Add FoveaSplat3D…"** viewport action (file picker → configured node, with undo/redo).
- **Release pipeline**: `release.yml` (tag `v*` → multi-platform GDExtension build, universal macOS dylib, zipped addon + SHA-256 + GitHub Release); macOS arm64 added to the build matrix; CI split into hard-fail non-GPU tests, informational GPU tests, a startup non-crash matrix, and a lavapipe visual-regression job.

### Import — mobile / SOTA formats (Phase 1, Chantier J)
- **`SplatFormatLoader`** routes by extension: `.ply` → PLYLoader (unchanged), **`.splat`** → new 32-bytes/splat binary parser (antimatter15 / Luma / Polycam exports). `.spz`/`.sog` stubbed (J2/J3). 14/14 round-trip tests.

### Capture → asset (Phase 1, Chantier F)
- **`FoveaDependencyManager`** (unified tool status/resolution, honors `[fovea] tools/*_path`) and **`FoveaDependencyInstaller`** (in-editor download + extract + portable Python/pip post-install).

### In-editor tooling
- Delta-splat painting (manager + 3D brush) activated via a registration wrapper addon; lattice/cloud animators; GPU skinning; indirect-draw / instance culling; octree & LOD-texture bakers; mobile presets; live-link receiver; mocap bridge.

### Fixes
- PLYLoader infinite loop on truncated headers (EOF guard).
- `fovea_lattice_animator.gd` Variant type-inference parse error.
- `splat_sorter.gd` "free invalid ID" (free uniform set before its buffers).
- StudioTo3D log highlighter "color regions must start with a symbol" (×5).
- `SplatSorter`/`FoveaStreamingManager` headless null-safety + `wait_to_finish` guards.

---

## 🛠️ v0.1.2 — Import, Export, Compression, Segmentation, & Editor Preview (June 2026)

### 🚀 New Features & Enhancements
- **Multi-Format Export & Compression**: Overhauled the export workflow to support saving reconstructed splats as standard `.ply` or highly-compressed binary `.fovea` files. File dialog now automatically handles missing extensions based on user choice.
- **Editor 3D Viewport Preview**: Converted `fovea_splattable.gd` and `splat_renderer.gd` to `@tool` scripts, allowing direct rendering of loaded `.ply` splats inside Godot's 3D editor viewport without running the game.
- **Splat Import & Conversion**: Exposed inspector-friendly buttons on `FoveaSplattable` to import external PLY files, apply custom `style_override` values, and batch compress/export them to `.fovea` format directly from the editor.
- **AI-Driven Segmentation & Tags**: Wired up a trigger in the `FoveaSplattable` inspector to query `FoveaSegmentationBridge` with custom labels (e.g. "liquid", "wood", "cloth", "stone"), back-projecting the matched elements to classification layers saved inside the `.fovea` binary.
- **Null Safety in Editor**: Guarded camera distance calculations and CPU/GPU sorting inside `splat_sorter.gd` against null cameras, preventing editor crashes when no active gameplay camera is registered.
- **Splat Layer & Dither Seed Propagation**: Fixed a structural omission in `fovea_splat_subsystem.gd` and `fovea_core_splat_renderer.gd` where `layer_type` and `dither_seed` were lost during frame-by-frame packing and CPU processing. Dynamic and segmented splats now preserve their classification layers and noise seeds correctly down to the GPU shaders.

---

## 🛠️ Sprint 4 — StudioTo3D & Integration Polish (June 2026)

### 🐛 Pipeline & Integration Fixes
- **FFmpeg Overwrite Prompt**: Added `-y` flag to FFmpeg extraction commands to bypass overwrite prompts and resolve pipeline freezes.
- **Process Frame Deadlock**: Swapped `process_frame` yields with short timers (`create_timer(0.01)`) to avoid viewport freezes when the editor goes idle.
- **Thread Signal Safety**: Replaced unsafe deferred string-based signal emission with the modern, thread-stable `Signal.emit.call_deferred(...)` syntax.
- **COLMAP Workspace Skip**: Removed pre-creation of empty `sparse` directories to prevent COLMAP's automatic reconstructor from skipping mapping.
- **Python Bridge Paths**: Globalized Python script bridge execution using absolute paths to resolve working directory script loading errors.
- **Automatic Scene Instancing**: Enhanced `studio_to_3d_panel.gd` to automatically instantiate a `FoveaSplattable` node under the active edited 3D scene root and set its owner upon successful reconstruction.
- **COLMAP SfM Failure Handling**: Fixed a critical pipeline bug where Phase 2 (SfM) verification failures (such as a missing `sparse/0` directory when COLMAP failed to find a good initial pair) were ignored, incorrectly proceeding to Phase 3 (3DGS training). The pipeline now correctly halts, marks the session as `"Erreur"`, and propagates the failure. Added dry-run safety to output verification to prevent integration test failures in headless test runners.
- **Documentation**: Updated `README.md` to reflect proper `FoveaSplattable` properties and describe the automatic scene integration feature.

---

## 🛠️ Sprint 4 — Audit Corrections & Architectural Decomposition (May 2026)

### 📐 FoveaCoreManager Decomposition (Subsystems)
- **`fovea_vr_subsystem.gd` [NEW]** — Manages OpenXR initialization lifecycle and broadcasts `xr_initialized` and `xr_unavailable` signals.
- **`fovea_foveated_subsystem.gd` [NEW]** — Directs the `FoveatedController` lifecycle and handles gaze updates, caching calculations to avoid redundant computations.
- **`fovea_splat_subsystem.gd` [NEW]** — Orchestrates Gaussian splat generation, occlusion filtering, sorting (GPU/CPU), and submission to the renderer.
- **`foveacore_manager.gd` [REFACTOR]** — Decomposed from a 342-line god object to a lean 175-line high-level orchestrator. The public API has been fully preserved.

### 🧹 GPU Splat Cleaning Integration (P3 Audit)
- **`fovea_splat_cleaner.gd` [NEW]** — Handles filtering of NaNs/Infs, floater splats (via SpatialHashGrid), and decimation.
- **`fovea_splat_renderer.gd` [MODIFIED]** — Integrates `FoveaSplatCleaner` directly into the GPU byte-stream loading pipeline, performing fast parallel filtering on raw GPU bytes before batch decoding (0 extra allocations).

### 🐛 Critical Bug Fixes & Optimizations (P0/P1/P2 Audit)
- **BUG-01 (Clay Deformer)** — Removed redundant `_process` update loop inside `FoveaClayDeformer` which was double-calling `deform_multimesh` each frame and doubling the deformation magnitude.
- **BUG-02 (Voxelizer Guard)** — Enhanced `FoveaVoxelizer` to strictly validate file paths, checking for the `.fovea` extension and matching the 8-byte `FOVEA_3D` magic header before parsing.
- **PERF-01 (Non-Blocking Collisions)** — Deferred the expensive collision shape generation in `FoveaSplattable` via `call_deferred()` to eliminate 200-500ms main-thread freezes during scene loading.
- **PERF-04 (Batch Decoding)** — Replaced individual per-splat decode iterations with high-speed bulk `PackedFloat32Array` writes to `multimesh.transform_array` and `custom_data_array`, speeding up decode times by **10x to 50x**.
- **INC-01 (Migration Notice)** — Marked the outdated `ply_file_path` as `@deprecated` with interactive warnings.
- **INC-03 (Tests Cleanup)** — Relocated `test_clay_deformer.gd` under `addons/foveacore/test/` for clean directory structures.
- **INC-04 (Editor Registration)** — Registered new subsystems and modules (`FoveaVRSubsystem`, `FoveaFoveatedSubsystem`, `FoveaSplatSubsystem`, `FoveaClayDeformer`, `FoveaVoxelizer`, and `FoveaSplatCleaner`) in `plugin.gd` so they appear correctly in the Godot inspector.

---


## 🔬 WorldMirror 2.0 — Reconstruction SOTA

### Backend Bridge (Phase A)
- **`worldmirror_bridge.py`** — Drop-in replacement for simulated `star_bridge.py`. Uses Tencent Hunyuan's `WorldMirrorPipeline` with HuggingFace model auto-download. Feed-forward video→3DGS+depth+cameras in ~10s.
- **`reconstruction_backend.gd`** — New `_run_worldmirror_path()` method. Priority: WM2 > STAR > COLMAP.
- **`reconstruction_manager.gd`** — `run_worldmirror()` single-pass pipeline. Replaces SfM + 3DGS training. Config propagation for `worldmirror_bridge_script`.
- **`reconstruction_session.gd`** — `use_worldmirror` flag + `target_size` field.
- **`studio_dependency_checker.gd`** — `is_worldmirror2_ready()` / CUDA 12.4 check.

### Format Bridge (Phase B)
- **`worldmirror_camera_importer.gd`** — Parses WM2 `camera_params.json`, OpenCV→Godot transform (diag(1,-1,-1,1)).
- **`worldmirror_depth_loader.gd`** — Loads WM2 `depth/*.png`, ImageTexture array for preview.

### UI Integration (Phase C)
- **`studio_to_3d_panel.tscn`** — WM2Row: checkbox, slider (518-1904px), status label. Run button + AutoRun checkbox. Debug mode + Clean floaters.
- **`studio_to_3d_panel.gd`** — `_on_wm2_mode_changed`, `_on_wm2_target_changed`, `_update_wm2_status`. PLY reload adapted for WM2 `gaussians.ply`.

### DiffSynth Unified Bridge
- **`diffsynth_bridge.py`** — Unified CLI: `--backend worldmirror2|vista4d|anyrecon`. Dispatch to 3 backends, shared output format.
- **`analyse_vista4d_anyrecon.md`** — Comparative analysis: HY-World-2.0 vs Vista4D vs AnyRecon. Convergence table, feature mapping, unified architecture.

---

## 🐛 Bug Fixes (Critical)

| Bug | File | Fix |
|---|---|---|
| Backface culling commented out | `gpu_culling_compute.glsl` | Decode octahedral normals from PackedSplat, enable NdotV discard |
| CPU sort on main thread | `foveacore_manager.gd:219` | GPU bitonic sort via SplatSorter instance, CPU fallback for >65k |
| `calculate_blur_score()` placeholder | `studio_processor.gd` | Variance of Laplacian (3×3 kernel, [0,1] normalization) |
| PLYLoader API mismatch | `studio_to_3d_panel.gd` | `load_ply()` → `load_gaussians_from_ply()` |
| Duplicate `ply_loader.gd` | `scripts/` | Removed old `PlyLoader` (lowercase) keeping `PLYLoader` |
| ProxyFaceRenderer uncabled | `foveacore_manager.gd` | Auto-attached via `register_splattable()`, LOD switch at 30m |
| HybridRenderer placeholder colors | `hybrid_renderer.gd` | StyleEngine integration (`compute_color` procedural) |
| Broken signal paths in .tscn | `studio_to_3d_panel.tscn` | Fixed VBox→VSplit/TopScroll/VBoxTop + added missing connections |
| Cargo.toml unstable | `shaders/Cargo.toml` | Pinned gdext: `branch=master` → `tag=v0.2.1` |
| floaters_detector TODO | `floaters_detector.gd` | Referenced existing SpatialHashGrid for O(1) neighbor queries |
| floaters_detector logic | `floaters_detector.gd:168` | `for t_results in results: floating.append_array(t_results)` → `floating.append_array(results)` (itération sur entiers au lieu du tableau) |
| foveated_enabled gating pipeline | `foveacore_manager.gd:183` | `_perform_culling` conditionné par `foveated_enabled` → bloquait tout le rendu via toggle T |
| vr_enabled bloquait desktop | `foveacore_manager.gd:150` | `_process` conditionné par `vr_enabled` → pipeline inactif sans casque |
| _set_style non implémenté | `test_foveacore.gd:103` | TODO remplacé par création d'un `FoveaStyle` + appel à `manager.set_style()` |
| triangle.normals sans vérif | `temporal_reprojector.gd:146` | Accès `normals[0]` sans garde → crash si normales absentes |
| Camera direction faussée | `proxy_face_renderer.gd:78` | `-_camera.global_transform.origin.normalized()` → `-_camera.global_transform.basis.z.normalized()` |
| Camera jamais trouvée | `proxy_face_renderer.gd:47` | `get_node_or_null("Camera")` → `get_viewport().get_camera_3d()` avec réessai dans `_process` |
| look_at sur camera null | `proxy_face_renderer.gd:143` | `look_at(_camera.global_transform.origin, ...)` sans guard null → crash |
| MultiMesh recréé chaque frame | `splat_renderer.gd:78` | `_setup_multimesh()` déplacé dans `_ready()`, plus d'appel dans `load_splats` |

---

## 🚀 GPU Optimizations

- **`procedural_noise.glsl`** — FBM + Worley compute shader → 64³ 3D texture. Audit #13.
- **`gpu_noise_generator.gd`** — Dispatch wrapper, CPU fallback via `buffer_get_data`.
- **`gpu_culling_compute.glsl`** — Backface culling enabled (~40-50% splats discarded).
- **`foveacore_manager.gd`** — GPU sort for non-.fovea splats (≤65536).

---

## 🧪 Testing & CI/CD

- **`test_style_engine.gd`** — 25+ unit tests: all 7 materials, roughness ranges, specular, bump, glass alpha, noise determinism.
- **`test_surface_extractor.gd`** — 15 unit tests: front/back facing, triangle area, edge cases.
- **`test_style_engine_desktop.tscn`** — Minimal desktop test scene (no VR required).
- **`.gdlintrc`** — GDScript linting config (gdtoolkit).
- **`.github/workflows/ci.yml`** — 3 jobs: lint GDScript, unit tests (matrix), Python validation.

---

## 📦 Setup & Dependencies

- **`setup_worldmirror.bat/.sh`** — PyTorch CUDA + HY-World-2.0 clone + pip install.
- **`setup_diffsynth.bat/.sh`** — DiffSynth-Studio + Flash Attention + WM2 chaining.
- **`requirements_worldmirror.txt`** — Pinned torch/torchvision versions + instructions.

---

## 📐 Refactoring

- **`studio_roi_painter.gd`** — ROI painting dialog (142 lines, extracted from 748-line monolith).
- **`studio_preview_manager.gd`** — Preview texture + shader params (69 lines, extracted).
- **`studio_to_3d_panel.gd`** — 812→687 lines (split into 3 components).
- **`plugin.gd`** — 7 new custom types registered. Fixed PLYLoader name.

---

## 📝 Documentation

- **`README.md`** — Full rewrite: WM2 status, features list, acknowledgments (Tencent Hunyuan, Vista4D, AnyRecon, 3DGS, COLMAP, Godot), Earthandcheck.png icon.
- **`ROADMAP.md`** — Phase 1 updated with WM2 sub-tasks.
- **`DEPENDENCIES.md`** — WorldMirror 2.0 section with installation guide.
- **`plans/integration_worldmirror2.md`** — 380+ line technical integration plan (4 phases, code snippets, risk matrix, KPIs).

---

## 📊 Stats

| Metric | Value |
|---|---|
| Commits | 16 |
| Files changed | 28 |
| Lines added | ~2150 |
| Lines deleted | ~295 |
| Audit recs resolved | 15/15 |
| Unit tests added | 40+ |
| New classes | 7 |
| Bug fixes (this pass) | 9 |

*Generated 2026-05-05*
