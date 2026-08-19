<div align="center">
  <img src="../../../icon.svg" alt="FoveaEngine logo" width="80" />

  <h1>Transparency framebuffer harness</h1>
  <p>Deterministic alpha-composition oracle plus experimental splat-like scene layouts.</p>
  <p><a href="../../../README.md">Project overview</a> · <a href="../../../docs/feature-status.md">Feature status</a> · <a href="capture_render.gd">PLY capture harness</a></p>
</div>

> [!IMPORTANT]
> The framebuffer oracle is automated and fail-closed. The five 3D layouts remain visual fixtures: they are constructed deterministically, but their pixels are not yet compared with production splat output or golden images.

## Current result

| Capability | Current evidence |
| --- | --- |
| Five deterministic 3D layouts constructed | Yes |
| Clean Godot scene load | Yes on the recorded D3D12 run |
| Batched MultiMesh setup | Yes |
| Framebuffer capture | Yes |
| Numeric alpha-composition gate | Yes |
| Non-zero exit on oracle failure | Yes |
| Production splat-shader parity | No |
| Golden-image / PSNR / SSIM gate | No |
| Performance benchmark suitable for claims | No |

On 2026-08-15, Godot 4.7.dev5 Mono with Forward+, D3D12, and an NVIDIA RTX 5060 Ti produced these framebuffer samples over black:

| Sample | Measured red | Expected red | Tolerance |
| --- | ---: | ---: | ---: |
| One 50% red layer | 0.498 | 0.500 | ±0.080 |
| Two overlapping 50% red layers | 0.749 | 0.750 | ±0.080 |

The positive run exited `0` with zero `ERROR:`, script errors, parse errors, driver-initialization failures, or RID leak warnings. The forced negative control printed `TRANSPARENCY_ORACLE: FAIL` and exited `1`.

![Two 50% red layers composed over black](../../../docs/images/transparency-framebuffer-oracle.png)

<p align="center"><sub>Captured oracle output: the center is the two-layer sample; the black border is the background control.</sub></p>

## What changed

The historical harness allocated one `FoveaCoreSplatRenderer`—and therefore one local rendering device—for nearly every visual plane. The reproduced baseline emitted 627 `ERROR:` entries, including 208 driver-initialization failures, plus one script error.

The bounded harness now:

- uses ordinary `MultiMeshInstance3D` fixtures and one shared test shader;
- writes transforms and custom colors through batch arrays;
- seeds random placement with a fixed value;
- removes the unrelated VR rig and invalid `AmbientLight3D` scene node;
- labels the five layouts `constructed`, never unconditionally `passed`;
- samples one-layer, two-layer, and background framebuffer pixels;
- exits non-zero if capture, color, alpha, or forced-negative gates fail.

This isolates the transparency question without claiming that a test shader proves the production Gaussian-splat path.

## Files

| File | Purpose | Maturity |
| --- | --- | --- |
| [`transparency_blend_scene.tscn`](transparency_blend_scene.tscn) | Minimal D3D12 scene and harness host | Automated bounded harness |
| [`transparency_blend_test.gd`](transparency_blend_test.gd) | Builds five layouts and evaluates the framebuffer oracle | Oracle validated; layouts experimental |
| [`color_format_benchmark.gd`](color_format_benchmark.gd) | Experimental RGB565/palette timing and image metrics | Separate benchmark scaffold; no committed baseline |
| [`capture_render.gd`](capture_render.gd) | Deterministic PLY capture used by visual regression work | Validated capture path, not this oracle |

## Constructed layouts

The script still creates these arrangements for manual inspection:

1. five semi-transparent blue layers and a second overlapping group;
2. red-to-blue gradients, complementary colors, and an opacity ramp;
3. seven depth positions plus four overlapping colors;
4. continuous and stepped gradients intended to expose palette banding;
5. simulated RGB565 and nearest-palette colors for a small color set.

These layouts are inputs, not assertions. Only the isolated framebuffer oracle currently earns a `passed` result.

## Reproduce the positive gate

Run with a real rendering driver. The harness exits on its own:

```bash
godot --path . \
  --rendering-driver d3d12 \
  --resolution 1280x720 \
  --log-file transparency-positive.log \
  --scene res://addons/foveacore/test/transparency_blend_scene.tscn \
  -- --capture=/absolute/path/transparency-framebuffer-oracle.png
```

Expected markers:

```text
TRANSPARENCY_ORACLE: PASS | one=0.498 two=0.749
process exit code: 0
```

Inspect the complete log instead of trusting the summary alone:

```bash
rg -n "ERROR:|SCRIPT ERROR|Parse Error|Failed to initialize driver|RID allocations" transparency-positive.log
```

Headless or dummy renderers cannot validate blending. The harness now fails
immediately with exit code `1` in that environment instead of waiting forever
for a framebuffer signal or reporting a false success.

## Verify the fail-closed path

```bash
godot --path . \
  --rendering-driver d3d12 \
  --log-file transparency-negative.log \
  --scene res://addons/foveacore/test/transparency_blend_scene.tscn \
  -- --force-oracle-failure
```

Expected markers:

```text
TRANSPARENCY_ORACLE: FAIL
process exit code: 1
```

## Remaining promotion gates

Before documenting production splat transparency as validated, add:

1. captures of the same fixtures through the production packed-data shader path;
2. declared per-scenario alpha, depth-order, and color-distance assertions;
3. reference, RGB565, and palette images generated from identical inputs;
4. calibrated golden-image, PSNR/SSIM, and banding thresholds;
5. cross-driver and cross-GPU records with fixture provenance;
6. a representative performance benchmark kept separate from correctness.

The current result validates deterministic framebuffer composition and failure propagation only. It does not certify Gaussian rendering fidelity, depth sorting, palette quality, VR, or performance.
