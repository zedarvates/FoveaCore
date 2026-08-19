# AGENTS.md - FoveaEngine Development Guide

## Build & Test Commands
- **GDExtension**: `scons target=template_debug platform=windows` (if source available)
- **Godot Project**: Open in Godot 4.7.dev5 Mono Official (or later 4.7 versions)
- **Test Scene**: `godot --scene res://demo/drop_a_ply.tscn`
- **Reconstruction Tools**:
  - `python addons/foveacore/scripts/reconstruction/diffsynth_bridge.py`: Unified DiffSynth bridge (WorldMirror/DVLT/Vista4D).
  - `python addons/foveacore/scripts/reconstruction/worldmirror_bridge.py`: WorldMirror 2.0 bridge.
  - `python addons/foveacore/scripts/reconstruction/star_bridge.py`: Monocular bridge.
  - `python addons/foveacore/scripts/reconstruction/star_simulator.py`: Logic simulator.

## External Dependencies
- **FFmpeg**: Required for frame extraction. Path set in Settings panel.
- **COLMAP**: Required for SfM path (Standard).
- **WorldMirror 2.0**: Recommended SOTA feed-forward reconstruction model.
- **DiffSynth-Studio**: Unified inference platform for DVLT and Vista4D.
- **Depth-Anything-3**: Model weights for precise monocular depth.

## Code Style & Architecture
- **GDScript**: Use Godot 4.6+ features (typed arrays, lambdas). Avoid chaining void methods.
- **C++/GDExtension**: Core performance logic (Splat sorting, Foveation).
- **StudioTo3D**: Modular pipeline (Extraction -> Geometry -> Training).
- **STAR Architecture**: Causal temporal cache + DA3 Depth Maps for 4D consistency.

## 👁️ FoveaCore Codage Rules & Constraints

### 📐 General Guidelines
- **Strictly Typed GDScript**: Always specify types for variables, function arguments, and return values (e.g. `var x: float = 1.0`, `func my_func(a: String) -> void`).
- **No Blocking Calls in `_ready()`**: Heavy operations like voxelization or collision shape generation MUST be executed via `call_deferred()` or in a background thread to prevent viewport freezes.
- **Null Safety on Vulkan Devices**: Always safely guard `culler_pipeline` and `culler_pipeline.rd` before querying GPU buffers (`buffer_get_data`) to prevent hard crashes in Compatibility or headless modes.
- **Strict Naming Convention**: Use PascalCase for class names and snake_case for local variables/methods. Comments and documentation should favor English for open-source clarity.

### 🚀 Performance & Memory
- **Batch Processing Rule**: Never loop `set_instance_transform()` or `set_instance_custom_data()` for loading or updating splats in MultiMesh. Use direct bulk writes via `transform_array` and `custom_data_array` (PackedFloat32Array) for a **10x to 50x** execution speedup.
- **Zero Allocations for Cleaning**: Run `FoveaSplatCleaner` operations (outliers pruning, floater culling with `SpatialHashGrid`, and decimation) directly on the raw GPU byte stream *before* decoding to maintain zero-copy efficiency.
- **Morton Cache Locality**: Arrange splat data sorted by 30-bit Morton codes before binary serialization to maximize VRAM texture cache hits.

### 🛡️ Survival Rules & Subsystem Architecture
- **Subsystem Decoupling**: Keep `FoveaCoreManager` as a clean, lightweight autoload orchestrator. All domain logic must reside in its decoupled subsystems:
  - `FoveaVRSubsystem` — Handles OpenXR initialization and VR rigs.
  - `FoveaFoveatedSubsystem` — Handles eye tracking and gaze caching.
  - `FoveaSplatSubsystem` — Handles sorting, frustum/occlusion culling, and renderer submissions.
- **Voxelizer Verification**: `FoveaVoxelizer` must strictly guard input files, verifying the `.fovea` extension and validating the 8-byte `FOVEA_3D` magic header before parsing to avoid corrupted collision geometries.
- **Clay Deformer Non-Destructiveness**: Modifications to splat positions via `FoveaClayDeformer` must always operate on a cached snapshot of original transforms to ensure edits are completely reversible.

## Git Workflow
- Keep commits focused on specific features/fixes.
- Use `rtk` for optimized token usage during commit/push operations.

## Botte Secrète policy
This project follows `.botte/policy.md` (prefer local models for cheap work, improve prompts locally, run `/checkup` after updates). Read it.

## Imported Claude Cowork project instructions
