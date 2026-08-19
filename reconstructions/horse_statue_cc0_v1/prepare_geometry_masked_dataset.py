#!/usr/bin/env python3
"""Pair MP4-extracted frames with deterministic geometry ID masks."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "addons" / "foveacore" / "scripts" / "reconstruction"))
from file_digest import sha256

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", required=True, type=Path)
    parser.add_argument("--masks", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--size", type=int, default=512)
    args = parser.parse_args()

    if args.output.exists():
        parser.error(f"output already exists (refusing to overwrite): {args.output}")
    if args.size < 128 or args.size > 4096:
        parser.error("size must be between 128 and 4096")

    frames = sorted(args.frames.glob("frame_*.png"))
    masks = sorted(args.masks.glob("frame_*.png"))
    if len(frames) != len(masks) or len(frames) < 8:
        parser.error(
            f"frame/mask cardinality mismatch: frames={len(frames)} masks={len(masks)}"
        )

    images_dir = args.output / "images"
    masks_dir = args.output / "masks"
    rgba_dir = args.output / "rgba"
    images_dir.mkdir(parents=True)
    masks_dir.mkdir()
    rgba_dir.mkdir()

    records: list[dict[str, object]] = []
    for index, (frame_path, mask_path) in enumerate(zip(frames, masks, strict=True)):
        source = Image.open(frame_path).convert("RGB")
        source_size = source.size
        source = source.resize((args.size, args.size), Image.Resampling.LANCZOS)

        mask = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            raise RuntimeError(f"failed to read geometry mask: {mask_path}")
        mask = cv2.resize(mask, (args.size, args.size), interpolation=cv2.INTER_AREA)
        mask = np.where(mask >= 24, 255, 0).astype(np.uint8)
        mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=1)

        ys, xs = np.where(mask > 0)
        if xs.size == 0:
            raise RuntimeError(f"empty geometry mask: {mask_path}")
        coverage = float(xs.size) / float(mask.size)
        if coverage < 0.03 or coverage > 0.75:
            raise RuntimeError(f"implausible geometry-mask coverage {coverage:.3f}")

        alpha = Image.fromarray(mask, mode="L")
        neutral = Image.new("RGB", source.size, (0, 0, 0))
        neutral.paste(source, mask=alpha)
        rgba = source.convert("RGBA")
        rgba.putalpha(alpha)

        output_name = f"frame_{index:04d}.png"
        image_output = images_dir / output_name
        mask_output = masks_dir / f"{output_name}.png"
        rgba_output = rgba_dir / output_name
        neutral.save(image_output, format="PNG", optimize=True)
        alpha.save(mask_output, format="PNG", optimize=True)
        rgba.save(rgba_output, format="PNG", optimize=True)

        records.append(
            {
                "index": index,
                "video_frame": frame_path.name,
                "video_frame_sha256": sha256(frame_path),
                "geometry_mask": mask_path.name,
                "geometry_mask_sha256": sha256(mask_path),
                "image": image_output.name,
                "image_sha256": sha256(image_output),
                "mask": mask_output.name,
                "mask_sha256": sha256(mask_output),
                "source_size": list(source_size),
                "output_size": [args.size, args.size],
                "mask_coverage": coverage,
                "mask_bbox": [
                    int(xs.min()),
                    int(ys.min()),
                    int(xs.max() + 1),
                    int(ys.max() + 1),
                ],
            }
        )

    manifest = {
        "schema": "fovea-synthetic-turntable-dataset-v1",
        "method": "mp4-extracted-color-plus-same-camera-geometry-id-mask",
        "source_class": "synthetic_multiview_video",
        "color_source": str(args.frames.resolve()),
        "mask_source": str(args.masks.resolve()),
        "mask_estimation_model": None,
        "geometry_id_masks": True,
        "camera_poses_generated": False,
        "frame_count": len(records),
        "frames": records,
    }
    manifest_path = args.output / "preprocess_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(
        f"GEOMETRY_MASK_DATASET_OK frames={len(records)} "
        f"manifest_sha256={sha256(manifest_path)} output={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
