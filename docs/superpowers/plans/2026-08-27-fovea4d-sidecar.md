# Fovea4D Motion Sidecar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fail-closed `.fovea4d` v1 motion-field sidecar with deterministic CPU sampling, cross-language validation, and an experimental GPU playback path while preserving `.fovea` v2.

**Architecture:** The static `.fovea` remains immutable and independently loadable. A 128-byte `FOVEA_4D` sidecar binds to the base SHA-256 and stores keyframe-major int16 XYZ motion-grid samples; an experimental player uploads and samples that field before culling and sorting.

**Tech Stack:** Godot 4.7.dev5 typed GDScript, RenderingDevice/GLSL compute, Rust 1.97, SHA-256, little-endian binary fixtures.

**Spec:** `docs/superpowers/specs/2026-08-27-fovea4d-sidecar-design.md`

## Global Constraints

- Do not modify the `.fovea` v2 magic, 72-byte header, 16-byte splat record, loaders, or release packaging contract.
- `.fovea4d` v1 uses magic `FOVEA_4D`, version 1, little-endian fields, a 128-byte header, and codec 1 only.
- Payload records are keyframe-major, X-fastest spatial order, and exactly three signed int16 values per grid cell.
- Grid dimensions are each `2..32`; keyframes are `2..256`; sample rate is `0.1..240.0` Hz; payload is capped at 256 MiB.
- The sidecar is bound to the exact SHA-256 of its base `.fovea` and falls back to the static asset on every validation or runtime failure.
- Base positions remain immutable. `.fovea4d` motion is mutually exclusive with other position-changing modifiers on the same asset.
- V1 changes positions only. Color, opacity, covariance, topology, capture, networking, and runtime neural inference remain out of scope.
- Use strictly typed GDScript and English comments/docs. No blocking work in `_ready()`.
- Do not stage, overwrite, or commit the pre-existing `gsplat_bridge.py`, `test_gsplat_bridge.py`, or unrelated `docs/superpowers/plans/` files.

---

## File responsibility map

| File | Responsibility |
|---|---|
| `addons/foveacore/scripts/fovea_4d_format.gd` | Constants, exact header parsing, size arithmetic, structural validation |
| `addons/foveacore/scripts/fovea_4d_motion_field.gd` | Validated resource and CPU trilinear/temporal sampler |
| `addons/foveacore/scripts/fovea_4d_loader.gd` | File I/O, base SHA-256 binding, structured load result |
| `addons/foveacore/scripts/fovea_4d_writer.gd` | Offline quantization and deterministic sidecar writing |
| `addons/foveacore/scripts/advanced/fovea_4d_player.gd` | Experimental target binding, playback, seek, static fallback |
| `addons/foveacore/shaders/fovea_4d_motion.glsl` | GPU field sampling into transient animated splat buffer |
| `addons/foveacore/rust/src/fovea_4d_format.rs` | Independent Rust parser and structural validator |
| `addons/foveacore/rust/src/bin/generate_fovea4d_v1_fixture.rs` | Deterministic Rust-to-GDScript golden fixture |
| `addons/foveacore/test/test_fovea_4d_*.gd` | Structural, loader, sampler, player, and GPU acceptance tests |
| `test/fixtures/*.fovea4d` | Cross-language v1 golden fixtures |

### Task 1: GDScript format constants and structural validation

**Files:**
- Create: `addons/foveacore/scripts/fovea_4d_format.gd`
- Create: `addons/foveacore/test/test_fovea_4d_format.gd`

**Interfaces:**
- Consumes: raw `PackedByteArray` sidecar bytes.
- Produces: `Fovea4DFormat.expected_payload_size(grid_dims: Vector3i, keyframe_count: int) -> int` and `Fovea4DFormat.parse_bytes(bytes: PackedByteArray) -> Dictionary` returning `{ok, error, header, payload}`.

- [ ] **Step 1: Write the failing structural tests**

Create a test-local byte builder for a 2x2x2 grid and two keyframes. Assert:

```gdscript
assert(Fovea4DFormat.MAGIC == "FOVEA_4D")
assert(Fovea4DFormat.HEADER_SIZE == 128)
assert(Fovea4DFormat.expected_payload_size(Vector3i(2, 2, 2), 2) == 96)
var parsed: Dictionary = Fovea4DFormat.parse_bytes(valid_bytes)
assert(parsed["ok"])
assert(parsed["header"]["grid_dims"] == Vector3i(2, 2, 2))
assert((parsed["payload"] as PackedByteArray).size() == 96)
```

