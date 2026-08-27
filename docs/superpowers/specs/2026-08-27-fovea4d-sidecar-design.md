# FoveaEngine 4D Motion Sidecar Design

**Date:** 2026-08-27  
**Status:** Proposed design approved for specification; implementation not started.

## 1. Purpose

FoveaEngine needs a bounded animated-splat format that avoids storing one full
`.fovea` asset per frame. The static `.fovea` v2 contract must remain unchanged.
Animation is therefore stored in an optional `.fovea4d` sidecar that references
one exact static base asset and contains a quantized spatiotemporal displacement
field.

The first version targets smooth deformation with fixed splat identity and
topology. It does not attempt general 4D reconstruction, dynamic splat birth or
death, neural runtime inference, or automatic video-to-4D authoring.

## 2. Evidence and selected approach

A deterministic 8,000-splat feasibility spike compared a 120-frame full
flipbook, per-splat delta keyframes, and quantized motion fields.

| Encoding | Combined size | Reduction vs flipbook | Normalized position RMSE | CPU median |
|---|---:|---:|---:|---:|
| Full `.fovea` flipbook | 19,669,440 bytes | baseline | 0 | not measured |
| Per-splat deltas, 12 keys | 739,928 bytes | 96.24% | 0.0240% | 0.035 ms |
| Motion field 8x8x8, 16 keys | 213,096 bytes | 98.92% | 0.0912% | 4.76 ms |
| Motion field 16x16x16, 12 keys | 458,856 bytes | 97.67% | 0.0402% | 4.01 ms |

A 4x4x4 field failed the quality threshold. Six temporal keyframes also failed.
The selected v1 baseline is an 8x8x8 field with 16 unique loop keyframes. A
16x16x16 field remains a high-quality authoring option.

The spike included one duplicated closure sample. V1 removes that duplicate;
the synthetic quality gate must therefore be rerun with the unique-keyframe
loop convention before the format is promoted to experimental.

## 3. Compatibility boundary

- `.fovea` remains `FOVEA_3D`, version 2, with its current 72-byte header and
  16-byte splat records.
- `.fovea4d` is optional. A runtime that does not recognize it still loads the
  base `.fovea` as a static asset.
- A sidecar binds to the exact SHA-256 digest of its base `.fovea` bytes.
- A missing, corrupt, unsupported, or mismatched sidecar must fail closed to the
  static base asset. It must never prevent the valid base asset from loading.
- `.fovea4d` is not added as an optional section inside `.fovea` v2.

## 4. File identity and byte order

- Extension: `.fovea4d`
- Magic: eight ASCII bytes `FOVEA_4D`
- Format version: `1`
- Byte order: little-endian
- Header size: 128 bytes
- Codec v1: quantized dense motion grid (`codec = 1`)

## 5. Header layout

| Offset | Size | Type | Field |
|---:|---:|---|---|
| 0 | 8 | ASCII | magic `FOVEA_4D` |
| 8 | 4 | u32 | version, exactly 1 |
| 12 | 4 | u32 | header size, exactly 128 |
| 16 | 4 | u32 | flags |
| 20 | 4 | u32 | codec, exactly 1 for v1 |
| 24 | 32 | bytes | SHA-256 of the base `.fovea` |
| 56 | 2 | u16 | grid size X |
| 58 | 2 | u16 | grid size Y |
| 60 | 2 | u16 | grid size Z |
| 62 | 2 | u16 | unique keyframe count |
| 64 | 4 | f32 | keyframe sample rate in Hz |
| 68 | 12 | 3xf32 | base-asset local-space bounds minimum |
| 80 | 12 | 3xf32 | base-asset local-space bounds maximum |
| 92 | 12 | 3xf32 | displacement scale for signed X/Y/Z codes |
| 104 | 8 | u64 | payload offset, exactly 128 in v1 |
| 112 | 8 | u64 | payload size in bytes |
| 120 | 8 | bytes | reserved, all zero in v1 |

Flag bit 0 means looped playback. All other flag bits are zero in v1 and are
rejected if set.

## 6. Payload layout

Each grid cell stores three signed little-endian int16 values. A decoded
displacement is:

```text
offset_xyz = int16_xyz * displacement_scale_xyz
```

Records are keyframe-major with X as the fastest spatial axis:

```text
index = keyframe * (nx * ny * nz) + (z * ny + y) * nx + x
```

The exact v1 payload size is:

```text
keyframe_count * nx * ny * nz * 3 * 2 bytes
```

No padding, compression wrapper, optional section, or trailing data is allowed
in v1.

## 7. Time and loop semantics

Looped files store unique samples only; the first keyframe is not duplicated at
the end. Runtime time is mapped as:

```text
frame_coordinate = positive_mod(time_seconds * sample_rate_hz, keyframe_count)
k0 = floor(frame_coordinate)
k1 = (k0 + 1) % keyframe_count
temporal_weight = fract(frame_coordinate)
```

Non-looped playback clamps `frame_coordinate` to `[0, keyframe_count - 1]` and
uses the final keyframe as both endpoints after playback completes.

