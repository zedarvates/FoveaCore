# Animated Splats

FoveaEngine provides several experimental animation tools. The most bounded
runtime path is the optional `.fovea4d` v1 motion sidecar: the base `.fovea`
asset stays immutable and independently loadable, while a small quantized grid
stores local position offsets over time.

`.fovea4d` is experimental. It is not a video-to-4D reconstruction format and
does not change splat color, opacity, covariance, topology, birth, or death.

## What is validated

- strict `FOVEA_4D` v1 parsing in GDScript and Rust;
- SHA-256 binding to one exact base `.fovea` file;
- deterministic writing and byte-identical cross-language fixtures;
- trilinear spatial and linear temporal sampling with unique loop keys;
- a D3D12 compute readback matching the CPU sampler within one quantization
  unit on an NVIDIA RTX 5060 Ti;
- dispatch before culling, animated bounds, and restoration of the static base;
- mutual exclusion with other position-changing modifiers;
- an 8,000-splat synthetic acceptance gate.

This evidence does not certify real captured motion, rendered-image quality,
million-splat performance, mobile GPUs, OpenXR, or headset playback.

## Runtime architecture

1. `Fovea4DLoader` validates the sidecar and its base-file digest.
2. `Fovea4DMotionField` owns immutable payload bytes and sampling metadata.
3. `Fovea4DPlayer` advances time and temporarily routes an instanced asset to a
   local renderer.
4. `fovea_4d_motion.glsl` writes positions into a transient animated buffer.
5. GPU culling, sorting, publishing, and rendering decode that buffer with its
   conservative animated AABB.
6. Stopping or removing the player releases the transient resources and
   restores the original static/instanced route.

The compute path changes the packed XYZ fields only. Normals, color/covariance
indices, opacity, layer, flags, and the base splat buffer are preserved.

## Quick tutorial

### 1. Prepare the base asset

Add a `FoveaSplat3D` node and assign a local `.fovea` file to `source_path`.
The sidecar must be generated against this exact file; changing even one byte
invalidates the SHA-256 binding.

### 2. Generate a sidecar offline

Build one `PackedVector3Array` per unique keyframe. Every array contains
`grid_dims.x * grid_dims.y * grid_dims.z` local-space offsets in X-fastest
order. Do not duplicate the first key at the end of a loop.

```gdscript
var grid_dims := Vector3i(8, 8, 8)
var keyframes: Array[PackedVector3Array] = build_motion_keys()
var base_bounds := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))

var error := Fovea4DWriter.write_sidecar(
    "res://assets/character_walk.fovea4d",
    "res://assets/character.fovea",
    grid_dims,
    keyframes,
    16.0,
    true,
    base_bounds
)
assert(error == OK)
```

Generate sidecars in an offline/editor workflow. Writing performs quantization,
file I/O, digest calculation, and a validation reload; it is not a per-frame
runtime operation.

### 3. Add playback

Enable the `FoveaLabs` plugin, add a `Fovea4DPlayer` beside the target, and set:

- `target_path` to the `FoveaSplat3D` node;
- `sidecar_path` to the matching `.fovea4d` file;
- `autoplay`, `playback_rate`, and `loop_override` as needed.

The equivalent scene script is:

```gdscript
@onready var player: Fovea4DPlayer = $Fovea4DPlayer

func _ready() -> void:
    player.target_path = NodePath("../FoveaSplat3D")
    player.sidecar_path = "res://assets/character_walk.fovea4d"
    player.autoplay = true

func pause_motion() -> void:
    player.pause()

func scrub_motion(seconds: float) -> void:
    player.seek(seconds)
```

Loading is deferred from `_ready()` so file validation does not block node
initialization. Connect `motion_loaded(sidecar_path)` and
`motion_error(message)` to expose status in tools or UI.

## Modifier exclusivity

One asset may have only one active position-changing path. Enabling 4D motion
fails with `ERR_ALREADY_IN_USE` when any of these are active:

- delta positions or a non-zero delta weight;
- a weighted procedural morph;
- a clay deformer;
- a child in the `fovea_position_modifiers` group;
- another dynamic ownership path.

Color-only or material-only animation remains conceptually compatible, but no
combined path should be treated as validated unless it has its own test.

## CPU reference path

`Fovea4DMotionField.sample()` is the scalar correctness reference. For repeated
CPU playback over fixed positions, call `build_cpu_sample_cache()` once and
then `sample_cpu_cache()` per frame. The cache stores spatially interpolated
values for every unique keyframe; it trades memory and setup time for a cheap
temporal interpolation loop. GPU playback does not use this cache.

The current 8,000-splat synthetic gate measured a 492 ms one-time cache build
and a 0.322 ms median cached sampling frame on the validation machine. These
numbers are test evidence, not cross-platform performance guarantees.

## Other experimental animation components

The repository also contains flow, morph, material, LOD-stretch, flipbook,
neural-offset, bone-skinning, cloth, and deformation prototypes. Their presence
does not imply that every shader is wired into the canonical renderer or that
they can be composed with `.fovea4d`. Check `docs/feature-status.md` and the
relevant focused tests before using them in release content.
