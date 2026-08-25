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

## Decision

**Research result: keep. Production integration: not yet approved.**

The 4.23% storage reduction is measurable and substantially better than the
joint latent experiments. It is still insufficient evidence for replacing the
current `.fovea` covariance codebook because:

- the experiment uses one 8,000-splat fixture;
- color quality is inherited from the preserved baseline palette rather than
  recomputed by the neural decoder;
- the 3.8 ms CPU result is a Python/NumPy measurement, not a Godot, Rust, GPU,
  mobile, or XR runtime result;
- decoder memory, initialization, SIMD portability, and cross-asset quality
  have not been measured;
- the `.fvnc` artifact is experimental and is not part of the public
  `.fovea` v2 contract.

## Next research gates

1. Evaluate at least three representative assets and report worst-case quality.
2. Compare against the existing covariance codebook at equal byte budgets.
3. Implement a read-only Rust decoder benchmark before any runtime integration.
4. Measure end-to-end Godot load time, CPU memory, and frame impact.
5. Version the artifact formally only if it remains beneficial across assets.
