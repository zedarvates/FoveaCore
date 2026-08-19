#!/usr/bin/env python3
"""Build a deterministic COLMAP model for a full turntable capture.

This is a constrained calibration path for captures where the camera is fixed,
the isolated subject performs one uniform full revolution, and the frames are
chronological. It does not pretend that the poses are unconstrained SfM output:
the generated manifest records the circular-pose prior and all parameters.

Initial 3D points are sampled from the multi-view visual hull of the real masks.
The resulting cameras.bin/images.bin/points3D.bin files can be consumed by the
official gsplat COLMAP dataset loader.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from file_digest import sha256


SUPPORTED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


def parse_pair(value: str) -> tuple[float, float]:
    parts = [float(part.strip()) for part in value.split(",")]
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("value must contain two comma-separated numbers")
    return parts[0], parts[1]


def normalize(vector: np.ndarray) -> np.ndarray:
    length = float(np.linalg.norm(vector))
    if length <= 1.0e-12:
        raise ValueError("cannot normalize a zero-length vector")
    return vector / length


def rotation_matrix_to_qvec(matrix: np.ndarray) -> np.ndarray:
    """Convert a 3x3 rotation matrix to COLMAP's (qw, qx, qy, qz)."""
    trace = float(np.trace(matrix))
    if trace > 0.0:
        scale = math.sqrt(trace + 1.0) * 2.0
        qw = 0.25 * scale
        qx = (matrix[2, 1] - matrix[1, 2]) / scale
        qy = (matrix[0, 2] - matrix[2, 0]) / scale
        qz = (matrix[1, 0] - matrix[0, 1]) / scale
    else:
        diagonal = np.diag(matrix)
        index = int(np.argmax(diagonal))
        if index == 0:
            scale = math.sqrt(1.0 + matrix[0, 0] - matrix[1, 1] - matrix[2, 2]) * 2.0
            qw = (matrix[2, 1] - matrix[1, 2]) / scale
            qx = 0.25 * scale
            qy = (matrix[0, 1] + matrix[1, 0]) / scale
            qz = (matrix[0, 2] + matrix[2, 0]) / scale
        elif index == 1:
            scale = math.sqrt(1.0 + matrix[1, 1] - matrix[0, 0] - matrix[2, 2]) * 2.0
            qw = (matrix[0, 2] - matrix[2, 0]) / scale
            qx = (matrix[0, 1] + matrix[1, 0]) / scale
            qy = 0.25 * scale
            qz = (matrix[1, 2] + matrix[2, 1]) / scale
        else:
            scale = math.sqrt(1.0 + matrix[2, 2] - matrix[0, 0] - matrix[1, 1]) * 2.0
            qw = (matrix[1, 0] - matrix[0, 1]) / scale
            qx = (matrix[0, 2] + matrix[2, 0]) / scale
            qy = (matrix[1, 2] + matrix[2, 1]) / scale
            qz = 0.25 * scale
    qvec = normalize(np.array([qw, qx, qy, qz], dtype=np.float64))
    return -qvec if qvec[0] < 0.0 else qvec


