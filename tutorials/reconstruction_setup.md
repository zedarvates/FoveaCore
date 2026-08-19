# How-to: Configure StudioTo3D reconstruction tools

This guide prepares the external tools used by StudioTo3D. It configures executables and describes the current trainer contract. It does not promise a successful reconstruction: camera coverage, input quality, GPU support, and the selected backend all affect the outcome.

## Scope

The classical path is:

1. FFmpeg extracts frames from a video.
2. COLMAP estimates cameras.
3. [`gsplat_bridge.py`](../addons/foveacore/scripts/reconstruction/gsplat_bridge.py) trains a PLY with the official gsplat trainer.

WorldMirror, DVLT, AnyRecon, and Vista4D are optional research paths with different maturity. See [Feature status](../docs/feature-status.md).

## 1. Install FFmpeg

Install FFmpeg from your platform package manager or a trusted build. Make the `ffmpeg` executable available on `PATH`.

```text
ffmpeg -version
```

## 2. Install COLMAP

Install a COLMAP build appropriate for your platform and make `colmap` available on `PATH`.

```text
colmap -h
```

## 3. Prepare a gsplat runtime

StudioTo3D no longer calls an unspecified `train.py`. The reconstruction backend resolves `gsplat_bridge.py`, which keeps the legacy `-s` / `-m` / `--iterations` interface and requires:

- source images
- a COLMAP sparse model
- a CUDA-enabled official gsplat installation

Set `FOVEA_GSPLAT_PYTHON` when gsplat lives in a dedicated interpreter. The bridge refuses a non-empty output directory and publishes:

```text
<source>/output/point_cloud/iteration_<N>/point_cloud.ply
<source>/output/fovea_gsplat_training_manifest.json
```

The manifest records SHA-256 provenance. The bridge does not synthesize images or cameras.

## 4. Configure paths in Godot

1. Open the StudioTo3D panel in the Godot editor.
2. Leave the defaults (`ffmpeg`, `colmap`, and `python`) when those commands are on `PATH`.
3. Otherwise set full local paths for the corresponding executables.
4. Use the panel tool-check action and correct every reported failure before starting a session.

Never commit personal executable paths to `project.godot`.

## 5. Run the classical workflow

1. Start with a short video that has sharp, overlapping views and limited motion blur.
2. Select the video in StudioTo3D.
3. Extract frames with FFmpeg.
4. Run the COLMAP stage and inspect the generated workspace.
5. Only then start gsplat training.

If COLMAP cannot establish camera poses, capture more overlap, improve lighting, or use an input with more visible texture. Do not treat a partially generated workspace as a completed reconstruction.

## Optional research bridges

WorldMirror 2.0 has an optional local bridge, but it needs its own upstream installation, model weights, CUDA environment, and target-machine validation.

DVLT and AnyRecon only support dry-run integration in the current codebase. Vista4D is not implemented and rejects a production invocation. These paths are useful for development tracking, not for deliverable reconstruction output.
