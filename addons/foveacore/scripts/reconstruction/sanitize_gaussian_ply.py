#!/usr/bin/env python3
"""Prepare a source-preserving gsplat binary PLY for runtime diagnostics.

This is a foreground-asset preparation step, not a reconstruction algorithm.
It preserves every PLY property and normally only removes records selected by
thresholds provided on the command line.  An explicit diagnostic option can
replace all retained scales with a fixed isotropic scale, allowing a renderer
to distinguish position/color defects from covariance defects.  The source
file is never modified and a JSON manifest records the exact input/output
hashes, removals, and transformations.

Supported input is deliberately narrow and fail-closed: binary little-endian
PLY with one vertex element and scalar float/float32 properties, matching the
uncompressed ``gsplat.exporter`` PLY output.
"""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
from typing import Any

import numpy as np
from file_digest import sha256 as _sha256


SH_C0 = 0.28209479177387814


def _parse_header(stream: Any) -> tuple[list[bytes], int, list[str]]:
    first = stream.readline()
    if first.rstrip(b"\r\n") != b"ply":
        raise ValueError("Input is not a PLY file")

    header_lines: list[bytes] = [first]
    vertex_count: int | None = None
    properties: list[str] = []
    current_element = ""
    saw_format = False

    while True:
        line = stream.readline()
        if not line:
            raise ValueError("Truncated PLY header: missing end_header")
        header_lines.append(line)
        text = line.decode("ascii").strip()

        if text == "format binary_little_endian 1.0":
            saw_format = True
        elif text.startswith("element "):
            parts = text.split()
            if len(parts) != 3:
                raise ValueError(f"Malformed element declaration: {text}")
            current_element = parts[1]
            if current_element != "vertex":
                raise ValueError(
                    f"Unsupported PLY element '{current_element}'; expected vertices only"
                )
            if vertex_count is not None:
                raise ValueError("PLY declares the vertex element more than once")
            vertex_count = int(parts[2])
        elif text.startswith("property "):
            parts = text.split()
            if current_element != "vertex" or len(parts) != 3:
                raise ValueError(f"Unsupported PLY property declaration: {text}")
            if parts[1] not in {"float", "float32"}:
                raise ValueError(
                    f"Unsupported property type '{parts[1]}' for '{parts[2]}'"
                )
            properties.append(parts[2])
        elif text == "end_header":
            break

    if not saw_format:
        raise ValueError("Only binary_little_endian 1.0 PLY is supported")
    if vertex_count is None or vertex_count <= 0:
        raise ValueError("PLY has no positive vertex count")
    if not properties:
        raise ValueError("PLY has no vertex properties")
    if len(properties) != len(set(properties)):
        raise ValueError("PLY contains duplicate property names")
    return header_lines, vertex_count, properties


def _replace_vertex_count(header_lines: list[bytes], vertex_count: int) -> bytes:
    rewritten: list[bytes] = []
    replaced = False
    for line in header_lines:
        text = line.decode("ascii").strip()
        if text.startswith("element vertex "):
            newline = b"\r\n" if line.endswith(b"\r\n") else b"\n"
            rewritten.append(f"element vertex {vertex_count}".encode("ascii") + newline)
            replaced = True
        else:
            rewritten.append(line)
    if not replaced:
        raise ValueError("Internal error: vertex count declaration was not found")
    return b"".join(rewritten)


def _require_properties(index: dict[str, int], names: list[str]) -> None:
    missing = [name for name in names if name not in index]
    if missing:
        raise ValueError("Missing required Gaussian properties: " + ", ".join(missing))


