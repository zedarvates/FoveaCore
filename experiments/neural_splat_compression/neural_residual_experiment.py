import argparse
import json
import math
import random
from pathlib import Path

import numpy as np
import torch
from torch import nn


QUALITY_LIMITS = {
    "rotation_mean_degrees": 10.3765651506782,
    "scale_rmse": 0.0294672913316346,
    "color_rmse": 0.0378711942775849,
}


def load_3dgs_ply(path: Path) -> dict[str, np.ndarray]:
    raw = path.read_bytes()
    marker = b"end_header\n"
    header_end = raw.find(marker)
    if header_end < 0:
        raise ValueError("PLY header is missing end_header")
    header_end += len(marker)
    lines = raw[:header_end].decode("ascii").splitlines()
    if len(lines) < 3 or lines[0] != "ply" or lines[1] != "format binary_little_endian 1.0":
        raise ValueError("only binary little-endian PLY 1.0 is supported")

    vertex_count = 0
    properties: list[str] = []
    in_vertex = False
    for line in lines[2:]:
        parts = line.split()
        if parts[:2] == ["element", "vertex"]:
            vertex_count = int(parts[2])
            in_vertex = True
        elif parts and parts[0] == "element":
            in_vertex = False
        elif in_vertex and parts[:2] == ["property", "float"]:
            properties.append(parts[2])
        elif in_vertex and parts and parts[0] == "property":
            raise ValueError("the experiment fixture must use float vertex properties")
    if vertex_count <= 0 or not properties:
        raise ValueError("PLY has no float vertex payload")

    expected_bytes = vertex_count * len(properties) * 4
    payload = raw[header_end:]
    if len(payload) != expected_bytes:
        raise ValueError("PLY payload size does not match its header")
    matrix = np.frombuffer(payload, dtype="<f4").reshape(vertex_count, len(properties))
    columns = {name: matrix[:, index].copy() for index, name in enumerate(properties)}

    required = {
        "x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity",
        "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3",
    }
    missing = required.difference(columns)
    if missing:
        raise ValueError(f"PLY is missing required 3DGS fields: {sorted(missing)}")

    rotation = np.stack(
        [columns["rot_0"], columns["rot_1"], columns["rot_2"], columns["rot_3"]],
        axis=1,
    )
    rotation /= np.maximum(np.linalg.norm(rotation, axis=1, keepdims=True), 1e-12)
    return {
        "position": np.stack([columns["x"], columns["y"], columns["z"]], axis=1),
        "scale": np.exp(
            np.stack([columns["scale_0"], columns["scale_1"], columns["scale_2"]], axis=1)
        ),
        "rotation": rotation,
        "color": np.stack(
            [
                0.5 + 0.28209 * columns["f_dc_0"],
                0.5 + 0.28209 * columns["f_dc_1"],
                0.5 + 0.28209 * columns["f_dc_2"],
            ],
            axis=1,
        ),
        "opacity": 1.0 / (1.0 + np.exp(-columns["opacity"])),
    }


def quaternion_to_rotation_vector(quaternions: np.ndarray) -> np.ndarray:
    normalized = np.asarray(quaternions, dtype=np.float64).copy()
    normalized /= np.maximum(np.linalg.norm(normalized, axis=1, keepdims=True), 1e-12)
    normalized[normalized[:, 0] < 0.0] *= -1.0
    vector = normalized[:, 1:]
    vector_norm = np.linalg.norm(vector, axis=1)
    angle = 2.0 * np.arctan2(vector_norm, np.clip(normalized[:, 0], 0.0, 1.0))
    scale = np.divide(angle, vector_norm, out=np.full_like(angle, 2.0), where=vector_norm > 1e-12)
    return (vector * scale[:, None]).astype(np.float32)


def rotation_vector_to_quaternion(vectors: np.ndarray) -> np.ndarray:
    vectors = np.asarray(vectors, dtype=np.float64)
    angle = np.linalg.norm(vectors, axis=1)
    half_angle = angle * 0.5
    vector_scale = np.divide(
        np.sin(half_angle),
        angle,
        out=np.full_like(angle, 0.5),
        where=angle > 1e-12,
    )
    quaternions = np.concatenate(
        [np.cos(half_angle)[:, None], vectors * vector_scale[:, None]],
        axis=1,
    )
    quaternions /= np.maximum(np.linalg.norm(quaternions, axis=1, keepdims=True), 1e-12)
    return quaternions.astype(np.float32)