def make_pose(
    angle: float,
    radius: float,
    elevation: float,
    target_z: float,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    center = np.array(
        [radius * math.cos(angle), radius * math.sin(angle), elevation],
        dtype=np.float64,
    )
    target = np.array([0.0, 0.0, target_z], dtype=np.float64)
    forward = normalize(target - center)
    world_up = np.array([0.0, 0.0, 1.0], dtype=np.float64)
    right = normalize(np.cross(forward, world_up))
    down = normalize(np.cross(forward, right))
    camera_to_world = np.column_stack((right, down, forward))
    world_to_camera = camera_to_world.T
    translation = -world_to_camera @ center
    return center, world_to_camera, translation


def load_capture(
    images_dir: Path,
    masks_dir: Path,
) -> tuple[list[Path], list[np.ndarray], list[np.ndarray]]:
    image_paths = sorted(
        path
        for path in images_dir.iterdir()
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )
    if len(image_paths) < 8:
        raise ValueError("a turntable model requires at least 8 chronological frames")

    images: list[np.ndarray] = []
    masks: list[np.ndarray] = []
    expected_size: tuple[int, int] | None = None
    for image_path in image_paths:
        image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
        if image is None:
            raise ValueError(f"failed to read image: {image_path}")
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        mask_path = masks_dir / f"{image_path.name}.png"
        if not mask_path.is_file():
            mask_path = masks_dir / image_path.name
        mask = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            raise ValueError(f"failed to read mask for {image_path.name}")
        if mask.shape != image.shape[:2]:
            raise ValueError(f"mask size differs from image for {image_path.name}")
        size = (image.shape[1], image.shape[0])
        if expected_size is None:
            expected_size = size
        elif size != expected_size:
            raise ValueError("all turntable images must have identical dimensions")
        binary = mask >= 128
        if not np.any(binary):
            raise ValueError(f"empty foreground mask for {image_path.name}")
        images.append(image)
        masks.append(binary)
    return image_paths, images, masks


def project_points(
    points: np.ndarray,
    rotation: np.ndarray,
    translation: np.ndarray,
    focal: float,
    principal: tuple[float, float],
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    camera = points @ rotation.T + translation
    depth = camera[:, 2]
    safe_depth = np.where(depth > 1.0e-8, depth, 1.0)
    u = focal * camera[:, 0] / safe_depth + principal[0]
    v = focal * camera[:, 1] / safe_depth + principal[1]
    return u, v, depth


def visual_hull(
    masks: list[np.ndarray],
    poses: list[tuple[np.ndarray, np.ndarray, np.ndarray]],
    focal: float,
    principal: tuple[float, float],
    resolution: int,
    min_views: int,
    radius: float,
) -> tuple[np.ndarray, np.ndarray, dict[str, Any]]:
    height, width = masks[0].shape
    bboxes: list[tuple[int, int, int, int]] = []
    for mask in masks:
        ys, xs = np.where(mask)
        bboxes.append((int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)))

    bbox_array = np.asarray(bboxes, dtype=np.float64)
    widths = bbox_array[:, 2] - bbox_array[:, 0]
    heights = bbox_array[:, 3] - bbox_array[:, 1]
    vertical_centers = (bbox_array[:, 1] + bbox_array[:, 3]) * 0.5
    horizontal_extent = radius * float(np.percentile(widths, 95)) / (2.0 * focal) * 1.35
    vertical_extent = radius * float(np.percentile(heights, 95)) / (2.0 * focal) * 1.35
    target_z = -(
        float(np.median(vertical_centers)) - principal[1]
    ) * radius / focal

    xs = np.linspace(-horizontal_extent, horizontal_extent, resolution, dtype=np.float32)
    ys = np.linspace(-horizontal_extent, horizontal_extent, resolution, dtype=np.float32)
    zs = np.linspace(
        target_z - vertical_extent,
        target_z + vertical_extent,
        resolution,
        dtype=np.float32,
    )
    grid = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), axis=-1)
    points = grid.reshape(-1, 3)
    support = np.zeros(points.shape[0], dtype=np.uint8)
    for mask, (_, rotation, translation) in zip(masks, poses):
        u, v, depth = project_points(points, rotation, translation, focal, principal)
        ui = np.rint(u).astype(np.int32)
        vi = np.rint(v).astype(np.int32)
        valid = (
            (depth > 0.0)
            & (ui >= 0)
            & (ui < width)
            & (vi >= 0)
            & (vi < height)
        )
        indices = np.where(valid)[0]
        inside = mask[vi[indices], ui[indices]]
        support[indices[inside]] += 1

    occupied = (support >= min_views).reshape(resolution, resolution, resolution)
    if not np.any(occupied):
        raise RuntimeError("visual hull is empty; verify masks, focal length, and turn direction")
    interior = np.zeros_like(occupied)
    interior[1:-1, 1:-1, 1:-1] = (
        occupied[1:-1, 1:-1, 1:-1]
        & occupied[:-2, 1:-1, 1:-1]
        & occupied[2:, 1:-1, 1:-1]
        & occupied[1:-1, :-2, 1:-1]
        & occupied[1:-1, 2:, 1:-1]
        & occupied[1:-1, 1:-1, :-2]
        & occupied[1:-1, 1:-1, 2:]
    )
    surface = occupied & ~interior
    surface_points = grid[surface]

    scalar = occupied.astype(np.float32)
    gradients = np.gradient(scalar)
    inward = np.stack(gradients, axis=-1)[surface]
    normals = -inward
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    radial = surface_points.copy()
    radial[:, 2] = 0.0
    radial_lengths = np.linalg.norm(radial, axis=1, keepdims=True)
    radial = radial / np.maximum(radial_lengths, 1.0e-8)
    normals = np.where(lengths > 1.0e-8, normals / np.maximum(lengths, 1.0e-8), radial)

    stats = {
        "grid_resolution": resolution,
        "grid_bounds": [
            [float(xs[0]), float(ys[0]), float(zs[0])],
            [float(xs[-1]), float(ys[-1]), float(zs[-1])],
        ],
        "target_z_from_mask_centers": target_z,
        "occupied_voxels": int(np.count_nonzero(occupied)),
        "surface_voxels": int(surface_points.shape[0]),
        "min_supporting_views": min_views,
    }
    return surface_points, normals, stats