Duplicate the fixture and independently corrupt magic, version, header size, flags, codec, reserved bytes, grid bounds, keyframe count, sample rate, bounds, scales, payload offset, payload size, truncation, trailing bytes, and a 256 MiB overflow request. Each parse must return `ok == false` and a non-empty error.

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
$godot = Resolve-Path ".codex/tools/godot-4.7-dev5/Godot_v4.7-dev5_mono_win64_console.exe"
& $godot --headless --xr-mode off --path . -s res://addons/foveacore/test/test_fovea_4d_format.gd
```

Expected: script load failure because `fovea_4d_format.gd` does not exist.

- [ ] **Step 3: Implement the minimal parser**

Implement constants and checked size arithmetic before slicing payload bytes:

```gdscript
class_name Fovea4DFormat
extends RefCounted

const MAGIC: String = "FOVEA_4D"
const VERSION: int = 1
const HEADER_SIZE: int = 128
const CODEC_GRID_INT16: int = 1
const LOOP_FLAG: int = 1
const MAX_PAYLOAD_BYTES: int = 256 * 1024 * 1024

static func expected_payload_size(grid_dims: Vector3i, keyframe_count: int) -> int:
    if grid_dims.x < 2 or grid_dims.x > 32:
        return -1
    if grid_dims.y < 2 or grid_dims.y > 32 or grid_dims.z < 2 or grid_dims.z > 32:
        return -1
    if keyframe_count < 2 or keyframe_count > 256:
        return -1
    var size: int = keyframe_count * grid_dims.x * grid_dims.y * grid_dims.z * 6
    return size if size <= MAX_PAYLOAD_BYTES else -1
```

`parse_bytes()` must decode every table field at its specified offset, require exact file length, convert the 32 digest bytes to lowercase hex for `header.base_sha256`, and reject unknown flag bits.

- [ ] **Step 4: Run focused and compile-all tests**

Run the focused command from Step 2, then:

```powershell
& $godot --headless --xr-mode off --path . -s res://addons/foveacore/test/test_compile_all_scripts.gd
```

Expected: focused assertions pass; compile summary reports zero failed scripts.

- [ ] **Step 5: Commit Task 1**

```powershell
git add -- addons/foveacore/scripts/fovea_4d_format.gd addons/foveacore/test/test_fovea_4d_format.gd
git commit -m "feat(4d): validate motion sidecar structure"
```

### Task 2: Motion-field resource and CPU sampler

**Files:**
- Create: `addons/foveacore/scripts/fovea_4d_motion_field.gd`
- Create: `addons/foveacore/test/test_fovea_4d_motion_field.gd`

**Interfaces:**
- Consumes: the validated header and payload returned by `Fovea4DFormat.parse_bytes()`.
- Produces: `Fovea4DMotionField.configure(header: Dictionary, payload: PackedByteArray) -> String`, `validate() -> String`, `sample(local_position: Vector3, time_seconds: float) -> Vector3`, `animated_bounds(base_bounds: AABB) -> AABB`, and `to_gpu_bytes() -> PackedByteArray`.

- [ ] **Step 1: Write failing sampler tests**

Build a resource with a 2x2x2 grid and two unique loop keyframes. Encode known offsets and assert exact corner sampling, trilinear center sampling, temporal midpoint interpolation, last-to-first loop interpolation, negative time wrapping, non-loop clamping, and repeat-call immutability.

```gdscript
var field := Fovea4DMotionField.new()
var error: String = field.configure(header, payload)
assert(error.is_empty())
assert(field.sample(Vector3.ZERO, 0.0).is_equal_approx(Vector3(1, 0, 0)))
assert(field.sample(Vector3.ZERO, 0.25).is_equal_approx(Vector3(0.5, 0.5, 0)))
```

- [ ] **Step 2: Run the sampler test and verify RED**

Run the pinned Godot executable with `test_fovea_4d_motion_field.gd`.
Expected: load failure because `Fovea4DMotionField` is missing.

- [ ] **Step 3: Implement typed decode and interpolation**

Store immutable copies of header values and payload. Decode signed int16 values with the per-axis scale and use the spec index:

```gdscript
func _cell_index(x: int, y: int, z: int, keyframe: int) -> int:
    return keyframe * grid_dims.x * grid_dims.y * grid_dims.z + (z * grid_dims.y + y) * grid_dims.x + x

