# Tutorial: Train, bake, and inspect a Gaussian-splat asset

This tutorial covers the current FoveaEngine training contract, native `.fovea` export, and the experimental editor brush. It replaces the older Graphdeco `train.py` instructions. Those commands are no longer what StudioTo3D launches.

## 1. Train with the official gsplat bridge

Use this path after FFmpeg and COLMAP have produced a dataset with images plus a sparse model. The bridge verifies a CUDA-enabled gsplat runtime, runs the official trainer, copies the final PLY to the StudioTo3D location, and writes a hash-addressed manifest.

```bash
python addons/foveacore/scripts/reconstruction/gsplat_bridge.py -s <dataset_dir> -m <dataset_dir>/output --iterations 7000
```

Rules that the bridge enforces:

- `-m` must be `<dataset_dir>/output`
- the output directory must be empty
- photorealistic training requires at least 1,000 iterations
- existing PLY or manifest files are never overwritten

If gsplat is installed in another interpreter, set `FOVEA_GSPLAT_PYTHON` to that executable before running the same command.

A successful run publishes:

```text
<dataset_dir>/output/point_cloud/iteration_7000/point_cloud.ply
<dataset_dir>/output/fovea_gsplat_training_manifest.json
```

`--dry-run` validates the dataset and runtime without launching CUDA training.

## 2. Load the trained PLY in Godot

Open [`demo/drop_a_ply.tscn`](../demo/drop_a_ply.tscn) or add a `FoveaSplat3D` node and set `source_path` to the published PLY. Confirm the visual result on your GPU before converting formats or claiming quality.

## 3. Bake a native `.fovea` file

Native `.fovea` export is available for structural and experimental runtime testing. It is not a frame-rate guarantee and does not by itself prove image parity.

### Editor

1. Select a `FoveaSplat3D` node.
2. Set `source_path` to the loaded `.ply` and wait for `asset_loaded`.
3. In **Fovea Actions**, click **Convert to .fovea**.
4. The editor writes a `.fovea` file next to the source, using the same base name.

The writer stores a color palette of up to 256 entries, a covariance codebook of up to 1024 entries, Morton ordering, and quantized positions inside the asset bounds. Coplanar merging is a separate experimental runtime option.

### GDScript

```gdscript
var splat := FoveaSplat3D.new()
add_child(splat)
splat.source_path = "res://reconstructions/input.ply"
await splat.asset_loaded

if not splat.export_to_fovea("res://reconstructions/output.fovea"):
	push_error("Fovea export failed")
```

`generate_collisions` only applies after a `.fovea` source is loaded.

## 4. Experimental editing

[`addons/foveacore/scenes/splat_brush_playground.tscn`](../addons/foveacore/scenes/splat_brush_playground.tscn) is the editor sandbox. OpenXR is experimental; the desktop camera fallback is the supported inspection path in this tutorial.

Brush modes:

- `ERASE` - remove floaters inside the brush sphere
- `DENSITY` - clone splats into sparse regions
- `COLOR` - modulate RGB
- `FLOW` - paint direction vectors consumed by the experimental water-particle shader

Keep a copy of the source asset. Verify the result visually, then export a new `.fovea` file only if the target renderer supports that path. Brush and clay-deformer output is not a production editing certificate.

## Next steps

- Follow [Reconstruction setup](reconstruction_setup.md) if FFmpeg or COLMAP is still missing.
- Read [Feature status](../docs/feature-status.md) before treating GPU sorting, XR, or research bridges as available.
