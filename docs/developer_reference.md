# FoveaEngine Developer Reference

> Status: source-derived reference, updated 2026-08-15. Stable-node, facade, and reconstruction API tokens below are checked against the active GDScript signatures by `test_developer_reference_contract.gd`. GPU, XR, native, and reconstruction paths remain subject to the validation status in [Feature status](feature-status.md).

## API ownership at a glance

| Usage | Godot identity | Active implementation |
| --- | --- | --- |
| Stable scene node | Class `FoveaSplat3D` | [`fovea_splat_3d.gd`](../addons/foveacore/scripts/fovea_splat_3d.gd) |
| Core singleton | Autoload `FoveaCoreManager`, class `FoveaCoreManagerScript` | [`foveacore_manager.gd`](../addons/foveacore/scripts/foveacore_manager.gd) |
| Reconstruction singleton | Autoload `ReconstructionManager`, class `FoveaReconstructionManager` | [`reconstruction_manager.gd`](../addons/foveacore/scripts/reconstruction/reconstruction_manager.gd) |

Use the autoload names from scene scripts. The backing `class_name` values identify the implementation types and intentionally differ for both manager singletons.

## Stable scene entry point: `FoveaSplat3D`

`FoveaSplat3D` is the public node for rendering a Gaussian-splat asset in a Godot scene.

```gdscript
var splat: FoveaSplat3D = FoveaSplat3D.new()
splat.source_path = "res://assets/garden.fovea"
add_child(splat)
```

### Signal

- `asset_loaded(path: String)` — emitted after the source has been loaded into the delegate renderer.

### Exported properties

| Property | Type | Meaning |
| --- | --- | --- |
| `source_path` | `String` | `.fovea`, `.ply`, or `.splat` source path. Planned `.spz` decoding is not exposed. |
| `enabled` | `bool` | Master rendering switch for the asset. |
| `quality_preset` | `QualityPreset` | `AUTO`, `PERFORMANCE`, `BALANCED`, or `CINEMATIC`. Returning to `AUTO` restores neutral local density/priority so global manager settings remain authoritative. |
| `generate_collisions` | `bool` | Requests collision generation for compatible assets. |
| `opacity` | `float` | Per-asset opacity multiplier. |
| `is_static` | `bool` | Static/streaming hint passed to the delegate. |

### Methods

- `get_advanced() -> FoveaSplattable` — returns the internal delegate for advanced, non-stable controls.
- `export_to_fovea(dest_path: String) -> bool` — exports the current splat data through the delegate.

## Autoload facade: `FoveaCoreManager`

`FoveaCoreManager` is the registered autoload name. Its backing script declares `class_name FoveaCoreManagerScript` and owns subsystem wiring. It does not expose an `initialize(config)` API.

### Runtime controls

- `register_splattable(node: FoveaSplattable) -> void`
- `refresh_splattable_asset(node: FoveaSplattable) -> void`
- `unregister_splattable(node: FoveaSplattable) -> void`
- `set_style(style: FoveaStyle) -> void`
- `set_splat_density(density: float) -> void`
- `toggle_foveated(enabled: bool) -> void`
- `toggle_animation(enabled: bool) -> void`
- `get_animation_subsystem() -> FoveaAnimationSubsystem`
- `toggle_hybrid_mode() -> void`

### Relevant exported settings

The manager exports VR, splat-density, foveated, style, and animation settings. Important values include `vr_enabled`, `target_fps`, `foveated_enabled`, `global_splat_density`, `max_splats_per_frame`, `foveal_radius`, and `animation_enabled`.

`target_fps` is a target, not a measured performance guarantee.

## Internal subsystems

These classes are implementation interfaces; normal game code should prefer `FoveaSplat3D` and the manager facade.

### `FoveaVRSubsystem`

- Signal: `xr_initialized`
- Signal: `xr_unavailable(reason: String)`
- Method: `setup(enabled: bool, shader: bool) -> void`
- State: `is_xr_active: bool`

The subsystem enables OpenXR when available and otherwise reports the fallback condition.

### `FoveaFoveatedSubsystem`

- `setup(r: float, foveal: float, parafoveal: float, peripheral: float) -> void`
- `update(enabled: bool) -> void`
- `get_controller() -> FoveatedController`
- `get_layered_controller() -> LayeredFoveatedController`
- `get_gaze_point() -> Vector3`
- `mark_dirty() -> void`
- `disable() -> void`

### `FoveaSplatSubsystem`

- `setup(density: float, max_s: int = 100000) -> void`
- `process_frame(visibility_result, camera: Camera3D, camera_pos: Vector3) -> int`
- `apply_foveated_pass(foveated_controller: FoveatedController, layered_controller: LayeredFoveatedController = null, enable_layered: bool = false) -> void`

It transforms or generates splats, applies animation, sorts them with GPU-aware fallback, and submits them to the renderer.

### `FoveaCoreSplatRenderer`

The renderer is an advanced implementation class. Its main callable surface includes:

- `setup_palette(palette: FoveaColorPalette) -> void`
- `load_palette_from_fovea() -> void`
- `update_material_shader() -> void`
- `load_and_render_splats(camera_moved: bool = true) -> void`
- `update_splat_mesh_mode(use_triangle: bool) -> void`
- `render_splats(splats: Array[GaussianSplat]) -> int`
- `pack_gaussian_splats(splats: Array[GaussianSplat], aabb_min: Vector3, aabb_max: Vector3) -> PackedByteArray`