func _decode_cell(x: int, y: int, z: int, keyframe: int) -> Vector3:
    var byte_offset: int = _cell_index(x, y, z, keyframe) * 6
    return Vector3(
        float(payload.decode_s16(byte_offset)) * displacement_scale.x,
        float(payload.decode_s16(byte_offset + 2)) * displacement_scale.y,
        float(payload.decode_s16(byte_offset + 4)) * displacement_scale.z
    )
```

`sample()` must operate in base-asset local space, clamp spatial coordinates, linearly interpolate eight cells, then linearly interpolate two temporal samples using the unique-loop convention.
Scan decoded cells once during `configure()` to cache displacement minima and
maxima. `animated_bounds()` adds those component extrema to the base AABB.
`to_gpu_bytes()` repacks each three-int16 file record into two u32 words (8
bytes per cell) for std430-safe GPU upload without changing file storage.

- [ ] **Step 4: Run sampler and format tests**

Run both focused test scripts. Expected: all assertions pass with no parse errors.

- [ ] **Step 5: Commit Task 2**

```powershell
git add -- addons/foveacore/scripts/fovea_4d_motion_field.gd addons/foveacore/test/test_fovea_4d_motion_field.gd
git commit -m "feat(4d): sample quantized motion field"
```

### Task 3: Loader and base-asset binding

**Files:**
- Create: `addons/foveacore/scripts/fovea_4d_loader.gd`
- Create: `addons/foveacore/test/test_fovea_4d_loader.gd`

**Interfaces:**
- Consumes: `Fovea4DFormat.parse_bytes()` and an existing local `.fovea` path.
- Produces: `Fovea4DLoader.load_sidecar(sidecar_path: String, base_fovea_path: String) -> Dictionary` returning `{ok, error, field}`.

- [ ] **Step 1: Write failing binding and I/O tests**

Write a valid test sidecar whose header contains `FileAccess.get_sha256(base_path)`. Assert valid load, missing files, non-project paths, malformed sidecar, and a different valid base asset. The mismatched base must return `ok == false` while the test base remains readable.

```gdscript
var result: Dictionary = Fovea4DLoader.load_sidecar(SIDECAR_PATH, BASE_PATH)
assert(result["ok"])
assert(result["field"] is Fovea4DMotionField)
var mismatch: Dictionary = Fovea4DLoader.load_sidecar(SIDECAR_PATH, OTHER_BASE_PATH)
assert(not mismatch["ok"])
assert(str(mismatch["error"]).contains("SHA-256"))
```

- [ ] **Step 2: Run the loader test and verify RED**

Run `test_fovea_4d_loader.gd`. Expected: load failure because the loader is missing.

- [ ] **Step 3: Implement fail-closed loading**

Implement project/cache confinement and structured errors:

```gdscript
static func load_sidecar(sidecar_path: String, base_fovea_path: String) -> Dictionary:
    if not sidecar_path.begins_with("res://") and not sidecar_path.begins_with("user://"):
        return _failure("sidecar path must be project-local or cache-local")
    if base_fovea_path.get_extension().to_lower() != "fovea":
        return _failure("base asset must use .fovea")
    var parsed: Dictionary = Fovea4DFormat.parse_bytes(FileAccess.get_file_as_bytes(sidecar_path))
    if not bool(parsed.get("ok", false)):
        return _failure(str(parsed.get("error", "invalid sidecar")))
    if str(parsed["header"]["base_sha256"]) != FileAccess.get_sha256(base_fovea_path).to_lower():
        return _failure("base .fovea SHA-256 mismatch")
