#!/usr/bin/env python3
"""Verify a FoveaEngine video-to-3DGS runtime proof manifest."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import sys
from typing import Any
from file_digest import sha256


EXPECTED_SCHEMA = "fovea.video_3dgs.runtime_proof.v1"


def ply_vertex_count(path: Path) -> int:
    with path.open("rb") as stream:
        for raw_line in stream:
            line = raw_line.decode("ascii", errors="strict").strip()
            if line.startswith("element vertex "):
                return int(line.rsplit(" ", 1)[1])
            if line == "end_header":
                break
    raise ValueError(f"missing PLY vertex count: {path}")


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"invalid PNG header: {path}")
    return struct.unpack(">II", header[16:24])


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected a JSON object: {path}")
    return value


def verify(manifest_path: Path) -> None:
    manifest_path = manifest_path.resolve()
    manifest = load_json(manifest_path)
    if manifest.get("schema") != EXPECTED_SCHEMA:
        raise ValueError(f"unexpected proof schema: {manifest.get('schema')}")

    hashes = manifest.get("hashes")
    if not isinstance(hashes, dict) or len(hashes) < 10:
        raise ValueError("proof manifest must contain the complete artifact hash set")
    for relative, expected in hashes.items():
        path = (manifest_path.parent / relative).resolve()
        if not path.is_file():
            raise FileNotFoundError(f"proof artifact is missing: {path}")
        observed = sha256(path)
        if observed != expected:
            raise ValueError(
                f"hash mismatch for {path}: expected {expected}, observed {observed}"
            )

    dataset = manifest["dataset"]
    source_class = dataset.get("source_class")
    if source_class is None and "real_view_count" in dataset:
        source_class = "real_multiview_video"
    if source_class not in {"real_multiview_video", "synthetic_multiview_video"}:
        raise ValueError(f"unsupported source class: {source_class}")
    view_count = dataset.get("view_count", dataset.get("real_view_count"))
    if not isinstance(view_count, int) or view_count < 3:
        raise ValueError("proof must declare at least three source views")

    preprocess = load_json(
        (manifest_path.parent / dataset["preprocess_manifest"]).resolve()
    )
    if preprocess.get("frame_count") != view_count:
        raise ValueError("preprocess frame count does not match proof view count")
    if source_class == "real_multiview_video":
        if preprocess.get("geometry_generated") is not False:
            raise ValueError(
                "real-video preprocess manifest must state that it generated no geometry"
            )
    else:
        if preprocess.get("source_class") != source_class:
            raise ValueError("synthetic-video preprocess source class does not match proof")
        if preprocess.get("geometry_id_masks") is not True:
            raise ValueError("synthetic-video proof requires explicit geometry ID masks")
        if preprocess.get("mask_estimation_model") is not None:
            raise ValueError("synthetic-video proof must not relabel estimated masks as ID masks")

    camera = load_json(
        (manifest_path.parent / dataset["camera_manifest"]).resolve()
    )
    if camera.get("frame_count") != view_count:
        raise ValueError("camera model does not cover every source view")
    if camera.get("point_count", 0) <= 0:
        raise ValueError("camera prior has no visual-hull SfM initialization points")

    artifacts = manifest["artifacts"]
    trained = artifacts["trained_ply"]
    runtime = artifacts["runtime_ply"]
    trained_path = (manifest_path.parent / trained["path"]).resolve()
    runtime_path = (manifest_path.parent / runtime["path"]).resolve()
    if trained_path.is_file():
        if ply_vertex_count(trained_path) != trained["splats"]:
            raise ValueError("trained PLY vertex count does not match proof")
    elif trained.get("required_in_repo", True):
        raise FileNotFoundError(f"trained PLY is missing: {trained_path}")
    if ply_vertex_count(runtime_path) != runtime["splats"]:
        raise ValueError("runtime PLY vertex count does not match proof")

    captures = manifest.get("captures", [])
    required_roles = {"front", "side_a", "rear", "side_b"}
    roles = {capture.get("role") for capture in captures}
    if not required_roles.issubset(roles):
        raise ValueError("front, rear and both side captures are required")
    for capture in captures:
        path = (manifest_path.parent / capture["path"]).resolve()
        declared_resolution = capture.get("resolution", [512, 512])
        if (
            not isinstance(declared_resolution, list)
            or len(declared_resolution) != 2
            or not all(isinstance(value, int) and value > 0 for value in declared_resolution)
        ):
            raise ValueError(f"invalid declared capture resolution: {path}")
        if png_size(path) != tuple(declared_resolution):
            raise ValueError(f"unexpected capture dimensions: {path}")
        if capture.get("role") in required_roles:
            matrix = capture.get("camera_c2w_opencv")
            runtime_camera = capture.get("runtime_camera")
            has_exact_matrix = isinstance(matrix, list) and len(matrix) == 16
            has_runtime_camera = (
                isinstance(runtime_camera, dict)
                and isinstance(runtime_camera.get("azimuth_degrees"), (int, float))
                and isinstance(runtime_camera.get("elevation_degrees"), (int, float))
                and runtime_camera.get("up_axis") in {"x", "y", "z"}
                and isinstance(runtime_camera.get("fov_degrees"), (int, float))
                and isinstance(runtime_camera.get("frame_margin"), (int, float))
            )
            if not has_exact_matrix and not has_runtime_camera:
                raise ValueError(f"capture has no reproducible camera definition: {path}")

    metrics = manifest["training"]["validation_metrics"]
    if metrics.get("num_gaussians") != trained.get("splats"):
        raise ValueError("training metric splat count does not match trained PLY")
    if metrics.get("psnr", 0.0) <= 0.0 or metrics.get("ssim", 0.0) <= 0.0:
        raise ValueError("training metrics are missing")

    print(
        "Runtime proof verified: "
        f"{view_count} {source_class} views -> {trained['splats']} trained splats "
        f"-> {runtime['splats']} runtime splats -> {len(captures)} captures"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    verify(args.manifest)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, TypeError, ValueError) as exc:
        print(f"Runtime proof verification failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