def sanitize(args: argparse.Namespace) -> dict[str, Any]:
    source = args.input.resolve()
    destination = args.output.resolve()
    manifest_path = args.manifest.resolve()

    if source == destination:
        raise ValueError("Output must differ from input; source PLY is immutable")
    if not source.is_file():
        raise FileNotFoundError(f"Input PLY does not exist: {source}")
    if destination.exists() and not args.overwrite:
        raise FileExistsError(f"Output already exists (use --overwrite): {destination}")
    if manifest_path.exists() and not args.overwrite:
        raise FileExistsError(
            f"Manifest already exists (use --overwrite): {manifest_path}"
        )

    with source.open("rb") as stream:
        header_lines, vertex_count, properties = _parse_header(stream)
        payload = stream.read()

    expected_bytes = vertex_count * len(properties) * 4
    if len(payload) != expected_bytes:
        raise ValueError(
            f"Unexpected PLY payload size: got {len(payload)}, expected {expected_bytes}"
        )

    records = np.frombuffer(payload, dtype="<f4").reshape(vertex_count, len(properties))
    if not np.isfinite(records).all():
        raise ValueError("PLY contains NaN or infinite values")

    index = {name: offset for offset, name in enumerate(properties)}
    _require_properties(
        index,
        [
            "x",
            "y",
            "z",
            "f_dc_0",
            "f_dc_1",
            "f_dc_2",
            "opacity",
            "scale_0",
            "scale_1",
            "scale_2",
            "rot_0",
            "rot_1",
            "rot_2",
            "rot_3",
        ],
    )

    positions = records[:, [index["x"], index["y"], index["z"]]]
    bounds_min = positions.min(axis=0)
    bounds_max = positions.max(axis=0)
    bounds_diagonal = float(np.linalg.norm(bounds_max - bounds_min))
    if not math.isfinite(bounds_diagonal) or bounds_diagonal <= 0.0:
        raise ValueError("PLY position bounds have no usable extent")

    log_scales = records[
        :, [index["scale_0"], index["scale_1"], index["scale_2"]]
    ]
    linear_scales = np.exp(log_scales)
    max_linear_scale = linear_scales.max(axis=1)

    sh0 = records[:, [index["f_dc_0"], index["f_dc_1"], index["f_dc_2"]]]
    rgb = np.clip(0.5 + SH_C0 * sh0, 0.0, 1.0)
    luma = rgb @ np.asarray([0.2126, 0.7152, 0.0722], dtype=np.float32)

    hard_scale_limit = bounds_diagonal * args.max_scale_ratio
    hard_scale_outlier = max_linear_scale > hard_scale_limit

    background_outlier = np.zeros(vertex_count, dtype=bool)
    background_scale_limit: float | None = None
    if args.background_luma_max is not None:
        background_scale_limit = bounds_diagonal * args.background_min_scale_ratio
        background_outlier = (luma <= args.background_luma_max) & (
            max_linear_scale > background_scale_limit
        )

    remove = hard_scale_outlier | background_outlier
    keep = ~remove
    kept_records = np.array(records[keep], dtype="<f4", copy=True, order="C")
    if kept_records.shape[0] == 0:
        raise ValueError("All splats would be removed; refusing to write an empty asset")

    retained_linear_scales = np.array(linear_scales[keep], copy=True)
    max_anisotropy_ratio_before = float(
        np.max(
            retained_linear_scales.max(axis=1)
            / np.maximum(retained_linear_scales.min(axis=1), np.finfo(np.float32).tiny)
        )
    )
    scale_capped_splats = 0
    capped_linear_scale: float | None = None
    if args.cap_linear_scale_ratio is not None:
        capped_linear_scale = bounds_diagonal * args.cap_linear_scale_ratio
        capped_scales = np.minimum(retained_linear_scales, capped_linear_scale)
        scale_capped_splats = int(
            np.any(capped_scales < retained_linear_scales, axis=1).sum()
        )
        retained_linear_scales = capped_scales

    anisotropy_clamped_splats = 0
    if args.max_anisotropy_ratio is not None:
        min_allowed_scale = (
            retained_linear_scales.max(axis=1, keepdims=True)
            / args.max_anisotropy_ratio
        )
        clamped_linear_scales = np.maximum(retained_linear_scales, min_allowed_scale)
        anisotropy_clamped_splats = int(
            np.any(clamped_linear_scales > retained_linear_scales, axis=1).sum()
        )
        retained_linear_scales = clamped_linear_scales
        kept_records[:, index["scale_0"]] = np.log(retained_linear_scales[:, 0])
        kept_records[:, index["scale_1"]] = np.log(retained_linear_scales[:, 1])
        kept_records[:, index["scale_2"]] = np.log(retained_linear_scales[:, 2])

    forced_isotropic_scale: float | None = None
    if args.force_isotropic_scale_ratio is not None:
        forced_isotropic_scale = bounds_diagonal * args.force_isotropic_scale_ratio
        forced_log_scale = math.log(forced_isotropic_scale)
        kept_records[:, index["scale_0"]] = forced_log_scale
        kept_records[:, index["scale_1"]] = forced_log_scale
        kept_records[:, index["scale_2"]] = forced_log_scale
        retained_linear_scales.fill(forced_isotropic_scale)

    retained_anisotropy = retained_linear_scales.max(axis=1) / np.maximum(
        retained_linear_scales.min(axis=1), np.finfo(np.float32).tiny
    )

    destination.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    output_bytes = _replace_vertex_count(header_lines, kept_records.shape[0]) + kept_records.tobytes()
    temporary_output = destination.with_name(destination.name + ".tmp")
    temporary_output.write_bytes(output_bytes)
    os.replace(temporary_output, destination)

    manifest: dict[str, Any] = {
        "schema": "fovea.gaussian_ply_sanitize.v2",
        "source": str(source),
        "source_sha256": _sha256(source),
        "output": str(destination),
        "output_sha256": _sha256(destination),
        "property_count": len(properties),
        "input_splats": vertex_count,
        "output_splats": int(kept_records.shape[0]),
        "removed_splats": int(remove.sum()),
        "removal_reasons": {
            "hard_scale_outliers": int(hard_scale_outlier.sum()),
            "background_outliers": int(background_outlier.sum()),
            "overlap": int((hard_scale_outlier & background_outlier).sum()),
        },
        "bounds": {
            "min": bounds_min.astype(float).tolist(),
            "max": bounds_max.astype(float).tolist(),
            "diagonal": bounds_diagonal,
        },
        "thresholds": {
            "max_scale_ratio": args.max_scale_ratio,
            "max_linear_scale": hard_scale_limit,
            "background_luma_max": args.background_luma_max,
            "background_min_scale_ratio": (
                args.background_min_scale_ratio
                if args.background_luma_max is not None
                else None
            ),
            "background_min_linear_scale": background_scale_limit,
        },
        "transformations": {
            "cap_linear_scale_ratio": args.cap_linear_scale_ratio,
            "capped_linear_scale": capped_linear_scale,
            "scale_capped_splats": scale_capped_splats,
            "max_anisotropy_ratio": args.max_anisotropy_ratio,
            "anisotropy_clamped_splats": anisotropy_clamped_splats,
            "force_isotropic_scale_ratio": args.force_isotropic_scale_ratio,
            "forced_isotropic_linear_scale": forced_isotropic_scale,
        },
        "observed": {
            "max_linear_scale_before": float(max_linear_scale.max()),
            "max_linear_scale_after": float(retained_linear_scales.max()),
            "max_anisotropy_ratio_before": max_anisotropy_ratio_before,
            "max_anisotropy_ratio_after": float(retained_anisotropy.max()),
            "min_luma": float(luma.min()),
            "max_luma": float(luma.max()),
        },
    }
    temporary_manifest = manifest_path.with_name(manifest_path.name + ".tmp")
    temporary_manifest.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    os.replace(temporary_manifest, manifest_path)
    return manifest