```

Configure a new `Fovea4DMotionField`; return no partial resource when validation fails.

- [ ] **Step 4: Run loader, sampler, and format tests**

Expected: all focused scripts exit 0; mismatched base test fails closed.

- [ ] **Step 5: Commit Task 3**

```powershell
git add -- addons/foveacore/scripts/fovea_4d_loader.gd addons/foveacore/test/test_fovea_4d_loader.gd
git commit -m "feat(4d): bind motion sidecar to base asset"
```

### Task 4: Deterministic writer and GDScript golden fixture

**Files:**
- Create: `addons/foveacore/scripts/fovea_4d_writer.gd`
- Create: `addons/foveacore/test/test_fovea_4d_writer.gd`
- Create: `addons/foveacore/test/generate_fovea_4d_fixture.gd`
- Create: `test/fixtures/gdscript_fovea4d_v1_fixture.fovea4d`

**Interfaces:**
- Consumes: a base `.fovea`, grid dimensions, ordered unique keyframes, sample rate, loop flag, and local bounds.
- Produces: `Fovea4DWriter.write_sidecar(path: String, base_path: String, grid_dims: Vector3i, keyframes: Array[PackedVector3Array], sample_rate_hz: float, loop: bool, bounds: AABB) -> Error`.

- [ ] **Step 1: Write failing writer tests**

Use two 2x2x2 keyframes. Assert deterministic bytes, exact 128-byte header,
exact 96-byte payload, base digest binding, round-trip sampling, and rejection
of empty keys, inconsistent cell counts, non-local output, invalid bounds, and
non-finite vectors. Assert that an all-zero axis is accepted and decodes to
exact zeros.

The all-zero axis is encoded with scale `1.0` and zero codes so the positive-scale format invariant remains valid.

- [ ] **Step 2: Run writer tests and verify RED**

Run `test_fovea_4d_writer.gd`. Expected: missing writer failure.

- [ ] **Step 3: Implement deterministic quantization and writing**

Compute one positive scale per axis across all keyframes, quantize to signed int16, write the exact header, write payload bytes, close, reload with `Fovea4DLoader`, and remove the output if round-trip validation fails.

```gdscript
var maximum := Vector3.ZERO
for frame: PackedVector3Array in keyframes:
    for offset: Vector3 in frame:
        maximum = maximum.max(offset.abs())
var scale := Vector3(
    maximum.x / 32767.0 if maximum.x > 0.0 else 1.0,
    maximum.y / 32767.0 if maximum.y > 0.0 else 1.0,
    maximum.z / 32767.0 if maximum.z > 0.0 else 1.0
)
```

Use `FileAccess.store_16()` with two's-complement values masked to `0xffff`. Never write trailing bytes.

- [ ] **Step 4: Generate and verify the GDScript fixture**

Run:

```powershell
& $godot --headless --xr-mode off --path . -s res://addons/foveacore/test/generate_fovea_4d_fixture.gd
& $godot --headless --xr-mode off --path . -s res://addons/foveacore/test/test_fovea_4d_writer.gd
```

Expected: fixture is reproduced byte-for-byte and reloads against `test/fixtures/rust_v2_fixture.fovea`.

- [ ] **Step 5: Commit Task 4**

```powershell
git add -- addons/foveacore/scripts/fovea_4d_writer.gd addons/foveacore/test/test_fovea_4d_writer.gd addons/foveacore/test/generate_fovea_4d_fixture.gd test/fixtures/gdscript_fovea4d_v1_fixture.fovea4d
git commit -m "feat(4d): write deterministic motion sidecars"
```

### Task 5: Independent Rust parser and cross-language fixtures

**Files:**
- Create: `addons/foveacore/rust/src/fovea_4d_format.rs`
- Create: `addons/foveacore/rust/src/bin/generate_fovea4d_v1_fixture.rs`
- Modify: `addons/foveacore/rust/src/lib.rs`
- Create: `test/fixtures/rust_fovea4d_v1_fixture.fovea4d`
- Modify: `addons/foveacore/test/test_fovea_4d_format.gd`

**Interfaces:**
- Consumes: `.fovea4d` bytes and the 32-byte expected base digest.
- Produces: `parse_fovea4d(bytes: &[u8]) -> Result<(Fovea4dHeader, &[u8]), Fovea4dError>` and the deterministic Rust fixture.

- [ ] **Step 1: Write failing Rust structural tests**

Define tests for the complete valid header plus corrupt magic, version, flags, codec, dimensions, key count, non-finite sample rate/scales/bounds, payload overflow, wrong offset/size, truncation, trailing data, and non-zero reserved bytes. Include the GDScript fixture at compile time:

```rust
#[test]
fn gdscript_fixture_is_accepted() {
    let bytes = include_bytes!("../../../../test/fixtures/gdscript_fovea4d_v1_fixture.fovea4d");
    let (header, payload) = parse_fovea4d(bytes).expect("GDScript fixture validates");
    assert_eq!(header.grid_dims, [2, 2, 2]);
    assert_eq!(payload.len(), 96);
}
```

- [ ] **Step 2: Run Rust tests and verify RED**

```powershell
cargo test --manifest-path addons/foveacore/rust/Cargo.toml --all-targets
```

Expected: unresolved `fovea_4d_format` module.

- [ ] **Step 3: Implement the Rust parser**

Use explicit little-endian slices and checked multiplication. Do not add dependencies.

```rust
pub const FOVEA4D_MAGIC: &[u8; 8] = b"FOVEA_4D";
pub const FOVEA4D_VERSION: u32 = 1;
pub const FOVEA4D_HEADER_SIZE: usize = 128;