def sample_colors(
    points: np.ndarray,
    normals: np.ndarray,
    images: list[np.ndarray],
    masks: list[np.ndarray],
    poses: list[tuple[np.ndarray, np.ndarray, np.ndarray]],
    focal: float,
    principal: tuple[float, float],
) -> np.ndarray:
    height, width = masks[0].shape
    centers = np.stack([pose[0] for pose in poses])
    view_vectors = centers[None, :, :] - points[:, None, :]
    view_vectors /= np.maximum(np.linalg.norm(view_vectors, axis=2, keepdims=True), 1.0e-8)
    scores = np.sum(view_vectors * normals[:, None, :], axis=2)
    order = np.argsort(-scores, axis=1)
    colors = np.zeros((points.shape[0], 3), dtype=np.uint8)
    found = np.zeros(points.shape[0], dtype=bool)

    for rank in range(len(poses)):
        pending = np.where(~found)[0]
        if pending.size == 0:
            break
        camera_indices = order[pending, rank]
        for camera_index in np.unique(camera_indices):
            selected = pending[camera_indices == camera_index]
            _, rotation, translation = poses[int(camera_index)]
            u, v, depth = project_points(
                points[selected], rotation, translation, focal, principal
            )
            ui = np.rint(u).astype(np.int32)
            vi = np.rint(v).astype(np.int32)
            valid = (
                (depth > 0.0)
                & (ui >= 0)
                & (ui < width)
                & (vi >= 0)
                & (vi < height)
            )
            valid_indices = np.where(valid)[0]
            if valid_indices.size == 0:
                continue
            visible = masks[int(camera_index)][vi[valid_indices], ui[valid_indices]]
            accepted = valid_indices[visible]
            if accepted.size == 0:
                continue
            target_indices = selected[accepted]
            colors[target_indices] = images[int(camera_index)][vi[accepted], ui[accepted]]
            found[target_indices] = True
    if not np.all(found):
        colors[~found] = np.array([128, 128, 128], dtype=np.uint8)
    return colors


