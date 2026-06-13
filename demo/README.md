# FoveaEngine — "Drop a PLY" demo

The 60-second pitch of FoveaEngine: a Gaussian Splatting cloud rendering live in a
standard Godot scene.

## Run it

1. Open `demo/drop_a_ply.tscn` in the editor.
2. Press **F5** (or the Play Scene button).
3. A splat cloud renders under a sky + sun, with an FPS readout top-left.

The scene contains a `FoveaSplat3D` node pointing at the reference fixture
(`res://test/fixtures/reference_3dgs.ply`, 8000 splats). Swap `source_path` for
your own `.ply` / `.fovea` / `.spz` to view any capture.

## Regenerating the scene

The scene is built programmatically so it's always valid:

```bash
godot --headless --path . -s res://demo/build_demo_scene.gd
```

## See also

- `docs/benchmark.md` — performance harness and the 90 FPS target.
- Drag & drop a `.ply` from the FileSystem dock straight into the 3D viewport
  (E1) is the companion authoring flow — verify it in the editor.