pub struct Fovea4dHeader {
    pub flags: u32,
    pub base_sha256: [u8; 32],
    pub grid_dims: [u16; 3],
    pub keyframe_count: u16,
    pub sample_rate_hz: f32,
    pub bounds_min: [f32; 3],
    pub bounds_max: [f32; 3],
    pub displacement_scale: [f32; 3],
}
```

- [ ] **Step 4: Generate Rust fixture and verify in Godot**

```powershell
cargo run --manifest-path addons/foveacore/rust/Cargo.toml --bin generate_fovea4d_v1_fixture -- test/fixtures/rust_fovea4d_v1_fixture.fovea4d
& $godot --headless --xr-mode off --path . -s res://addons/foveacore/test/test_fovea_4d_format.gd
cargo clippy --manifest-path addons/foveacore/rust/Cargo.toml --all-targets -- -D warnings -A clippy::result_large_err
```

Expected: GDScript accepts the Rust fixture; Rust accepts the GDScript fixture; Clippy is clean.

- [ ] **Step 5: Commit Task 5**

```powershell
git add -- addons/foveacore/rust/src/fovea_4d_format.rs addons/foveacore/rust/src/bin/generate_fovea4d_v1_fixture.rs addons/foveacore/rust/src/lib.rs addons/foveacore/test/test_fovea_4d_format.gd test/fixtures/rust_fovea4d_v1_fixture.fovea4d
git commit -m "test(4d): validate sidecar across Rust and Godot"
```

### Task 6: Experimental player and modifier exclusivity

**Files:**
- Create: `addons/foveacore/scripts/advanced/fovea_4d_player.gd`
- Modify: `addons/foveacore/scripts/fovea_splattable.gd`
- Modify: `addons/foveacore/scripts/advanced/fovea_core_splat_renderer.gd`
- Modify: `addons/fovea_labs/plugin.gd`
- Create: `addons/foveacore/test/test_fovea_4d_player.gd`

**Interfaces:**
- Consumes: `Fovea4DLoader.load_sidecar()`, one `FoveaSplat3D`, and its internal `FoveaSplattable` delegate.
- Produces: `FoveaSplattable.configure_4d_motion(field: Fovea4DMotionField) -> Error`, `update_4d_motion_time(time_seconds: float) -> void`, `clear_4d_motion() -> void`, plus an experimental `Fovea4DPlayer` node.

- [ ] **Step 1: Write failing player and exclusivity tests**

Create a `FoveaSplat3D` with a native `.fovea` base and a child player. Assert deferred load, autoplay time advance, pause, seek, playback-rate scaling, target cleanup, and static fallback. Assert `ERR_ALREADY_IN_USE` when delta positions, morph weight, an active renderer deformer, or a child in group `fovea_position_modifiers` is present.

```gdscript
var delegate: FoveaSplattable = splat.get_advanced()
assert(delegate.configure_4d_motion(field) == OK)
delegate.update_4d_motion_time(0.5)
assert(is_equal_approx(delegate.motion_4d_time_seconds, 0.5))
delegate.clear_4d_motion()
assert(delegate.motion_4d_field == null)
```

- [ ] **Step 2: Run player test and verify RED**

Run `test_fovea_4d_player.gd`. Expected: missing player and delegate methods.

- [ ] **Step 3: Add delegate state and fail-closed acquisition**

Add typed transient fields to `FoveaSplattable` and reject incompatible state before changing `is_static`:

```gdscript
var motion_4d_field: Fovea4DMotionField = null
var motion_4d_time_seconds: float = 0.0

