<div align="center">
  <img src="../icon.svg" alt="FoveaEngine logo" width="88" />

  <h1>Drop a PLY</h1>
  <p><strong>The shortest path from a Gaussian-splat asset to a live Godot scene.</strong></p>
  <p><a href="../README.md">Project overview</a> · <a href="../tutorials/get_started.md">First-splat tutorial</a> · <a href="../docs/feature-status.md">Feature status</a></p>
</div>

## What the demo proves

[`drop_a_ply.tscn`](drop_a_ply.tscn) is a regular Godot scene containing:

- a `FoveaSplat3D` node that first looks for the local 17,013-splat reconstruction trained from a real camera video, then uses the checked-in 25,674-splat synthetic-video reconstruction when the rights-restricted local proof is absent;
- a standard `WorldEnvironment`, directional light, and `Camera3D`;
- an explicit source/provenance label so the trained reconstruction cannot be confused with the fallback fixture;
- a small FPS overlay for immediate visual feedback.

No FFmpeg, COLMAP, OpenXR runtime, or VR headset is required to open an existing PLY asset.

### Why the Furby capture is useful

The local Furby turntable is FoveaEngine's primary real-camera object stress
case. Its fur tests dense soft detail, its ears test thin structures, its glossy
eyes test view-dependent appearance, and the motion visible in the source tests
whether the proof record preserves reconstruction failures instead of hiding
them. It is a representative object-turntable test for this project, not a
standardized academic benchmark.

The complete recorded path is 60 extracted views, COLMAP-compatible poses,
7,000 gsplat training iterations, 18,774 trained Gaussians, and a sanitized
17,013-splat runtime PLY. The resulting blur and ghosted ears are attributed to
subject movement during capture, not to image generation or PLY compression.

On the validation workstation, the runtime default is
`res://reconstructions/furby_real_60_v1/fovea_runtime/furby_6999_runtime_foreground_v1.ply`.
It was reconstructed from 60 views extracted from a real-world camera video,
not generated from a still image. That source and its output stay local because
the footage is validation-only and not redistributable.

The redistributable fallback lives at
`res://reconstructions/horse_statue_cc0_v1/fovea_runtime/horse_statue_6999_runtime_v1.ply`.
It was trained with gsplat from a real MP4 frame sequence, but that MP4 is a
synthetic multi-view render rather than a real-world camera capture. The source
model is [Horse Statue 01](https://polyhaven.com/a/horse_statue_01) by Rico
Cilliers, distributed as CC0 by Poly Haven. The runtime PLY is therefore a true
view-dependent 3D Gaussian reconstruction, not an AI-generated still, while its
source classification remains explicit and honest.

When the asset is missing, the scene says **COMPATIBILITY FIXTURE** on screen
and loads the small checked-in parser fixture; that fallback is never presented
as a reconstructed photorealistic result.

> [!NOTE]
> PLY is the validated rendering path demonstrated here. The `.splat` parser has a validated round-trip but no compatibility capture. Native `.fovea` registration now works after a live path change, but its compute renderer still fails the visual gate. Planned `.spz` files are rejected until a decoder exists. See the [feature status matrix](../docs/feature-status.md) before testing another format.

## Run it

1. Open [`demo/drop_a_ply.tscn`](drop_a_ply.tscn) in Godot 4.7.dev5 Mono or a compatible later 4.7 build.
2. Select **Play Current Scene**.
3. Confirm that the source label starts with **REAL CAMERA VIDEO 3DGS** when the local proof exists. Public clones without it must explicitly show **SYNTHETIC VIDEO 3DGS**; the FPS counter updates in the upper-left corner.
4. Hold the left mouse button and drag to orbit around the splat; use the wheel to zoom.

## Reconstruct with the default backend

StudioTo3D now resolves
[`gsplat_bridge.py`](../addons/foveacore/scripts/reconstruction/gsplat_bridge.py)
instead of an unspecified `train.py`. The bridge keeps the legacy CLI contract,
requires source images plus COLMAP cameras, verifies a CUDA-enabled official gsplat
runtime, saves the final PLY, and emits a SHA-256 provenance manifest.

Set `FOVEA_GSPLAT_PYTHON` when gsplat is installed in a dedicated environment.
The generated PLY is published at the path already consumed by StudioTo3D:

```text
<session>/output/point_cloud/iteration_<N>/point_cloud.ply
```

## Try your own asset

Select the `FoveaSplat3D` node and replace `source_path` with a project-local `.ply` file:

```gdscript
var splat := FoveaSplat3D.new()
splat.source_path = "res://assets/my_capture.ply"
add_child(splat)
```

You can also use the **+ FoveaSplat3D** editor action to create the node from a file. Validate the visual result and GPU behavior with your own capture before treating it as production-ready.

## Regenerate the scene

The committed scene is built programmatically so its structure stays reproducible:

```bash
godot --headless --path . -s res://demo/build_demo_scene.gd
```

The generator writes `res://demo/drop_a_ply.tscn` and exits non-zero if packing or saving fails.

## Next steps

- Follow the [first-splat tutorial](../tutorials/get_started.md) for runtime controls and collision options.
- Review the [benchmark harness](../docs/benchmark.md) before making performance claims.
- Track the [experimental demo-scene roadmap](../demo_scenes/README.md) without treating its placeholders as implemented features.
- Configure [StudioTo3D reconstruction](../tutorials/reconstruction_setup.md) when you want to build an asset from video.
