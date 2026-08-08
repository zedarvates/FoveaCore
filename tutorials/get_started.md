# Tutorial: Load your first Gaussian splat

This tutorial is for Godot developers who are new to FoveaEngine. You will open the project, run its test scene, and add a splat asset to a simple 3D scene.

## Before you begin

- Install Godot 4.7 (C# / Mono build).
- Clone this repository.
- Have a supported `.ply` splat asset available in your project, for example at `res://assets/example.ply`.

This tutorial does not require FFmpeg, COLMAP, VR hardware, or a reconstruction backend.

## 1. Open and validate the project

1. Import `project.godot` in Godot.
2. Let Godot import project resources.
3. Open `res://test_foveacore.tscn`.
4. Run the scene and inspect the Godot Output panel for errors.

If the scene does not run, resolve the reported Godot or graphics-driver issue before continuing. RenderingDevice features require a compatible renderer; a headless or Compatibility setup may not exercise them.

## 2. Create a minimal scene

1. Create a new **3D Scene** with a `Node3D` root.
2. Save it as `res://scenes/first_splat.tscn`.
3. Add a `FoveaSplat3D` node.
4. In the Inspector, set its `source_path` to `res://assets/example.ply`.
5. Save the scene. The node loads the asset when the scene runs.

Use the inspector for properties exposed by the version of the addon in your checkout. The project is under active development, so exported property names can evolve.

## 3. Run the scene

1. Add a camera and a directional light if your scene does not already contain them.
2. Position the camera so that it faces the splat asset.
3. Run `first_splat.tscn`.

You should see the asset render without unresolved-resource errors. If it does not appear, check that the asset path starts with `res://`, that the file exists, and that the Output panel contains no parsing or graphics errors.

## Next steps

- Configure video reconstruction with [Reconstruction setup](reconstruction_setup.md).
- Read [Feature status](../docs/feature-status.md) before enabling experimental GPU, XR, or animation paths.
- Use the repository test scenes as integration examples while the public API stabilizes.