def write_colmap_model(
    output_dir: Path,
    image_paths: list[Path],
    poses: list[tuple[np.ndarray, np.ndarray, np.ndarray]],
    points: np.ndarray,
    colors: np.ndarray,
    image_size: tuple[int, int],
    focal: float,
    principal: tuple[float, float],
) -> None:
    width, height = image_size
    with (output_dir / "cameras.bin").open("wb") as stream:
        stream.write(struct.pack("<Q", 1))
        # PINHOLE (model id 1): fx, fy, cx, cy. Avoid an unnecessary
        # undistortion pass for a zero-distortion turntable prior.
        stream.write(struct.pack("<IiQQ", 1, 1, width, height))
        stream.write(struct.pack("<dddd", focal, focal, principal[0], principal[1]))

    with (output_dir / "images.bin").open("wb") as stream:
        stream.write(struct.pack("<Q", len(image_paths)))
        for image_id, (image_path, (_, rotation, translation)) in enumerate(
            zip(image_paths, poses), start=1
        ):
            qvec = rotation_matrix_to_qvec(rotation)
            stream.write(struct.pack("<I", image_id))
            stream.write(struct.pack("<dddd", *qvec.tolist()))
            stream.write(struct.pack("<ddd", *translation.tolist()))
            stream.write(struct.pack("<I", 1))
            stream.write(image_path.name.encode("utf-8") + b"\x00")
            stream.write(struct.pack("<Q", 0))

    with (output_dir / "points3D.bin").open("wb") as stream:
        stream.write(struct.pack("<Q", len(points)))
        for point_id, (point, color) in enumerate(zip(points, colors), start=1):
            stream.write(struct.pack("<QdddBBBdQ", point_id, *point.tolist(), *color.tolist(), 0.0, 0))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--images", required=True, type=Path)
    parser.add_argument("--masks", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--focal", type=float, default=614.4)
    parser.add_argument("--principal-point", type=parse_pair)
    parser.add_argument("--radius", type=float, default=3.0)
    parser.add_argument("--elevation", type=float, default=0.12)
    parser.add_argument("--target-z", type=float, default=-0.25)
    parser.add_argument("--grid-resolution", type=int, default=96)
    parser.add_argument("--min-view-ratio", type=float, default=0.9)
    parser.add_argument("--max-points", type=int, default=50000)
    parser.add_argument("--seed", type=int, default=0)
    args = parser.parse_args()

    if not args.images.is_dir() or not args.masks.is_dir():
        parser.error("images and masks must be existing directories")
    if args.output.exists():
        parser.error(f"output already exists (refusing to overwrite): {args.output}")
    if args.focal <= 0.0 or args.radius <= 0.0:
        parser.error("focal and radius must be positive")
    if args.grid_resolution < 32 or args.grid_resolution > 192:
        parser.error("grid-resolution must be between 32 and 192")
    if args.min_view_ratio < 0.5 or args.min_view_ratio > 1.0:
        parser.error("min-view-ratio must be between 0.5 and 1.0")
    if args.max_points < 1000:
        parser.error("max-points must be at least 1000")

    image_paths, images, masks = load_capture(args.images, args.masks)
    height, width = masks[0].shape
    principal = args.principal_point or (width * 0.5, height * 0.5)
    min_views = max(1, int(math.ceil(len(image_paths) * args.min_view_ratio)))

    candidates: list[dict[str, Any]] = []
    for direction in (1, -1):
        poses = [
            make_pose(
                direction * 2.0 * math.pi * index / len(image_paths),
                args.radius,
                args.elevation,
                args.target_z,
            )
            for index in range(len(image_paths))
        ]
        points, normals, hull_stats = visual_hull(
            masks,
            poses,
            args.focal,
            principal,
            args.grid_resolution,
            min_views,
            args.radius,
        )
        candidates.append(
            {
                "direction": direction,
                "poses": poses,
                "points": points,
                "normals": normals,
                "hull": hull_stats,
            }
        )

    selected = max(candidates, key=lambda item: item["hull"]["occupied_voxels"])
    points = selected["points"]
    normals = selected["normals"]
    if points.shape[0] > args.max_points:
        rng = np.random.default_rng(args.seed)
        indices = np.sort(rng.choice(points.shape[0], args.max_points, replace=False))
        points = points[indices]
        normals = normals[indices]
    colors = sample_colors(
        points,
        normals,
        images,
        masks,
        selected["poses"],
        args.focal,
        principal,
    )

    args.output.mkdir(parents=True)
    write_colmap_model(
        args.output,
        image_paths,
        selected["poses"],
        points,
        colors,
        (width, height),
        args.focal,
        principal,
    )
    manifest = {
        "schema": "fovea-turntable-prior-v1",
        "method": "uniform-circular-pose-prior-plus-mask-visual-hull",
        "pose_source": "chronological frames from one assumed uniform full revolution",
        "metric_calibration": False,
        "assumptions": [
            "fixed camera and lighting",
            "rigid subject on a centered turntable",
            "uniform angular steps covering 360 degrees",
        ],
        "images_directory": str(args.images.resolve()),
        "masks_directory": str(args.masks.resolve()),
        "frame_count": len(image_paths),
        "image_size": [width, height],
        "camera_model": "PINHOLE",
        "focal": args.focal,
        "principal_point": list(principal),
        "radius": args.radius,
        "elevation": args.elevation,
        "target_z": args.target_z,
        "selected_rotation_direction": selected["direction"],
        "direction_scores": {
            str(item["direction"]): item["hull"]["occupied_voxels"]
            for item in candidates
        },
        "visual_hull": selected["hull"],
        "point_count": int(points.shape[0]),
        "random_seed": args.seed,
        "files": [],
    }
    for path in sorted(args.output.glob("*.bin")):
        manifest["files"].append(
            {"name": path.name, "bytes": path.stat().st_size, "sha256": sha256(path)}
        )
    manifest_path = args.output / "turntable_prior_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    print(f"Manifest sha256={sha256(manifest_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
