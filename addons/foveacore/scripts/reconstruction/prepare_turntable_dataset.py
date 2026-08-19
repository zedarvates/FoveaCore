#!/usr/bin/env python3
"""Prepare a masked, single-camera COLMAP dataset from turntable frames.

The StudioTo3D classical path assumes that the scene is static while the camera
moves. A turntable capture is equivalent only after the static background is
removed. This tool therefore creates per-frame foreground masks and neutral
background images; it never manufactures geometry or camera poses.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image
from rembg import new_session, remove
from file_digest import sha256


SUPPORTED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


def parse_crop(value: str) -> tuple[int, int, int, int]:
    parts = [int(part.strip()) for part in value.split(",")]
    if len(parts) != 4 or parts[2] <= 0 or parts[3] <= 0:
        raise argparse.ArgumentTypeError("crop must be x,y,width,height")
    return parts[0], parts[1], parts[2], parts[3]


def retain_subject(alpha: np.ndarray, threshold: int) -> np.ndarray:
    binary = np.where(alpha >= threshold, 255, 0).astype(np.uint8)
    binary = cv2.morphologyEx(
        binary,
        cv2.MORPH_CLOSE,
        cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)),
    )
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(binary)
    if count <= 1:
        raise RuntimeError("background removal produced no foreground component")

    height, width = binary.shape
    image_area = float(width * height)
    center = np.array([width * 0.5, height * 0.5], dtype=np.float32)
    diagonal = max(float(np.linalg.norm(center)), 1.0)
    best_label = -1
    best_score = -1.0
    for label in range(1, count):
        area = float(stats[label, cv2.CC_STAT_AREA])
        if area < image_area * 0.002:
            continue
        distance = float(np.linalg.norm(centroids[label] - center)) / diagonal
        score = area / (1.0 + 3.0 * distance)
        if score > best_score:
            best_score = score
            best_label = label
    if best_label < 0:
        raise RuntimeError("background removal produced only tiny components")

    subject = np.where(labels == best_label, 255, 0).astype(np.uint8)
    subject = cv2.morphologyEx(
        subject,
        cv2.MORPH_CLOSE,
        cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)),
    )
    return cv2.dilate(subject, np.ones((3, 3), np.uint8), iterations=1)


def prepare_frame(
    source_path: Path,
    image_path: Path,
    mask_path: Path,
    rgba_path: Path,
    session: Any,
    crop: tuple[int, int, int, int] | None,
    output_size: int,
    threshold: int,
) -> dict[str, Any]:
    source = Image.open(source_path).convert("RGB")
    source_size = source.size
    if crop is not None:
        x, y, width, height = crop
        if x < 0 or y < 0 or x + width > source.width or y + height > source.height:
            raise ValueError(f"crop {crop} exceeds {source_path.name} size {source.size}")
        source = source.crop((x, y, x + width, y + height))

    foreground = remove(source, session=session).convert("RGBA")
    rgba = np.asarray(foreground).copy()
    subject_mask = retain_subject(rgba[:, :, 3], threshold)
    rgba[:, :, 3] = np.where(subject_mask > 0, rgba[:, :, 3], 0)
    foreground = Image.fromarray(rgba, mode="RGBA")

    if output_size > 0:
        foreground = foreground.resize(
            (output_size, output_size), Image.Resampling.LANCZOS
        )
        subject_mask = cv2.resize(
            subject_mask,
            (output_size, output_size),
            interpolation=cv2.INTER_NEAREST,
        )

    neutral = Image.new("RGB", foreground.size, (0, 0, 0))
    neutral.paste(foreground.convert("RGB"), mask=foreground.getchannel("A"))
    neutral.save(image_path, format="PNG", optimize=True)
    Image.fromarray(subject_mask, mode="L").save(mask_path, format="PNG", optimize=True)
    foreground.save(rgba_path, format="PNG", optimize=True)

    ys, xs = np.where(subject_mask > 0)
    if xs.size == 0:
        raise RuntimeError(f"empty subject mask for {source_path.name}")
    coverage = float(xs.size) / float(subject_mask.size)
    if coverage < 0.03 or coverage > 0.75:
        raise RuntimeError(
            f"implausible mask coverage {coverage:.3f} for {source_path.name}"
        )
    return {
        "source": source_path.name,
        "source_size": list(source_size),
        "source_sha256": sha256(source_path),
        "image": image_path.name,
        "image_sha256": sha256(image_path),
        "mask": mask_path.name,
        "mask_sha256": sha256(mask_path),
        "mask_coverage": coverage,
        "mask_bbox": [
            int(xs.min()),
            int(ys.min()),
            int(xs.max() + 1),
            int(ys.max() + 1),
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Input frame folder")
    parser.add_argument("--output", required=True, type=Path, help="New dataset folder")
    parser.add_argument("--crop", type=parse_crop, help="Fixed x,y,width,height crop")
    parser.add_argument("--output-size", type=int, default=512, help="Square output size")
    parser.add_argument("--threshold", type=int, default=24, help="U2Net alpha threshold")
    parser.add_argument("--limit", type=int, default=0, help="Optional frame limit for a probe")
    args = parser.parse_args()

    if not args.input.is_dir():
        parser.error(f"input directory does not exist: {args.input}")
    if args.output.exists():
        parser.error(f"output already exists (refusing to overwrite): {args.output}")
    if args.output_size < 128 or args.output_size > 4096:
        parser.error("output-size must be between 128 and 4096")
    if args.threshold < 1 or args.threshold > 254:
        parser.error("threshold must be between 1 and 254")

    sources = sorted(
        path
        for path in args.input.iterdir()
        if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS
    )
    if args.limit > 0:
        sources = sources[: args.limit]
    if len(sources) < 1:
        parser.error("no supported input frames found")

    images_dir = args.output / "images"
    masks_dir = args.output / "masks"
    rgba_dir = args.output / "rgba"
    images_dir.mkdir(parents=True)
    masks_dir.mkdir()
    rgba_dir.mkdir()

    session = new_session("u2net", providers=["CPUExecutionProvider"])
    records: list[dict[str, Any]] = []
    for index, source_path in enumerate(sources):
        output_name = f"frame_{index:04d}.png"
        # COLMAP first looks for <image name>.png under ImageReader.mask_path.
        mask_name = output_name + ".png"
        record = prepare_frame(
            source_path,
            images_dir / output_name,
            masks_dir / mask_name,
            rgba_dir / output_name,
            session,
            args.crop,
            args.output_size,
            args.threshold,
        )
        records.append(record)
        print(
            f"[{index + 1:03d}/{len(sources):03d}] {source_path.name} "
            f"coverage={record['mask_coverage']:.3f} bbox={record['mask_bbox']}",
            flush=True,
        )

    manifest = {
        "schema": "fovea-turntable-dataset-v1",
        "method": "u2net-per-frame-background-removal",
        "geometry_generated": False,
        "camera_poses_generated": False,
        "input_directory": str(args.input.resolve()),
        "crop": list(args.crop) if args.crop is not None else None,
        "output_size": args.output_size,
        "threshold": args.threshold,
        "frame_count": len(records),
        "frames": records,
    }
    manifest_path = args.output / "preprocess_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Prepared {len(records)} real frames in {args.output}")
    print(f"Manifest: {manifest_path} sha256={sha256(manifest_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
