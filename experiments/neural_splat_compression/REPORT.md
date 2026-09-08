# Neural Splat Compression Autoresearch Report

**Date:** 2026-08-25  
**Branch:** `autoresearch/neural-splats-20260825`  
**Fixture:** `test/fixtures/reference_3dgs.ply` (8,000 splats)

## Goal and metric

The experiment asks whether a small quantized neural residual can reduce the
stored size of scale, rotation, and color attributes without exceeding the
quality limits established by the static `.fovea` baseline.

- Metric: total estimated bytes, lower is better.
- Failed quality gates receive a sentinel metric of `1_000_000_000`.
- Baseline: 163,912 bytes.
- Quality limits:
  - mean rotation error <= 10.376565 degrees;
  - scale RMSE <= 0.0294673;
  - color RMSE <= 0.0378712.

Reproduction command:

```powershell
python experiments/neural_splat_compression/neural_residual_experiment.py `
  --config experiments/neural_splat_compression/configs/06_covariance_only_latent6.json `
  --fixture test/fixtures/reference_3dgs.ply `
  --artifact-out covariance_only_latent6.fvnc
```

## Results

| Experiment | Commit | Result | Bytes | Key outcome |
|---:|---|---|---:|---|
| 0 | `9211096` | baseline | 163,912 | Static `.fovea` reference |
| 1 | `ba5de7c` | discard | - | Latent2 failed all learned attributes |
| 2 | `9a1fb08` | discard | - | Latent4 failed rotation and color |
| 3 | `f6bedb2` | discard | - | Latent6 joint model failed rotation and color |
| 4 | `92190ff` | discard | - | Latent8 failed rotation at 19.08 degrees |
| 5 | `5ee24b6` | discard | - | Rotation weighting regressed color |
| 6 | `7e16cad` | keep | 163,134 | Joint latent8 passed all gates; 0.47% saving |
| 7 | `50c4379` | discard | - | Latent7 narrowly failed scale |
| 8 | `6b8681b` | discard | - | Scale weighting regressed rotation |
| 9 | `327d706` | discard | - | Gentle scale weighting did not improve scale |
| 10 | `1d2b060` | discard | - | Wider latent7 decoder still failed scale |
| 11 | `51c3ce4` | keep | 156,972 | Preserve palette; learn covariance only |
| 12 | `3963ef9` | keep | 156,972 | Serialized artifact and measured CPU decode |
| 13 | `82c40f3` | discard | - | Multi-asset storage regressed on 2 of 3 assets |

## Best result

The covariance-only latent6 experiment separates color from the neural
residual. It preserves the existing palette representation and learns only
scale plus rotation.

| Measurement | Reproduced value |
|---|---:|
| Total bytes | 156,972 |
| Reduction from baseline | 6,940 bytes (4.23%) |
| Neural artifact | 49,828 bytes |
| Fixed position/opacity data | 96,072 bytes |
| Preserved color data | 11,072 bytes |
| Mean rotation error | 1.302 degrees |
| Scale RMSE | 0.000893 |
| CPU decode median | 3.776 ms |
| CPU decode p95 | 4.514 ms |
| Repeated decodes | 100 |

The binary artifact is decoded without a live PyTorch model. Unit tests cover
round-trip decoding, corrupt magic rejection, dimensions, storage accounting,
feature selection, and repeated decode measurement.

## Multi-asset validation

The same covariance-only configuration was trained and measured on three
redistributable 3DGS assets. Static sizes come from the canonical Godot
`.fovea` writer; neural sizes include fixed data, preserved color data, and
the serialized decoder artifact.

| Asset | Splats | Static bytes | Neural bytes | Size change | Rotation | Scale RMSE | Decode median |
|---|---:|---:|---:|---:|---:|---:|---:|
| Reference fixture | 8,000 | 163,912 | 156,972 | -4.23% | 1.302 deg | 0.000893 | 3.776 ms |
| Bonsai | 12,473 | 235,480 | 241,959 | +2.75% | 2.059 deg | 0.000096 | 11.632 ms |
| Horse statue | 25,674 | 446,696 | 492,778 | +10.32% | 1.582 deg | 0.000100 | 18.084 ms |

All three assets pass the learned rotation and scale gates. The storage metric
fails on bonsai and horse because the neural latent grows per splat while the
static covariance codebook remains bounded.

## Decision

**Single-fixture result: keep as evidence. Compression scheme: reject for
production.**

The 4.23% reference reduction is real, but it does not generalize. The
multi-asset worst case is a 10.32% storage regression, so the current design
must not replace the existing `.fovea` covariance codebook. Additional limits:

- the experiment uses one 8,000-splat fixture;
- color quality is inherited from the preserved baseline palette rather than
  recomputed by the neural decoder;
- the 3.8 ms CPU result is a Python/NumPy measurement, not a Godot, Rust, GPU,
  mobile, or XR runtime result;
- decoder memory, initialization, SIMD portability, and cross-asset quality
  have not been measured;
- the `.fvnc` artifact is experimental and is not part of the public
  `.fovea` v2 contract.

## Rigid-motion reference gate

The reference fixture was decoded once, then transformed through a closed
600-frame rigid-motion loop. Each frame carries one object transform
(translation, quaternion, and uniform scale) rather than per-splat latent
updates.

| Measurement | Result |
|---|---:|
| Splats | 8,000 |
| Frames | 600 |
| Initial latent decodes | 1 |
| Per-frame transform payload | 32 bytes |
| Per-frame latent payload | 0 bytes |
| Total motion payload | 19,200 bytes |
| CPU reference transform median | 0.620 ms/frame |
| CPU reference transform p95 | 0.963 ms/frame |
| Loop position RMSE | 0.0 |
| Loop rotation closure | 0.0081 degrees |
| Loop scale RMSE | 0.0 |

The bounded motion gate passed, but this is a vectorized NumPy reference. It
does not prove Godot frame cost, GPU shader transforms, rendering quality,
sorting under motion, XR behavior, or deforming/independent splats. It also
does not reverse the multi-asset storage rejection above.

## Fovea4D motion-sidecar acceptance

The approved position-only sidecar was rerun in Godot with 16 unique loop
keyframes; unlike the earlier feasibility spike, the first keyframe was not
duplicated at the end. The deterministic test uses the committed 8,000-splat
`.fovea` fixture, an 8x8x8 int16 motion grid, and 120 proxy frames.

| Measurement | Result |
|---|---:|
| Base plus `.fovea4d` bytes | 213,288 |
| Normalized position RMSE | 0.011233% |
| Normalized loop-closure RMSE | 0.0 |
| One-time CPU spatial-cache build | 492.128 ms |
| Cached CPU sampling median | 0.322 ms/frame |
| D3D12 shader/readback assertions | 13/13 passed |

The first scalar implementation measured 212.242 ms/frame because it decoded
and interpolated every grid cell for every splat. Caching decoded cells reduced
that to 90.688 ms/frame but still failed the 16.67 ms gate. The accepted CPU
reference precomputes spatial interpolation for every unique key and performs
only temporal interpolation per frame. Cache construction is reported
separately and is not included in the frame median.

The D3D12 check ran on an NVIDIA RTX 5060 Ti. It verified CPU/GPU position
agreement within one animated-AABB quantization unit and preserved packed
normal, color/covariance, opacity, and flag fields. This remains synthetic
evidence. It does not prove a real captured sequence, rendered-image quality,
million-splat throughput, mobile portability, or OpenXR/headset behavior.

## Next research gates

1. Explore an adaptive per-asset decision that retains the static codebook when
   neural storage is not smaller.
2. Compare against the existing covariance codebook at equal byte budgets.
3. Implement a read-only Rust decoder benchmark only after storage improves on
   every representative asset.
4. Measure end-to-end Godot load time, CPU memory, and rigid-transform frame
   impact without changing the public `.fovea` contract.
5. Test bounded deformation only after a representative cross-asset storage
   strategy passes.
6. Version the artifact formally only if it becomes beneficial across assets.
