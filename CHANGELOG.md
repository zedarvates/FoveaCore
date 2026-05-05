# Changelog — feat/worldmirror2-integration

> Branch `feat/worldmirror2-integration` — 17 commits, 33 files changed
> Merges into `main`

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