Temporal interpolation is linear. Nearest-frame temporal sampling is not
conformant for `.fovea4d` v1.

## 8. Spatial sampling

The base splat local position is normalized inside the sidecar bounds and
clamped to the grid. The runtime samples eight neighboring cells with trilinear
interpolation, samples both temporal keyframes, then linearly interpolates
between those spatial results.

The decoded displacement is additive and non-destructive:

```text
animated_position = immutable_base_position + sampled_displacement
```

The base splat buffer remains unchanged so disabling or rejecting animation is
fully reversible. The node or instance transform is applied after the local
displacement and is not encoded in the sidecar.

## 9. Runtime architecture

### Loader

`Fovea4DFormat` owns constants, header parsing, size arithmetic, and validation.
`Fovea4DLoader` reads the sidecar only after the base `.fovea` is available and
verifies the base SHA-256 before accepting the payload.

### Resource

`Fovea4DMotionField` owns validated metadata and packed int16 payload bytes. It
does not own the base splat asset and performs no file or network access after
loading.

### Player

An experimental `Fovea4DPlayer` references one `FoveaSplat3D` plus one motion
field. It controls time, playback rate, looping, pause, and seek without adding
4D properties to the stable `FoveaSplat3D` public surface.

### GPU path

The packed field is uploaded once to a storage buffer. A compute pass samples
the field and writes animated positions into the transient animated-splat buffer
before culling and depth sorting. The immutable base buffer is never rewritten.

### CPU reference path

A typed CPU sampler implements identical indexing and interpolation for tests,
headless verification, and small compatibility fixtures. It is not a
performance claim for production scenes.

## 10. Validation and fail-closed limits

A loader rejects the sidecar before allocating the payload when any condition
fails:

- magic, version, header size, codec, flags, or reserved bytes are invalid;
- the base SHA-256 does not match the loaded `.fovea`;
- any grid dimension is outside `2..32`;
- keyframe count is outside `2..256`;
- sample rate is non-finite or outside `0.1..240.0` Hz;
- bounds or displacement scales contain non-finite values;
- bounds are inverted or any displacement scale is not positive;
- payload offset is not 128;
- payload multiplication overflows or exceeds 256 MiB;
- recorded payload size differs from the exact computed size;
- file size differs from `payload_offset + payload_size`.

A rejected sidecar produces one structured error and leaves the static base
asset active. Validation must not partially upload GPU resources.

## 11. Authoring boundary

V1 defines a runtime and interchange contract only. An offline authoring tool
accepts a static base asset plus displacement samples already aligned to that
base topology. It quantizes the samples, writes the sidecar, reloads it, and
verifies reconstruction error before publishing.

`FoveaStudio4DCapture` remains unavailable. Per-frame reconstruction, temporal
correspondence, topology alignment, cleaning, and capture rights are separate
research problems and must not be presented as implemented by this format.

## 12. Testing strategy

### Structural tests

- deterministic 2x2x2, two-keyframe golden fixture;
- exact header and payload byte counts;
- GDScript writer to Rust reader and Rust writer to GDScript reader;
- corrupt magic, version, flags, codec, hash, bounds, scales, counts, offsets,
  truncation, oversized payload, trailing bytes, and reserved bytes;
- mismatched valid base asset rejection.

### Sampling tests

- exact cell samples and trilinear midpoint samples;
- linear temporal midpoint samples;
- loop interpolation from the last keyframe to the first;
- negative time and seek behavior;
- immutable base positions after repeated playback;
- CPU/GPU output agreement on a deterministic fixture.

### Performance and quality gates

For the approved 8,000-splat synthetic deformation proxy:

- combined base plus sidecar size at or below 214 KiB;
- normalized position RMSE at or below 0.1% of the base AABB diagonal;
- normalized loop-closure RMSE at or below `1e-6`;
- CPU reference median below 16.67 ms per frame;
- zero parse errors and zero failed non-GPU suites.

GPU timing, million-splat performance, mobile, XR, and visual parity remain
separate hardware gates. The existing aspirational sub-millisecond animation
budgets are not treated as validated acceptance criteria.

## 13. Security and distribution

When the sidecar is distributed through the MMO asset registry, a future
versioned registry entry must treat the base `.fovea` and `.fovea4d` as
separate content-addressed objects and record their binding. Clients verify
both file hashes before parsing either payload.

Paths remain project-local or cache-local; the format does not contain remote
URLs, credentials, executable code, scripts, or model weights.

## 14. Non-goals

V1 does not include:

- splat birth, death, remeshing, or topology changes;
- animated color, opacity, covariance, or spherical harmonics;
- skeletal rigs, cloth state, collision animation, or network replication;
- runtime neural inference;
- automatic 4D capture or reconstruction;
- changes to `.fovea` v2 or its public loaders;
- release-readiness claims for GPU, XR, or target hardware.

## 15. Promotion criteria

The sidecar may move from proposed to experimental only after the golden
cross-language fixture, negative structural suite, CPU sampler, and synthetic
quality gate pass. Runtime promotion requires a representative real 4D sequence,
GPU/CPU agreement, visual capture, and target-hardware measurements.
