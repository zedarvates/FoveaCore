# Tutorial: Load your first Gaussian splat

This is the shortest validated path from a fresh clone to a visible splat in Godot. It uses the committed demo scene and a repository asset. It does not require FFmpeg, COLMAP, CUDA, or a headset.

## Before you begin

- Install **Godot 4.7.dev5 Mono** or a compatible later 4.7 Mono build.
- Clone this repository with submodules:

```bash
git clone --recurse-submodules https://github.com/zedarvates/FoveaCore.git
cd FoveaCore
```

- Use a Forward+ capable GPU for the visual result. Compatibility and headless modes can load the node, but they are not the desktop rendering proof.

## 1. Open the working demo

1. Open `project.godot` in Godot.
2. Let the editor finish importing resources.
3. Open [`demo/drop_a_ply.tscn`](../demo/drop_a_ply.tscn).
4. Choose **Play Current Scene**.

The scene always labels the asset it actually loaded:

| On-screen label | What you are looking at |
| --- | --- |
| `REAL CAMERA VIDEO 3DGS` | Local 17,013-splat reconstruction from a real camera video. This file is validation-only and is not redistributed. |
| `SYNTHETIC VIDEO 3DGS` | Checked-in CC0 reconstruction at `res://reconstructions/horse_statue_cc0_v1/fovea_runtime/horse_statue_6999_runtime_v1.ply`. Public clones normally land here. |
| `COMPATIBILITY FIXTURE` | Small parser fixture used only when both reconstructions are missing. Do not treat this as a photorealistic result. |

Hold the left mouse button to orbit and use the mouse wheel to zoom. The FPS overlay is diagnostic feedback, not a benchmark.

If the scene fails to start, fix the reported Godot, .NET, or graphics-driver error before continuing. `res://test_foveacore.tscn` is an older mesh/script sandbox, not this tutorial.

## 2. Add a splat to your own scene

1. Create a new **3D Scene** with a `Node3D` root and save it as `res://scenes/first_splat.tscn`.
2. Add a `Camera3D` and a `DirectionalLight3D`.
3. Add a `FoveaSplat3D` node.
4. Set `source_path` to a project-local asset. The smallest committed PLY is `res://test/demo_bonsai.ply`. The redistributable reconstruction is `res://reconstructions/horse_statue_cc0_v1/fovea_runtime/horse_statue_6999_runtime_v1.ply`.
5. Leave `quality_preset` on `AUTO` unless you need an explicit density/culling trade-off.
6. Keep `generate_collisions` off unless the source is a `.fovea` asset. Collision generation is rejected for `.ply` / `.splat` files.

The same node can be created from GDScript:

```gdscript
var splat := FoveaSplat3D.new()
splat.source_path = "res://test/demo_bonsai.ply"
splat.quality_preset = FoveaSplat3D.QualityPreset.BALANCED
splat.opacity = 1.0
add_child(splat)
```

`source_path` accepts `.ply`, `.splat`, and `.fovea`. PLY is the validated desktop rendering path. The `.splat` parser has a deterministic round-trip but no compatibility capture. Native `.fovea` loading is experimental.

## 3. Confirm the result

1. Position the camera so it faces the asset.
2. Run `first_splat.tscn`.
3. Confirm that the Output dock contains no unresolved-resource or parse errors.
4. If the splat is missing, check that the path starts with `res://`, that the file exists on disk, and that the renderer is Forward+ rather than Compatibility.

Common runtime controls on `FoveaSplat3D`:

- `enabled` - show or hide the asset
- `quality_preset` - `AUTO`, `PERFORMANCE`, `BALANCED`, or `CINEMATIC`
- `opacity` - 0.0 to 1.0 multiplier
- `is_static` - keep this on for a still capture; turn it off only when the asset will animate
- `get_advanced()` - experimental styling and animation delegate, available after `_ready()`

## Next steps

- Read the [Drop a PLY demo notes](../demo/README.md) for provenance details.
- Configure FFmpeg, COLMAP, and the gsplat trainer with [Reconstruction setup](reconstruction_setup.md).
- Convert a loaded PLY to `.fovea` with [3DGS training and baking](3dgs_training.md).
- Check [Feature status](../docs/feature-status.md) before enabling GPU, XR, or research reconstruction paths.
