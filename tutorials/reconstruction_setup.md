# How-to: Configure StudioTo3D reconstruction tools

This guide is for developers who want to prepare the external tools used by StudioTo3D. It covers the classical FFmpeg + COLMAP route and accurately describes the optional research bridges.

## Scope

This guide configures executables. It does not promise a successful reconstruction: camera coverage, input quality, GPU support, and the selected backend all affect the outcome.

## 1. Install FFmpeg

Install FFmpeg using your platform’s package manager or a trusted distribution. Make the `ffmpeg` executable available on `PATH`.

Verify the installation:

```text
ffmpeg -version
```

## 2. Install COLMAP

Install a COLMAP build appropriate for your platform. Make `colmap` available on `PATH`.

Verify the installation:

```text
colmap -h
```

## 3. Configure paths in Godot

1. Open the StudioTo3D panel in the Godot editor.
2. Find its settings section.
3. Leave the defaults (`ffmpeg`, `colmap`, and `python`) when the commands are on `PATH`.
4. Otherwise, set full local paths for the corresponding executables.
5. Use the panel’s tool-check action, then correct every reported failure before starting a session.

Never commit personal executable paths to `project.godot`.

## 4. Run the classical workflow

1. Start with a short video that has sharp, overlapping views and limited motion blur.
2. Select the video in StudioTo3D.
3. Extract frames with FFmpeg.
4. Run the COLMAP stage.
5. Inspect the panel output and generated workspace before moving to any later processing stage.

If COLMAP cannot establish camera poses, capture more overlap, improve lighting, or use an input with more visible texture. Do not treat a partially generated workspace as a completed reconstruction.

## Optional research bridges

WorldMirror 2.0 has an optional local bridge, but it needs its own upstream installation, model weights, CUDA environment, and target-machine validation.

DVLT and AnyRecon only support dry-run integration in the current codebase. Vista4D is not implemented and rejects a production invocation. These paths are useful for development tracking, not for deliverable reconstruction output.

For the complete status, see [Feature status](../docs/feature-status.md).