func configure_4d_motion(field: Fovea4DMotionField) -> Error:
    if field == null or not field.validate().is_empty():
        return ERR_INVALID_DATA
    if not is_static or not delta_positions.is_empty() or delta_weight > 0.0:
        return ERR_ALREADY_IN_USE
    if morph_type != "None" and morph_weight > 0.0:
        return ERR_ALREADY_IN_USE
    var renderer: Node = get_node_or_null("FoveaCoreSplatRenderer")
    if renderer != null and renderer.get("deformer") != null:
        return ERR_ALREADY_IN_USE
    for node: Node in find_children("*", "", true, false):
        if node.is_in_group("fovea_position_modifiers"):
            return ERR_ALREADY_IN_USE
    motion_4d_field = field
    is_static = false
    return OK
```

`clear_4d_motion()` clears field/time and restores the pre-4D static flag. Forward configuration and time to `FoveaCoreSplatRenderer`; that renderer stores pending state until Task 7 creates GPU resources.

- [ ] **Step 4: Implement the player and labs registration**

`Fovea4DPlayer._ready()` calls `call_deferred("_load_motion")`; `_process(delta)` advances local time only when playing and forwards it to the target delegate. Add this explicit experimental alias:

```gdscript
["Fovea4DPlayer", "Node", "res://addons/foveacore/scripts/advanced/fovea_4d_player.gd", ""]
```

The player exposes `target_path`, `sidecar_path`, `autoplay`, `loop_override`, and `playback_rate`. Loading errors emit `motion_error(message)` and leave the target static.

- [ ] **Step 5: Run focused and non-GPU tests, then commit**

Run the player, loader, sampler, and format tests, followed by `run_all_tests.gd -- --group=nogpu`.

```powershell
git add -- addons/foveacore/scripts/advanced/fovea_4d_player.gd addons/foveacore/scripts/fovea_splattable.gd addons/foveacore/scripts/advanced/fovea_core_splat_renderer.gd addons/fovea_labs/plugin.gd addons/foveacore/test/test_fovea_4d_player.gd
git commit -m "feat(4d): add experimental motion player"
```

### Task 7: GPU motion-field dispatch before culling

**Files:**
- Create: `addons/foveacore/shaders/fovea_4d_motion.glsl`
- Modify: `addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd`
- Modify: `addons/foveacore/scripts/advanced/fovea_core_splat_renderer.gd`
- Create: `addons/foveacore/test/test_fovea_4d_gpu_contract.gd`

**Interfaces:**
- Consumes: `Fovea4DMotionField.to_gpu_bytes()`, base packed splat buffer, base AABB, derived animated AABB, splat count, and player time.
- Produces: `GPUCullerPipeline.configure_4d_motion(field: Fovea4DMotionField, base_bounds: AABB) -> Error`, `set_4d_motion_time(time_seconds: float) -> void`, and `clear_4d_motion() -> void`.

- [ ] **Step 1: Write failing shader/layout contract tests**

The non-GPU contract test asserts shader existence, local size 256, bindings 0..3, X-fastest/keyframe-major indexing, base and animated AABBs, temporal linear interpolation, and dispatch before culling. Add a GPU-marked test that uses a 2x2x2 field to move one packed splat outside the base AABB and asserts readback matches CPU sampling within one animated-AABB quantization unit.

- [ ] **Step 2: Run tests and verify RED**

Run the non-GPU contract. Expected: missing shader/configuration API. On a RenderingDevice machine, the GPU test must also fail before implementation.

- [ ] **Step 3: Implement the compute shader**

Use a std430-safe `uvec2` motion record because the file's 6-byte record is repacked to 8 bytes for upload:

```glsl
#[compute]
#version 450
layout(local_size_x = 256) in;
layout(set = 0, binding = 0, std430) readonly buffer BaseSplats { uvec4 base_splats[]; };
layout(set = 0, binding = 1, std430) writeonly buffer AnimatedSplats { uvec4 animated_splats[]; };
layout(set = 0, binding = 2, std430) readonly buffer MotionField { uvec2 motion_cells[]; };
layout(set = 0, binding = 3, std430) readonly buffer MotionParams { uvec4 counts; vec4 base_min; vec4 base_max; vec4 animated_min; vec4 animated_max; vec4 scale_time; };
```

Decode the base u16 position with `base_min/base_max`, sample eight cells at two keyframes, add displacement, then quantize with `animated_min/animated_max`. Copy all non-position packed fields unchanged.

- [ ] **Step 4: Integrate persistent GPU resources and dispatch ordering**

Create/free shader, pipeline, field buffer, params buffer, and uniform set symmetrically. `configure_4d_motion()` validates `rd`, uploads once, caches base/animated bounds, and returns an error without partial RIDs on failure.

In the asset dispatch path, select exactly one position animation source. When 4D is active, dispatch base input to `cache["animated"]`, point culling at that buffer, and set downstream AABB uniforms to the animated bounds. When cleared, restore base input and bounds. Never run delta and 4D passes together.

- [ ] **Step 5: Verify GPU and fallback behavior, then commit**

Run the non-GPU contract, focused GPU readback on D3D12, compile-all, and non-GPU suite. Force an invalid/missing motion buffer and verify the static base still renders.

```powershell
git add -- addons/foveacore/shaders/fovea_4d_motion.glsl addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd addons/foveacore/scripts/advanced/fovea_core_splat_renderer.gd addons/foveacore/test/test_fovea_4d_gpu_contract.gd
git commit -m "feat(4d): dispatch motion field before culling"
```

### Task 8: Synthetic acceptance gate and release-facing documentation

**Files:**
- Create: `addons/foveacore/test/test_fovea_4d_quality_gate.gd`
- Modify: `addons/foveacore/docs/ANIMATED_SPLATS.md`
- Modify: `docs/feature-status.md`
- Modify: `experiments/neural_splat_compression/REPORT.md`

**Interfaces:**
- Consumes: completed GDScript/Rust format, writer/loader, CPU sampler, player, and GPU path.
- Produces: reproducible acceptance evidence and an explicitly experimental status.

- [ ] **Step 1: Write the synthetic acceptance test**

Generate the approved 8x8x8, 16-unique-keyframe loop over the 8,000-splat fixture. Write and reload the sidecar, sample every proxy frame, and assert:

```gdscript
assert(combined_bytes <= 214 * 1024)
assert(normalized_position_rmse <= 0.001)
assert(normalized_loop_closure_rmse <= 0.000001)
assert(cpu_median_ms < 16.67)
```

Record the unique-keyframe result separately from the earlier duplicated-closure spike.

- [ ] **Step 2: Run all local gates**

```powershell
& $godot --headless --xr-mode off --path . -s res://addons/foveacore/test/test_fovea_4d_quality_gate.gd
& $godot --headless --xr-mode off --path . -s res://addons/foveacore/test/test_compile_all_scripts.gd
& $godot --headless --xr-mode off --path . -s res://addons/foveacore/test/run_all_tests.gd -- --group=nogpu
cargo test --manifest-path addons/foveacore/rust/Cargo.toml --all-targets
cargo clippy --manifest-path addons/foveacore/rust/Cargo.toml --all-targets -- -D warnings -A clippy::result_large_err
python tools/check_public_docs.py
python tools/botte_entrypoint.py checkup
```

Expected: zero failed focused/non-GPU/Rust suites, zero GDScript compile failures, public docs pass, checkup reports no drift.

- [ ] **Step 3: Update evidence without overclaiming**

Document `.fovea4d` as `EXPERIMENTAL` only. State that the accepted evidence is synthetic CPU plus focused GPU agreement. Keep `FoveaStudio4DCapture` unavailable and explicitly list real-sequence, visual, million-splat, mobile, and XR gates as open.

- [ ] **Step 4: Verify final diff scope**

```powershell
git status --short
git diff --check
git diff --name-only
git diff --cached --name-only
```

The diff must not include `gsplat_bridge.py`, `test_gsplat_bridge.py`, unrelated plans, generated `.godot` state, logs, or local reconstruction assets.

- [ ] **Step 5: Commit Task 8**

```powershell
git add -- addons/foveacore/test/test_fovea_4d_quality_gate.gd addons/foveacore/docs/ANIMATED_SPLATS.md docs/feature-status.md experiments/neural_splat_compression/REPORT.md
git commit -m "docs(4d): record motion sidecar acceptance boundary"
```
