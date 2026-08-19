#!/usr/bin/env python3
"""Run the official gsplat trainer behind FoveaEngine's legacy 3DGS CLI.

The Godot reconstruction backend historically called an unspecified ``train.py``
with the original 3DGS arguments (``-s``, ``-m`` and ``--iterations``).  This
bridge keeps that stable interface while selecting a real gsplat/CUDA runtime,
running the official ``examples/simple_trainer.py``, and publishing both the PLY
path expected by StudioTo3D and a hash-addressed provenance manifest.

No image or geometry is synthesized by this wrapper.  The source directory must
contain source images plus a COLMAP sparse model.  If COLMAP used ``input/`` as its
image directory, the bridge creates a non-destructive hard-linked ``images/``
view because that is the layout consumed by gsplat's COLMAP parser.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any, Iterable


SCHEMA = "fovea.gsplat.training.v1"
SUPPORTED_IMAGES = {".jpg", ".jpeg", ".png", ".webp"}


def image_files(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(
        path
        for path in directory.rglob("*")
        if path.is_file() and path.suffix.lower() in SUPPORTED_IMAGES
    )


def validate_dataset(source: Path) -> tuple[Path, list[Path], Path]:
    if not source.is_dir():
        raise ValueError(f"source dataset does not exist: {source}")

    images_dir = source / "images"
    inputs_dir = source / "input"
    images = image_files(images_dir)
    selected_images_dir = images_dir
    if not images:
        images = image_files(inputs_dir)
        selected_images_dir = inputs_dir
    if len(images) < 3:
        raise ValueError(
            "gsplat requires at least three source images in images/ or input/"
        )

    sparse_dir = source / "sparse" / "0"
    if not sparse_dir.is_dir():
        sparse_dir = source / "sparse"
    if not sparse_dir.is_dir():
        raise ValueError(f"COLMAP sparse model is missing under {source / 'sparse'}")
    camera_files = list(sparse_dir.glob("cameras.*"))
    image_model_files = list(sparse_dir.glob("images.*"))
    point_files = list(sparse_dir.glob("points3D.*"))
    if not camera_files or not image_model_files or not point_files:
        raise ValueError(
            "COLMAP sparse model must contain cameras, images and points3D files"
        )
    return selected_images_dir, images, sparse_dir


def ensure_gsplat_images_view(source: Path, selected_images_dir: Path) -> str:
    target = source / "images"
    if selected_images_dir == target:
        return "existing-images-directory"
    if target.exists():
        raise RuntimeError(f"refusing to replace non-image path: {target}")

    target.mkdir(parents=False)
    method = "hardlink"
    try:
        for source_image in image_files(selected_images_dir):
            relative = source_image.relative_to(selected_images_dir)
            destination = target / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            try:
                os.link(source_image, destination)
            except OSError:
                method = "copy"
                shutil.copy2(source_image, destination)
    except BaseException:
        shutil.rmtree(target, ignore_errors=True)
        raise
    return f"created-{method}-view-from-input"


def executable_candidates(explicit: str | None) -> Iterable[str]:
    values = [
        explicit,
        os.environ.get("FOVEA_GSPLAT_PYTHON"),
        sys.executable,
    ]
    home = Path.home()
    if os.name == "nt":
        values.extend(
            [
                str(home / "miniconda3" / "envs" / "fovea-3dgs" / "python.exe"),
                str(home / "anaconda3" / "envs" / "fovea-3dgs" / "python.exe"),
            ]
        )
    else:
        values.extend(
            [
                str(home / "miniconda3" / "envs" / "fovea-3dgs" / "bin" / "python"),
                str(home / "anaconda3" / "envs" / "fovea-3dgs" / "bin" / "python"),
            ]
        )
    values.append(shutil.which("python"))

    seen: set[str] = set()
    for value in values:
        if not value:
            continue
        resolved = shutil.which(value) or value
        key = os.path.normcase(os.path.abspath(resolved))
        if key in seen or not Path(resolved).is_file():
            continue
        seen.add(key)
        yield resolved


def probe_runtime(candidate: str) -> tuple[dict[str, Any] | None, str]:
    code = """
