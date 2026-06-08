# 📘 FoveaEngine Developer API Reference

This document provides a public API reference for the main scripts, singletons, and subsystems of FoveaEngine.

---

## 1. Singletons & Core Managers

### `FoveaCoreManager` (Autoload Facade)
The central entry point and orchestrator for all engine subsystems.
- **Properties**:
  - `vr_enabled: bool` — Indicates if OpenXR was initialized successfully.
  - `foveation_level: int` — Current foveation quality index.
- **Methods**:
  - `initialize(config: FoveaConfig) -> bool` — Sets up subsystems and registers rendering device pipelines.
  - `update_gaze(left: Vector2, right: Vector2) -> void` — Feeds eye-tracking coordinates from the OpenXR API.
  - `apply_foveation_settings() -> void` — Updates VRS shading textures dynamically.

### `ReconstructionManager` (Autoload / Local Orchestrator)
Orchestrates the asynchronous video-to-3D pipeline in three phases (Extraction, Reconstruction, Baking).
- **Signals**:
  - `phase_started(phase: int)` — Emitted when a pipeline phase starts.
  - `phase_progress_updated(phase: int, progress: float, status_text: String)` — Emitted during processing.
  - `reconstruction_completed(session_name: String, ply_path: String)` — Emitted when reconstruction finishes successfully.
  - `reconstruction_failed(session_name: String, error_message: String)` — Emitted when an error is caught.
- **Methods**:
  - `run_reconstruction(session: ReconstructionSession) -> void` — Starts the async backend processes.
  - `cancel_reconstruction() -> void` — Forcefully kills running python/COLMAP subprocesses.

---

## 2. Decoupled Subsystems

### `FoveaVRSubsystem`
Handles the OpenXR compositor interface and HMD lifecycle.
- **Methods**:
  - `is_xr_session_active() -> bool` — Validates if HMD is rendering.
  - `get_hmd_transform() -> Transform3D` — Returns the current tracking space transformation matrix of the headset.

### `FoveaFoveatedSubsystem`
Manages gaze-point filtering and foveated LOD calculations.
- **Methods**:
  - `calculate_gaze_lod(point: Vector3) -> float` — Returns the LOD ratio $[0.0, 1.0]$ based on angular distance to current gaze vector.

### `FoveaSplatSubsystem`
Submits and binds splat assets to the rendering pipelines.
- **Methods**:
  - `allocate_splat_buffer(size: int) -> RID` — Allocates GPU buffer space.
  - `submit_render_dispatch(renderer: FoveaCoreSplatRenderer) -> void` — Schedules sorting and culling tasks.

---

## 3. High-Performance Renderers

### `FoveaCoreSplatRenderer` (formerly `FoveaSplatRenderer`)
Main class for rendering individual `.fovea` or `.ply` assets using GPU compute.
- **Properties**:
  - `splat_file_path: String` — File path to the `.fovea` or `.ply` asset.
  - `use_triangle_mesh: bool` — If `true`, renders splats using subdivided circular meshes instead of quads (eliminates overdraw).
  - `splat_subdivisions: int` — Geometry subdivision count (default `16`).
- **Methods**:
  - `load_asset(path: String) -> void` — Triggers fast-path binary loading.

### `FoveaSplatDispatcher`
Regroups multiple splat assets into a single GPU compute dispatch to reduce draw calls.
- **Methods**:
  - `register_asset(node: FoveaSplattable) -> int` — Registers an asset and returns its allocated `layer_id` tag.

### `FoveaInstancedSplatRenderer` & `FoveaInstancedCuller`
Renders thousands of copies of a `.fovea` asset (e.g. forests, crowds) using a single VRAM geometry copy.
- **Methods**:
  - `add_instance(transform: Transform3D, custom_data: Color) -> void` — Adds a new instance to the GPU buffer.
  - `cull_instances_gpu(camera: Camera3D) -> void` — Triggers GPU-driven frustum culling.

---

## 4. Pipeline Backends

### `StudioProcessor`
Handles video frame extraction and background masking.
- **Methods**:
  - `extract_frames(video_path: String, output_dir: String, fps: int) -> int` — Synchronously calls FFmpeg.
  - `calculate_blur_score(image: Image) -> float` — Returns the Laplacian variance score to filter blurry frames.

### `ReconstructionBackend`
Executes external tools (COLMAP, WorldMirror, DVLT) asynchronously.
- **Methods**:
  - `execute_command_async(command: String, args: PackedStringArray) -> int` — Spawns an OS subprocess with output pipe tracking.

---

## 5. Optimization Utilities

### `FoveaSplatCleaner`
Prunes and merges splat clouds on the CPU or GPU.
- **Methods**:
  - `prune_nans_and_floaters(splats: Array[GaussianSplat]) -> Array[GaussianSplat]` — Removes invalid coordinates.
  - `merge_coplanar(splats: Array[GaussianSplat], z_bucket: float, min_group: int) -> Array[GaussianSplat]` — Fuses coplanar splats to reduce fill-rate overhead.

### `FoveaThreadPool`
Distributes surface extraction and parsing tasks across all available CPU cores.
- **Methods**:
  - `submit_task(callable: Callable, userdata: Variant) -> void` — Adds a task to the background worker queue.
