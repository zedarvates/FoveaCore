#!/usr/bin/env python3
"""Bake a NumPy displacement field into a FoveaNeuralOffsetField resource.

The input shape is ``(Nx, Ny, Nz, 3)``. The generated resource contains one
static animation frame and uses the same x-fastest cell order as
``FoveaNeuralOffsetField._cell_index``.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
from typing import Sequence

import numpy as np


SCRIPT_PATH = "res://addons/foveacore/scripts/advanced/fovea_neural_offset_field.gd"


def _format_float(value: float) -> str:
    """Return a compact, round-trip-safe float32 representation for Godot."""
    return format(float(np.float32(value)), ".9g")


def _validate_bounds(bounds: Sequence[float]) -> tuple[float, float, float, float, float, float]:
    if len(bounds) != 6:
        raise ValueError("bounds must contain min_x,min_y,min_z,max_x,max_y,max_z")

    parsed = tuple(float(value) for value in bounds)
    if not all(math.isfinite(value) for value in parsed):
        raise ValueError("bounds must contain only finite values")
    if any(parsed[axis + 3] <= parsed[axis] for axis in range(3)):
        raise ValueError("each maximum bound must be greater than its minimum")
    return parsed  # type: ignore[return-value]


def bake(
    input_path: str | Path,
    output_path: str | Path,
    resolution: int = 16,
    bounds: Sequence[float] = (-2, -2, -2, 4, 4, 4),
) -> bool:
    """Convert a cubic ``.npy`` vector field to a Godot ``.tres`` resource."""
    if resolution < 1:
        raise ValueError("resolution must be at least 1")

    data = np.load(Path(input_path), allow_pickle=False)
    expected_shape = (resolution, resolution, resolution, 3)
    if data.shape != expected_shape:
        raise ValueError(f"expected shape {expected_shape}, got {data.shape}")
    if not np.issubdtype(data.dtype, np.number):
        raise ValueError(f"expected a numeric array, got {data.dtype}")
    if not np.isfinite(data).all():
        raise ValueError("offset field must contain only finite values")

    parsed_bounds = _validate_bounds(bounds)
    # NumPy C order makes z the fastest spatial dimension. Godot's cell index
    # makes x fastest, so serialize the field in z/y/x order.
    ordered_vectors = np.transpose(data, (2, 1, 0, 3)).reshape(-1, 3).astype(np.float32)
    packed_values = ", ".join(
        _format_float(component) for vector in ordered_vectors for component in vector
    )

    resource_text = "\n".join(
        (
            '[gd_resource type="Resource" script_class="FoveaNeuralOffsetField" load_steps=2 format=3]',
            "",
            f'[ext_resource type="Script" path="{SCRIPT_PATH}" id="1"]',
            "",
            "[resource]",
            'script = ExtResource("1")',
            f"grid_dims = Vector3i({resolution}, {resolution}, {resolution})",
            "bounds_min = Vector3(%s)" % ", ".join(_format_float(v) for v in parsed_bounds[:3]),
            "bounds_max = Vector3(%s)" % ", ".join(_format_float(v) for v in parsed_bounds[3:]),
            "frame_count = 1",
            "fps = 24.0",
            f"offsets = PackedVector3Array({packed_values})",
            "",
        )
    )

    destination = Path(output_path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(resource_text, encoding="utf-8", newline="\n")
    print(
        "Baked %d vectors (%.1f KiB) -> %s"
        % (ordered_vectors.shape[0], ordered_vectors.nbytes / 1024.0, destination)
    )
    return True


def _parse_bounds(value: str) -> tuple[float, ...]:
    try:
        return tuple(float(component.strip()) for component in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("bounds must be six comma-separated numbers") from error


def main() -> None:
    parser = argparse.ArgumentParser(description="Bake a FoveaEngine neural offset field")
    parser.add_argument("--input", required=True, help="Input .npy file (Nx x Ny x Nz x 3)")
    parser.add_argument("--output", default="offset_field.tres", help="Output .tres path")
    parser.add_argument("--resolution", type=int, default=16, help="Cubic grid resolution")
    parser.add_argument(
        "--bounds",
        type=_parse_bounds,
        default=(-2.0, -2.0, -2.0, 4.0, 4.0, 4.0),
        help="min_x,min_y,min_z,max_x,max_y,max_z",
    )
    arguments = parser.parse_args()

    try:
        bake(arguments.input, arguments.output, arguments.resolution, arguments.bounds)
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
