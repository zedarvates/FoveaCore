# FoveaEngine Technical Specification

**Status:** living baseline 0.1
**Compiled:** 2026-07-16
**Scope:** the active FoveaEngine repository and the canonical `addons/foveacore` product path

## 1. Context

FoveaEngine is a Godot 4.7 project for Gaussian Splatting rendering, VR interaction, and video-to-3D reconstruction. `addons/foveacore` is the canonical addon; Rust and C++ native extension sources, a parallel C# project, experimental Godot plugins, test suites, and reconstruction bridges also exist in the repository.

The current release-facing status remains pre-release. GPU, XR, reconstruction, and native paths require validation on representative target hardware.

## 2. Goals

- Provide a minimal Godot-facing API for loading `.fovea`, `.ply`, and `.splat` assets, while rejecting planned formats such as `.spz` until their decoders exist.
- Keep VR, foveated rendering, splat processing, and animation logic in decoupled subsystems coordinated by a lightweight manager.
- Support desktop fallback when OpenXR is unavailable.
- Provide testable reconstruction orchestration for FFmpeg, COLMAP, and explicitly experimental external bridges.
- Maintain a binary `.fovea` container with guarded parsing and GPU-oriented data layout.
- Make performance and readiness claims only from reproducible evidence.

## 3. Non-goals

- Claiming cross-platform production certification from source inspection alone.
- Treating optional research bridges as bundled inference backends.
- Treating the parallel C# addon as the shipped renderer.
- Defining autonomous code-changing agents before their schemas, permissions, metrics, and rollback behavior are implemented.

## 4. Constraints

| Area | Contract |
| --- | --- |
| Godot | Use Godot 4.7-compatible APIs and strictly typed GDScript for new or modified code. |
| Startup | Heavy voxelization, collision generation, parsing, or training work must not block `_ready()`. |
| Renderer safety | Guard RenderingDevice objects and buffers in headless and compatibility modes. |
| Splat updates | Prefer bulk buffer or MultiMesh array writes over per-instance setter loops. |
| VR | `target_fps` defaults to 90, but sustained headset performance is **EXPERIMENTAL** until measured. |
| Memory | Validate counts, offsets, sizes, and multiplication bounds before allocating or reading asset buffers. |
| Editing | Deformation must preserve an original transform snapshot for complete reversal. |
| Build | Keep GDScript, Python, C#, Rust, and C++ validation surfaces coherent with CI. |
| Compatibility | Format changes require a versioned migration path and cross-reader round-trip tests. |

## 5. Public API and interfaces

### `FoveaSplat3D`

**State:** VALIDATED for headless lifecycle, delegation, and control propagation; representative rendering remains EXPERIMENTAL

The stable Godot node is defined in `addons/foveacore/scripts/fovea_splat_3d.gd`.

- Signal: `asset_loaded(path: String)`
- Inputs: `source_path`, `enabled`, `quality_preset`, `generate_collisions`, `opacity`, `is_static`
- Methods: `get_advanced() -> FoveaSplattable`, `export_to_fovea(dest_path: String) -> bool`
- Delegation: advanced behavior is owned by an internal `FoveaSplattable` node.

The focused public-node contract passes 26/26 assertions, including a real
one-splat PLY load, runtime-only delegate ownership, signal behavior, live
property propagation, and preset transitions. GPU, XR, collision geometry,
export fidelity, image quality, and performance remain separate gates.

### `FoveaCoreManager`

**State:** VALIDATED for headless facade orchestration and dynamic lifecycle; GPU and XR execution remain EXPERIMENTAL

The autoload facade in `addons/foveacore/scripts/foveacore_manager.gd` owns lifecycle and dependency wiring.

- `register_splattable(node: FoveaSplattable) -> void`
- `unregister_splattable(node: FoveaSplattable) -> void`
- `set_style(style: FoveaStyle) -> void`
- `set_splat_density(density: float) -> void`
- `toggle_foveated(enabled: bool) -> void`
- `toggle_animation(enabled: bool) -> void`
- `get_animation_subsystem() -> FoveaAnimationSubsystem`
- `toggle_hybrid_mode() -> void`

The facade contract passes 30/30 assertions and its dynamic `.fovea` lifecycle
passes 4/4. This covers ownership, injection, control routing, parameter
clamping, desktop fallback, renderer creation, path retention, and cleanup.

### Subsystems

**State:** VALIDATED for headless ownership, injection, control routing, and desktop fallback; compute, XR, and performance remain EXPERIMENTAL

- `FoveaVRSubsystem.setup(enabled: bool, shader: bool)` initializes OpenXR and emits `xr_initialized` or `xr_unavailable`.
- `FoveaFoveatedSubsystem.setup(...)` owns gaze and foveated-zone state.
- `FoveaSplatSubsystem.process_frame(...)` generates, transforms, animates, sorts, and submits current splats.
- `FoveaAnimationSubsystem` applies non-destructive animation modifiers before sorting and submission.

The validation above proves facade wiring and CPU-safe fallback behavior. It
does not certify RenderingDevice execution, eye tracking, headset composition,
representative visual fidelity, or sustained frame time.

### Reconstruction

**State:** EXPERIMENTAL

