# External dependencies

FoveaEngine does not bundle its reconstruction executables or model weights. Install only the tools needed for the workflow you intend to use.

## Baseline tools

### FFmpeg

FFmpeg extracts frames from video inputs.

1. Install FFmpeg using your platform’s package manager or a trusted distribution.
2. Ensure `ffmpeg` is available on your system `PATH`, or provide its full executable path in the StudioTo3D settings.
3. Verify it from a terminal with `ffmpeg -version`.

### COLMAP

COLMAP provides the classical Structure-from-Motion route.

1. Install a COLMAP build appropriate for your platform and GPU.
2. Ensure `colmap` is available on `PATH`, or provide its full executable path in the StudioTo3D settings.
3. Verify it with `colmap -h`.

## Configure Godot

The project defaults to the command names `ffmpeg`, `colmap`, and `python`. This keeps the repository portable and lets each developer configure their own environment.

In the StudioTo3D settings, set explicit executable paths only when the commands are not available on `PATH`. Do not commit machine-specific paths to `project.godot`.

## Optional Python reconstruction bridges

Python bridges are optional and are not a substitute for their upstream model installations.

- **WorldMirror 2.0:** optional bridge; install the required Python package, weights, and CUDA stack in an isolated environment. Validate it locally before relying on it.
- **DVLT and AnyRecon:** current bridge support is dry-run only. It must not be used to produce deliverable reconstructions.
- **Vista4D:** not implemented in this project. The bridge exits with an error for a non-dry-run invocation.

Use a virtual environment for Python dependencies and keep model weights outside the repository. Hardware requirements and inference time depend on the upstream backend, model revision, input size, and GPU; benchmark them on your own target hardware.