import json
from pathlib import Path
import gsplat
import torch
from file_digest import sha256
root = Path(gsplat.__file__).resolve().parent.parent
print(json.dumps({
    "gsplat_root": str(root),
    "gsplat_version": getattr(gsplat, "__version__", "unknown"),
    "trainer": str(root / "examples" / "simple_trainer.py"),
    "cuda": bool(torch.cuda.is_available()),
    "gpu": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "",
    "torch_version": torch.__version__,
}))
"""
    try:
        result = subprocess.run(
            [candidate, "-c", code],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=45,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return None, str(exc)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip().splitlines()
        return None, detail[-1] if detail else f"exit {result.returncode}"
    try:
        payload = json.loads(result.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        return None, f"invalid runtime probe: {exc}"
    trainer = Path(payload.get("trainer", ""))
    if not trainer.is_file():
        return None, f"official gsplat trainer is missing: {trainer}"
    if not payload.get("cuda", False):
        return None, "PyTorch reports CUDA unavailable"
    return payload, ""


def resolve_runtime(explicit_python: str | None) -> tuple[str, dict[str, Any]]:
    failures: list[str] = []
    for candidate in executable_candidates(explicit_python):
        payload, error = probe_runtime(candidate)
        if payload is not None:
            return candidate, payload
        failures.append(f"{candidate}: {error}")
    hint = (
        "Set FOVEA_GSPLAT_PYTHON or --trainer-python to a Python environment "
        "containing gsplat, CUDA-enabled PyTorch and the official examples."
    )
    raise RuntimeError("No usable gsplat CUDA runtime found. " + hint + "\n" + "\n".join(failures))


def read_ply_vertex_count(path: Path) -> int:
    with path.open("rb") as stream:
        for raw_line in stream:
            line = raw_line.decode("ascii", errors="strict").strip()
            if line.startswith("element vertex "):
                return int(line.rsplit(" ", 1)[1])
            if line == "end_header":
                break
    raise ValueError(f"PLY vertex count is missing: {path}")


def stream_process(command: list[str], working_directory: Path) -> int:
    process = subprocess.Popen(
        command,
        cwd=working_directory,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        bufsize=1,
    )
    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="", flush=True)
    return process.wait()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-s", "--source", required=True, type=Path)
    parser.add_argument("-m", "--model", required=True, type=Path)
    parser.add_argument("--iterations", type=int, default=30_000)
    parser.add_argument("--trainer-python", help="Python executable for gsplat/CUDA")
    parser.add_argument("--pose-opt", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--antialiased", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.source.resolve()
    model = args.model.resolve()
    if args.iterations < 1_000:
        raise ValueError("photorealistic training requires at least 1,000 iterations")
    if model != source / "output":
        raise ValueError("model directory must be <source>/output for StudioTo3D compatibility")

    selected_images_dir, images, sparse_dir = validate_dataset(source)
    python_executable, runtime = resolve_runtime(args.trainer_python)
    trainer = Path(runtime["trainer"])
    final_step = args.iterations - 1
    native_ply = model / "ply" / f"point_cloud_{final_step}.ply"
    published_ply = (
        model
        / "point_cloud"
        / f"iteration_{args.iterations}"
        / "point_cloud.ply"
    )
    manifest_path = model / "fovea_gsplat_training_manifest.json"
    if model.is_dir() and any(model.iterdir()):
        raise FileExistsError(
            f"refusing to train into a non-empty output directory: {model}"
        )
    protected_outputs = [native_ply, published_ply, manifest_path]
    existing = [path for path in protected_outputs if path.exists()]
    if existing:
        raise FileExistsError(
            "refusing to overwrite existing training artifacts: "
            + ", ".join(str(path) for path in existing)
        )

    command = [
        python_executable,
        str(trainer),
        "default",
        "--data-dir",
        str(source),
        "--data-factor",
        "1",
        "--result-dir",
        str(model),
        "--max-steps",
        str(args.iterations),
        "--eval-steps",
        str(args.iterations),
        "--save-steps",
        str(args.iterations),
        "--save-ply",
        "--ply-steps",
        str(args.iterations),
        "--disable-viewer",
        "--disable-video",
        "--scale-reg",
        "0.001",
        "--strategy.grow-grad2d",
        "0.0004",
        "--strategy.prune-scale3d",
        "0.05",
        "--strategy.reset-every",
        "100000",
    ]
    if args.pose_opt:
        command.append("--pose-opt")
    if args.antialiased:
        command.append("--antialiased")

    print(f"Fovea gsplat runtime: {python_executable}")
    print(
        "Fovea gsplat backend: "
        f"gsplat={runtime['gsplat_version']} torch={runtime['torch_version']} "
        f"gpu={runtime['gpu']}"
    )
    print(
        f"Fovea dataset: {len(images)} source images, COLMAP={sparse_dir}, "
        f"source={source}"
    )
    print("Fovea gsplat command: " + subprocess.list2cmdline(command))
    if args.dry_run:
        print("[DRY RUN] Preflight passed; no dataset or output files were changed.")
        return 0

    image_layout = ensure_gsplat_images_view(source, selected_images_dir)
    model.mkdir(parents=True, exist_ok=True)
    status = stream_process(command, trainer.parent)
    if status != 0:
        raise RuntimeError(f"official gsplat trainer failed with exit code {status}")
    if not native_ply.is_file():
        raise FileNotFoundError(f"gsplat did not produce its final PLY: {native_ply}")

    vertex_count = read_ply_vertex_count(native_ply)
    if vertex_count <= 0:
        raise ValueError(f"gsplat produced an empty PLY: {native_ply}")
    published_ply.parent.mkdir(parents=True, exist_ok=False)
    try:
        os.link(native_ply, published_ply)
        publication_method = "hardlink"
    except OSError:
        shutil.copy2(native_ply, published_ply)
        publication_method = "copy"

    artifact_hash = sha256(native_ply)
    manifest = {
        "schema": SCHEMA,
        "source": str(source),
        "source_image_directory": str(selected_images_dir),
        "source_image_count": len(images),
        "colmap_sparse_directory": str(sparse_dir),
        "image_layout": image_layout,
        "runtime": {
            "python": python_executable,
            "gsplat_root": runtime["gsplat_root"],
            "gsplat_version": runtime["gsplat_version"],
            "torch_version": runtime["torch_version"],
            "gpu": runtime["gpu"],
            "cuda": True,
        },
        "training": {
            "iterations": args.iterations,
            "pose_optimization": args.pose_opt,
            "antialiased": args.antialiased,
            "sh_degree": 3,
            "scale_regularization": 0.001,
        },
        "artifact": {
            "native_ply": str(native_ply),
            "published_ply": str(published_ply),
            "publication_method": publication_method,
            "vertex_count": vertex_count,
            "sha256": artifact_hash,
        },
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(
        f"Fovea gsplat complete: {vertex_count} splats, "
        f"sha256={artifact_hash}, output={published_ply}"
    )
    print(f"Fovea training manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"Fovea gsplat error: {exc}", file=sys.stderr)
        raise SystemExit(1)