## Fovea asset resource

`FoveaAsset` is the resource representation for the current `.fovea` v2 container.

| Field | Type |
| --- | --- |
| `splat_count` | `int` |
| `color_codebook_size` | `int` |
| `covar_codebook_size` | `int` |
| `aabb_min`, `aabb_max` | `Vector3` |
| `color_palette` | `FoveaColorPalette` |
| `covariance_codebook` | `PackedByteArray` |
| `splats_raw_bytes` | `PackedByteArray` |
| `style` | `FoveaStyle` |
| `mesh` | `ArrayMesh` |
| `metadata` | `Dictionary` |

- `get_aabb() -> AABB`

The binary contract is `FOVEA_3D` version 2, a 72-byte little-endian header, and 16-byte splat records. See [the canonical format specification](../plans/fovea_format_spec.md).

## Reconstruction API

Reconstruction is experimental and relies on optional local external tools. `ReconstructionManager` is the autoload used by scene scripts; its implementation class is `FoveaReconstructionManager`.

This dry-run example creates a session without claiming that the optional tools are installed:

```gdscript
var session: ReconstructionSession = ReconstructionManager.create_new_session(
	"res://capture.mp4",
	"garden"
)
session.dry_run = true
session.training_iterations = 30000
ReconstructionManager.run_reconstruction(session)
```

### Autoload `ReconstructionManager` / class `FoveaReconstructionManager` signals

- `session_started(name: String)`
- `session_progress_updated(progress: float)`
- `session_completed(result: ReconstructionSession)`
- `reconstruction_failed(reason: String)`
- `log_line_received(line: String)`
- `pipeline_state_changed(is_active: bool)`

### Autoload `ReconstructionManager` / class `FoveaReconstructionManager` methods

- `check_tools() -> Dictionary`
- `create_new_session(video_path: String, name: String = "") -> ReconstructionSession`
- `save_session(session: ReconstructionSession) -> Error`
- `load_session(path: String) -> ReconstructionSession`
- `delete_session(session: ReconstructionSession, delete_disk_files: bool = false) -> void`
- `run_extraction(session: ReconstructionSession, mask_mode: String = "Studio White") -> void`
- `run_reconstruction(session: ReconstructionSession) -> void`
- `run_sfm(session: ReconstructionSession) -> void`
- `run_star_sync(session: ReconstructionSession) -> void`
- `run_triposplat(session: ReconstructionSession) -> void`
- `run_worldmirror(session: ReconstructionSession) -> void`
- `run_training(session: ReconstructionSession) -> void`
- `run_artifixer(session: ReconstructionSession) -> void`

### `ReconstructionSession`

The session resource persists capture input, processing settings, pipeline state, and output paths. Relevant fields include:

| Field | Type | Purpose |
| --- | --- | --- |
| `session_name` | `String` | Human-readable session name. |
| `video_path` | `String` | Source capture path. |
| `output_directory` | `String` | Session workspace for extracted and generated files. |
| `extraction_fps` | `int` | Frame sampling rate for extraction. |
| `training_iterations` | `int` | Gaussian-training iteration budget; current new-session default is 30,000. |
| `dry_run` | `bool` | Exercises command construction without running optional external tools. |
| `visual_style` | `String` | Selected reconstruction style. |
| `splat_shape` | `String` | Selected output splat shape. |
| `state` | `SessionState` | Current session lifecycle state. |

- `to_dict() -> Dictionary`
- `from_dict(dict: Dictionary) -> void`
- `get_training_point_cloud_path() -> String`

Older saved sessions without `training_iterations` retain their historical 7,000-iteration value during migration; newly created sessions use 30,000.

### `ReconstructionBackend` signals and methods

Signals:

- `command_started(command: String)`
- `command_progress(current_line: String, percent: float)`
- `command_finished(status: int, output: String)`
- `error_occurred(message: String)`
- `oom_detected(command: String, details: String)`

Methods:

- `execute_reconstruction(session: ReconstructionSession) -> void`
- `build_gaussian_training_args(session: ReconstructionSession) -> Array`
- `execute_artifixer(session: ReconstructionSession) -> void`

### `StudioProcessor`

Signals:

- `frame_extracted(index: int, image: Image)`
- `processing_completed(frame_count: int)`
- `error_occurred(reason: String)`

Methods:

- `extract_frames(session: ReconstructionSession) -> void`
- `get_preview_frame(video_path: String) -> Image`
- `mask_background(image: Image, mode: String, threshold: float, roi: Rect2i) -> Image`
- `generate_normal_map_from_depth(depth_image: Image) -> Image`
- `mask_by_normal(normal_image: Image, top_facing_threshold: float = 0.7) -> Image`
- `calculate_blur_score(image: Image) -> float`
- `calculate_brightness_and_variance(image: Image) -> Dictionary`
- `detect_surface_features(image: Image) -> Dictionary`

## Compatibility notes

- Do not call GPU-specific renderer methods without a valid RenderingDevice path.
- OpenXR and eye tracking require a target-runtime smoke test.
- A bridge script or API method is not proof that the corresponding model, weights, or external executable is installed.
- Treat `FoveaSplattable` and advanced renderer APIs as volatile unless a task explicitly establishes a stable contract.