def _positive_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed) or parsed <= 0.0:
        raise argparse.ArgumentTypeError("value must be finite and greater than zero")
    return parsed


def _unit_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed) or not 0.0 <= parsed <= 1.0:
        raise argparse.ArgumentTypeError("value must be finite and within [0, 1]")
    return parsed


def _ratio_at_least_one(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed) or parsed < 1.0:
        raise argparse.ArgumentTypeError("value must be finite and at least one")
    return parsed


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Source gsplat PLY")
    parser.add_argument("--output", type=Path, required=True, help="Sanitized PLY")
    parser.add_argument(
        "--manifest",
        type=Path,
        required=True,
        help="JSON provenance manifest to write",
    )
    parser.add_argument(
        "--max-scale-ratio",
        type=_positive_float,
        default=0.05,
        help="Remove a splat when its largest linear scale exceeds this fraction of the position-bounds diagonal (default: 0.05)",
    )
    parser.add_argument(
        "--background-luma-max",
        type=_unit_float,
        default=None,
        help="Also remove near-background splats at or below this degree-0 SH luma",
    )
    parser.add_argument(
        "--background-min-scale-ratio",
        type=_positive_float,
        default=0.015,
        help="Minimum scale ratio for the optional background rule (default: 0.015)",
    )
    parser.add_argument(
        "--cap-linear-scale-ratio",
        type=_positive_float,
        default=None,
        help=(
            "Diagnostic/runtime compatibility transform: cap retained Gaussian "
            "axes to this fraction of the position-bounds diagonal"
        ),
    )
    transformation_group = parser.add_mutually_exclusive_group()
    transformation_group.add_argument(
        "--max-anisotropy-ratio",
        type=_ratio_at_least_one,
        default=None,
        help=(
            "Raise only undersized Gaussian axes so no retained splat exceeds "
            "this major/minor scale ratio"
        ),
    )
    transformation_group.add_argument(
        "--force-isotropic-scale-ratio",
        type=_positive_float,
        default=None,
        help=(
            "Diagnostic only: replace every retained Gaussian scale with this "
            "fraction of the position-bounds diagonal"
        ),
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace an existing output and manifest",
    )
    return parser


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()
    try:
        manifest = sanitize(args)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
