import argparse
import json
import math
import time
from pathlib import Path

import numpy as np

import neural_residual_experiment as compression


def _normalize_quaternions(quaternions: np.ndarray) -> np.ndarray:
    values = np.asarray(quaternions, dtype=np.float64)
    return values / np.maximum(np.linalg.norm(values, axis=-1, keepdims=True), 1e-12)


def _quaternion_multiply(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    left = np.asarray(left, dtype=np.float64)
    right = np.asarray(right, dtype=np.float64)
    lw, lx, ly, lz = np.moveaxis(left, -1, 0)
    rw, rx, ry, rz = np.moveaxis(right, -1, 0)
    result = np.stack(
        [
            lw * rw - lx * rx - ly * ry - lz * rz,
            lw * rx + lx * rw + ly * rz - lz * ry,
            lw * ry - lx * rz + ly * rw + lz * rx,
            lw * rz + lx * ry - ly * rx + lz * rw,
        ],
        axis=-1,
    )
    return _normalize_quaternions(result).astype(np.float32)


def _quaternion_matrix(rotation: np.ndarray) -> np.ndarray:
    w, x, y, z = _normalize_quaternions(np.asarray(rotation).reshape(1, 4))[0]
    return np.asarray(
        [
            [1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w), 2.0 * (x * z + y * w)],
            [2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w)],
            [2.0 * (x * z - y * w), 2.0 * (y * z + x * w), 1.0 - 2.0 * (x * x + y * y)],
        ],
        dtype=np.float32,
    )


def apply_rigid_transform(
    positions: np.ndarray,
    rotations: np.ndarray,
    scales: np.ndarray,
    *,
    translation: np.ndarray,
    rotation: np.ndarray,
    uniform_scale: float,
) -> dict[str, np.ndarray]:
    positions = np.asarray(positions, dtype=np.float32)
    rotations = _normalize_quaternions(rotations).astype(np.float32)
    scales = np.asarray(scales, dtype=np.float32)
    translation = np.asarray(translation, dtype=np.float32)
    object_rotation = _normalize_quaternions(np.asarray(rotation).reshape(1, 4))[0].astype(np.float32)
    if positions.ndim != 2 or positions.shape[1] != 3:
        raise ValueError("positions must have shape (N, 3)")
    if rotations.shape != (positions.shape[0], 4) or scales.shape != positions.shape:
        raise ValueError("rotation or scale count does not match positions")
    if translation.shape != (3,) or not np.isfinite(uniform_scale) or uniform_scale <= 0.0:
        raise ValueError("object transform is invalid")
    matrix = _quaternion_matrix(object_rotation)
    expanded_rotation = np.broadcast_to(object_rotation, rotations.shape)
    return {
        "position": (positions @ matrix.T) * uniform_scale + translation,
        "rotation": _quaternion_multiply(expanded_rotation, rotations),
        "scale": scales * uniform_scale,
    }


def _loop_pose(frame: int, frames: int) -> tuple[np.ndarray, np.ndarray, float]:
    phase = 2.0 * math.pi * float(frame) / float(frames - 1)
    translation = np.asarray(
        [0.5 * math.sin(phase), 0.25 * math.sin(phase * 2.0), 0.5 * (math.cos(phase) - 1.0)],
        dtype=np.float32,
    )
    rotation = np.asarray(
        [math.cos(phase * 0.5), 0.0, math.sin(phase * 0.5), 0.0],
        dtype=np.float32,
    )
    uniform_scale = 1.0 + 0.1 * math.sin(phase)
    return translation, rotation, uniform_scale


def run_rigid_motion_benchmark(
    artifact: bytes,
    positions: np.ndarray,
    *,
    frames: int,
    warmup: int,
) -> dict[str, float | int | bool]:
    if frames < 2 or warmup < 0:
        raise ValueError("frames must be at least two and warmup must be non-negative")
    positions = np.asarray(positions, dtype=np.float32)
    decode_start = time.perf_counter_ns()
    decoded_covariance = compression.decode_quantized_artifact(artifact)
    latent_decode_ms = (time.perf_counter_ns() - decode_start) / 1_000_000.0
    if decoded_covariance.shape != (positions.shape[0], 6):
        raise ValueError("artifact covariance count does not match positions")
    local_scales = np.exp(decoded_covariance[:, :3])
    local_rotations = compression.rotation_vector_to_quaternion(decoded_covariance[:, 3:6])

    warmup_pose = _loop_pose(0, frames)
    for _ in range(warmup):
        apply_rigid_transform(
            positions,
            local_rotations,
            local_scales,
            translation=warmup_pose[0],
            rotation=warmup_pose[1],
            uniform_scale=warmup_pose[2],
        )

    timings_ms: list[float] = []
    first_state: dict[str, np.ndarray] | None = None
    last_state: dict[str, np.ndarray] | None = None
    all_finite = True
    for frame in range(frames):
        translation, rotation, uniform_scale = _loop_pose(frame, frames)
        start_ns = time.perf_counter_ns()
        state = apply_rigid_transform(
            positions,
            local_rotations,
            local_scales,
            translation=translation,
            rotation=rotation,
            uniform_scale=uniform_scale,
        )
        timings_ms.append((time.perf_counter_ns() - start_ns) / 1_000_000.0)
        all_finite = all_finite and all(np.isfinite(values).all() for values in state.values())
        if frame == 0:
            first_state = {name: values.copy() for name, values in state.items()}
        if frame == frames - 1:
            last_state = state

    assert first_state is not None and last_state is not None
    position_rmse = float(
        np.sqrt(np.mean(np.square(first_state["position"] - last_state["position"])))
    )
    scale_rmse = float(np.sqrt(np.mean(np.square(first_state["scale"] - last_state["scale"]))))
    rotation_dot = np.clip(
        np.abs(np.sum(first_state["rotation"] * last_state["rotation"], axis=1)),
        0.0,
        1.0,
    )
    rotation_degrees = float(np.mean(np.degrees(2.0 * np.arccos(rotation_dot))))
    motion_pass = (
        all_finite
        and position_rmse <= 1e-6
        and rotation_degrees <= 0.01
        and scale_rmse <= 1e-6
    )
    return {
        "splats": int(positions.shape[0]),
        "frames": frames,
        "latent_decode_count": 1,
        "latent_decode_ms": float(latent_decode_ms),
        "per_frame_transform_bytes": 32,
        "per_frame_latent_bytes": 0,
        "total_motion_payload_bytes": frames * 32,
        "motion_frame_median_ms": float(np.median(timings_ms)),
        "motion_frame_p95_ms": float(np.percentile(timings_ms, 95)),
        "loop_closure_position_rmse": position_rmse,
        "loop_closure_rotation_degrees": rotation_degrees,
        "loop_closure_scale_rmse": scale_rmse,
        "all_finite": bool(all_finite),
        "motion_pass": bool(motion_pass),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--warmup", type=int, default=10)
    args = parser.parse_args()
    data = compression.load_3dgs_ply(args.fixture)
    report = run_rigid_motion_benchmark(
        args.artifact.read_bytes(),
        data["position"],
        frames=args.frames,
        warmup=args.warmup,
    )
    print(f"RIGID_MOTION_REPORT={json.dumps(report, sort_keys=True)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