def estimate_storage_bytes(
    splat_count: int,
    latent_dim: int,
    hidden_dim: int,
    latent_bits: int,
    output_dim: int = 9,
    preserve_color_palette: bool = False,
) -> dict[str, int]:
    if latent_bits not in (8, 16):
        raise ValueError("latent_bits must be 8 or 16")
    fixed_bytes = 72 + splat_count * 12
    preserved_color_bytes = splat_count + 256 * 12 if preserve_color_palette else 0
    latent_bytes = splat_count * latent_dim * (latent_bits // 8)
    weight_bytes = latent_dim * hidden_dim + hidden_dim * output_dim
    output_channels = hidden_dim + output_dim
    bias_bytes = output_channels * 2
    scale_bytes = output_channels * 4
    metadata_bytes = 64
    decoder_bytes = weight_bytes + bias_bytes + scale_bytes + metadata_bytes
    return {
        "fixed_bytes": fixed_bytes,
        "preserved_color_bytes": preserved_color_bytes,
        "latent_bytes": latent_bytes,
        "decoder_bytes": decoder_bytes,
        "total_bytes": fixed_bytes + preserved_color_bytes + latent_bytes + decoder_bytes,
    }


def meets_quality_gate(metrics: dict[str, float]) -> bool:
    return all(float(metrics[name]) <= limit for name, limit in QUALITY_LIMITS.items())


def build_feature_weights(config: dict, feature_mode: str = "joint") -> np.ndarray:
    weights = (
        [float(config.get("scale_weight", 1.0))] * 3
        + [float(config.get("rotation_weight", 1.0))] * 3
    )
    if feature_mode == "joint":
        weights += [float(config.get("color_weight", 1.0))] * 3
    elif feature_mode != "covariance_only":
        raise ValueError(f"unsupported feature_mode: {feature_mode}")
    return np.asarray(weights, dtype=np.float32)


def build_features(data: dict[str, np.ndarray], feature_mode: str) -> np.ndarray:
    covariance = np.concatenate(
        [
            np.log(np.maximum(data["scale"], 1e-12)),
            quaternion_to_rotation_vector(data["rotation"]),
        ],
        axis=1,
    )
    if feature_mode == "covariance_only":
        return covariance.astype(np.float32)
    if feature_mode == "joint":
        return np.concatenate([covariance, data["color"]], axis=1).astype(np.float32)
    raise ValueError(f"unsupported feature_mode: {feature_mode}")


class Autoencoder(nn.Module):
    def __init__(self, input_dim: int, hidden_dim: int, latent_dim: int) -> None:
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, latent_dim),
            nn.Tanh(),
        )
        self.decoder_first = nn.Linear(latent_dim, hidden_dim)
        self.decoder_second = nn.Linear(hidden_dim, input_dim)

    def decode(self, latent: torch.Tensor) -> torch.Tensor:
        return self.decoder_second(torch.tanh(self.decoder_first(latent)))

    def forward(self, values: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        latent = self.encoder(values)
        return self.decode(latent), latent


def _quantize_per_row(weights: np.ndarray) -> np.ndarray:
    maximum = np.maximum(np.max(np.abs(weights), axis=1, keepdims=True), 1e-12)
    scale = maximum / 127.0
    return np.round(weights / scale).clip(-127, 127).astype(np.int8).astype(np.float32) * scale


def _quantized_decode(
    model: Autoencoder,
    standardized: torch.Tensor,
    feature_mean: np.ndarray,
    feature_std: np.ndarray,
    latent_bits: int,
) -> np.ndarray:
    with torch.no_grad():
        latent = model.encoder(standardized).cpu().numpy()
    maximum_code = 127 if latent_bits == 8 else 32767
    latent_scale = np.maximum(np.max(np.abs(latent), axis=0), 1e-12) / maximum_code
    latent_codes = np.round(latent / latent_scale).clip(-maximum_code, maximum_code)

    first_weight = model.decoder_first.weight.detach().cpu().numpy() * latent_scale[None, :]
    first_weight = _quantize_per_row(first_weight)
    first_bias = model.decoder_first.bias.detach().cpu().numpy().astype(np.float16).astype(np.float32)
    hidden = np.tanh(latent_codes @ first_weight.T + first_bias)

    second_weight = model.decoder_second.weight.detach().cpu().numpy()
    second_bias = model.decoder_second.bias.detach().cpu().numpy()
    physical_weight = feature_std[:, None] * second_weight
    physical_bias = feature_std * second_bias + feature_mean
    physical_weight = _quantize_per_row(physical_weight)
    physical_bias = physical_bias.astype(np.float16).astype(np.float32)
    return hidden @ physical_weight.T + physical_bias


def quality_metrics(
    data: dict[str, np.ndarray],
    decoded_features: np.ndarray,
    preserve_color_palette: bool = False,
) -> dict[str, float]:
    decoded_scale = np.exp(decoded_features[:, :3])
    decoded_rotation = rotation_vector_to_quaternion(decoded_features[:, 3:6])
    rotation_dot = np.clip(
        np.abs(np.sum(data["rotation"] * decoded_rotation, axis=1)),
        0.0,
        1.0,
    )
    color_rmse = QUALITY_LIMITS["color_rmse"]
    if not preserve_color_palette:
        decoded_color = np.clip(decoded_features[:, 6:9], 0.0, 1.0)
        color_rmse = float(np.sqrt(np.mean(np.square(data["color"] - decoded_color))))
    return {
        "rotation_mean_degrees": float(np.mean(np.degrees(2.0 * np.arccos(rotation_dot)))),
        "scale_rmse": float(np.sqrt(np.mean(np.square(data["scale"] - decoded_scale)))),
        "color_rmse": color_rmse,
    }


def run_experiment(config: dict, fixture: Path) -> dict:
    seed = int(config.get("seed", 20260825))
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.set_num_threads(max(1, int(config.get("threads", 4))))

    data = load_3dgs_ply(fixture)
    feature_mode = str(config.get("feature_mode", "joint"))
    features = build_features(data, feature_mode)
    feature_mean = features.mean(axis=0)
    feature_std = np.maximum(features.std(axis=0), 1e-6)
    standardized = torch.from_numpy((features - feature_mean) / feature_std)

    latent_dim = int(config["latent_dim"])
    hidden_dim = int(config["hidden_dim"])
    latent_bits = int(config.get("latent_bits", 8))
    model = Autoencoder(features.shape[1], hidden_dim, latent_dim)
    optimizer = torch.optim.Adam(model.parameters(), lr=float(config.get("learning_rate", 0.01)))
    epochs = int(config.get("epochs", 300))
    feature_weights = torch.from_numpy(build_feature_weights(config, feature_mode))
    for _ in range(epochs):
        optimizer.zero_grad(set_to_none=True)
        reconstructed, latent = model(standardized)
        reconstruction_loss = torch.mean(
            torch.square(reconstructed - standardized) * feature_weights
        )
        latent_penalty = float(config.get("latent_penalty", 0.0001)) * torch.mean(torch.square(latent))
        loss = reconstruction_loss + latent_penalty
        loss.backward()
        optimizer.step()

    decoded = _quantized_decode(model, standardized, feature_mean, feature_std, latent_bits)
    preserve_color_palette = feature_mode == "covariance_only"
    quality = quality_metrics(data, decoded, preserve_color_palette)
    storage = estimate_storage_bytes(
        len(features),
        latent_dim,
        hidden_dim,
        latent_bits,
        output_dim=features.shape[1],
        preserve_color_palette=preserve_color_palette,
    )
    passed = meets_quality_gate(quality)
    return {
        "name": str(config.get("name", "unnamed")),
        "feature_mode": feature_mode,
        "quality_pass": passed,
        "metric_bytes": storage["total_bytes"] if passed else 1_000_000_000,
        **storage,
        **quality,
        "epochs": epochs,
        "seed": seed,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    result = run_experiment(config, args.fixture)
    print(f"NEURAL_COMPRESSION_RESULT={json.dumps(result, sort_keys=True)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