`ReconstructionManager` coordinates sessions and exposes session lifecycle signals. `ReconstructionBackend` selects external tool paths and supports a `dry_run` mode. External bridge presence is not evidence that model weights or inference environments are installed.

## 6. Internal flow

1. Godot loads the enabled plugins and three FoveaCore autoloads.
2. `FoveaSplat3D` creates/configures its internal `FoveaSplattable` delegate.
3. `FoveaCoreManager` registers visible splat nodes and owns subsystem dependencies.
4. Visibility extraction produces per-node results.
5. `FoveaSplatSubsystem` obtains loaded or generated splats, applies transforms and animation, performs GPU-aware sorting with CPU fallback, and submits to the renderer.
6. The foveated pass adjusts density/opacity using gaze data.
7. OpenXR activation uses the primary interface when available and otherwise falls back to desktop mode.

The detailed component diagram is in [architecture.md](architecture.md).

## 7. Formats

### `.fovea` v2 — current implemented layout

**State:** VALIDATED for the v2 structural and cross-language contract; native runtime performance remains EXPERIMENTAL

The active GDScript and Rust implementations use this 72-byte header:

| Field | Type |
| --- | --- |
| magic | 8 bytes, UTF-8/ASCII `FOVEA_3D` |
| version | `uint32`, current value `2` |
| splat_count | `uint32` |
| color_codebook_size | `uint32` |
| covariance_codebook_size | `uint32` |
| aabb_min / aabb_max | six `float32` values |
| style offset/size | two `uint32` values |
| mesh offset/size | two `uint32` values |
| metadata offset/size | two `uint32` values |

The current GDScript stream order is header → RGB32F palette → 32-byte covariance entries → 16-byte splat records → optional style JSON → optional mesh → optional metadata JSON. The 16-byte splat record contains quantized position, projected normal, palette index, covariance index, opacity, layer, dither seed, and brush type.

The tile rasterizer compute path consumes that same 16-byte PackedSplat stride. Dummy GPU buffers in rasterizer_performance_benchmark.gd must be sized as splat_count * 16; a 20-byte modeled density stride is not a valid rasterizer contract.

The locked Rust workspace passes 5/5 tests, a local Windows release build, and
Clippy with warnings denied. Its generator reproduces the tracked 208-byte
fixture byte-for-byte, and Godot 4.7.dev5 accepts that fixture in the 28/28
structural suite. These checks validate format compatibility and buildability,
not native throughput, GPU acceleration, XR behavior, or cross-platform release
artifacts.

`plans/gaussian_compression_spec.md` now describes a **PROPOSED** v3 candidate with a distinct identity. It is not a v2 reader/writer contract.

### Logs and agent interchange

**State:** PROPOSED

Runtime reconstruction progress currently uses Godot signals and process output. A stable JSON schema for audit, fix, and performance agent runs is proposed in [agents/README.md](agents/README.md) and is not yet a runtime API.

## 8. Tests and acceptance

The validation matrix is maintained in [tests/README.md](tests/README.md).

Minimum acceptance for documentation-only changes:

- Markdown links resolve within `docs/autowiki/`.
- no runtime file changes;
- the local validation utilities still pass;
- the repository checkup is recorded, including pre-existing directive drift.

Minimum acceptance for runtime changes:

- GDScript parse and compile check;
- non-GPU tests pass headless;
- affected Rust, C++, C#, or Python checks pass;
- GPU, visual, XR, and performance checks are run on representative hardware or marked hardware-blocked;
- affected Wiki claims are updated with current evidence states.

## 9. Risks and mitigations

| Priority | Risk | Mitigation |
| --- | --- | --- |
| P1 | Cross-language reader coverage and packed-record semantics are tested; instanced culling uses a 24-byte runtime record with a separate `instance_id`. The unit suite statically checks both shader contracts and its GPU readback checks two visible instances as the unordered identifier set `{0,1}`; it is **skipped** (not passed) when no local `RenderingDevice` exists. | Run that readback and publication-parity path on the CI/project Godot baseline with a Vulkan-capable device. |
| P1 | Public API reference contains signatures absent from current code. | Generate or verify the reference from parsed script signatures. |
| P1 | GPU/XR readiness is overclaimed by historical plans and audits. | Keep release state in `docs/feature-status.md` and require target-hardware results. |
| P2 | Rust and C++ native implementations can drift after their artifact identities were separated. | Keep the 14-assertion ownership contract in the non-GPU suite and require explicit packaging changes. |
| P2 | Large experimental surface increases false confidence from script-count tests. | Classify tests by capability and require behavior assertions plus fixtures. |

## 10. Migration and compatibility

- Preserve `FOVEA_3D` version 2 readers until fixtures prove a replacement path.
- Reject unsupported magic, version, count, size, or offset combinations before buffer access.
- Introduce any incompatible compact format as a new version with explicit reader selection.
- Keep `FoveaSplat3D` as the stable public node; advanced API changes belong behind its delegate.

## 11. Future extensions

- Cross-language `.fovea` conformance suite with golden fixtures.
- Typed JSON schemas for audit and research runs.
- Self-hosted GPU/XR validation with frame-time, memory, and image-quality baselines.
- Generated API reference from Godot script metadata.
- Measurable compression research comparing size, decode time, PSNR, SSIM, and VRAM.
