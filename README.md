# FoveaEngine

FoveaEngine is a Godot 4 addon project for experimenting with Gaussian-splat rendering, VR interaction, and video-to-3D reconstruction workflows.

> **Project status:** active development. Treat this repository as pre-release software until the release checklist and runtime validation have completed on the target platform.

## What you can use today

- Load and render supported Gaussian-splat assets in Godot scenes.
- Use the FoveaCore addon and its test scenes as integration starting points.
- Configure FFmpeg and COLMAP for the classical StudioTo3D workflow.
- Explore OpenXR, foveation, GPU culling, editing, and animation subsystems on compatible hardware.

The exact readiness of each feature is listed in [Feature status](docs/feature-status.md). GPU, XR, and reconstruction paths still require validation on the target machine.

## Requirements

- Godot **4.7 or a compatible later 4.7 build**, with C# / Mono support.
- A Forward+ capable graphics device for RenderingDevice-based features.
- FFmpeg on `PATH` for video frame extraction.
- COLMAP on `PATH` for the classical reconstruction path.
- Python for optional reconstruction bridges.

See [Dependencies](DEPENDENCIES.md) for configuration details.

## Quick start

1. Clone this repository.
2. Open `project.godot` in Godot 4.7.
3. Enable the included plugins if Godot has not enabled them automatically.
4. Run the project’s main test scene, `res://test_foveacore.tscn`.
5. Follow the [First splat tutorial](tutorials/get_started.md) to add a splat asset to your own scene.

For a video reconstruction workflow, first complete [Reconstruction setup](tutorials/reconstruction_setup.md).

## Documentation

- [First splat tutorial](tutorials/get_started.md) — create a minimal scene and load an asset.
- [Reconstruction setup](tutorials/reconstruction_setup.md) — configure FFmpeg, COLMAP, and optional bridges.
- [3DGS training and editing](tutorials/3dgs_training.md) — optimization and editing notes.
- [Feature status](docs/feature-status.md) — supported, experimental, and unavailable capabilities.
- [Developer reference](docs/developer_reference.md) — subsystem-oriented API notes.
- [Dependencies](DEPENDENCIES.md) — external tools and configuration.

## Reconstruction backends

The project includes bridge entry points for several research backends. Their presence does not mean that a production inference path is available.

| Backend | Current integration status |
| --- | --- |
| WorldMirror 2.0 | Optional bridge; requires local installation and target-machine validation. |
| COLMAP | Classical external-tool workflow; requires a working local COLMAP installation. |
| DVLT | Dry-run integration only; inference calls are not wired. |
| AnyRecon | Dry-run integration only; inference pipeline is not wired. |
| Vista4D | Not implemented; production invocation fails explicitly. |

## Contributing and validation

Before proposing a change, run the repository checks and the relevant Godot scene on the hardware you intend to support. The Python validation utilities are under `addons/tools/`.
