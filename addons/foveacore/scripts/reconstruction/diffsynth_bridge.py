"""
Unified DiffSynth-Studio bridge for FoveaEngine.
Supports WorldMirror 2.0, Vista4D, and AnyRecon backends
via DiffSynth-Studio inference framework + Wan 2.1 video diffusion.

Usage:
    python diffsynth_bridge.py --backend worldmirror2 --input frames/ --output workspace/
    python diffsynth_bridge.py --backend vista4d --input video.mp4 --output workspace/ --task reshoot
    python diffsynth_bridge.py --backend anyrecon --input frames/ --output workspace/
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path

BACKENDS = ["worldmirror2", "vista4d", "anyrecon", "dvlt"]


def check_diffsynth() -> bool:
    try:
        import diffsynth  # noqa: F401
        return True
    except ImportError:
        return False


def main():
    parser = argparse.ArgumentParser(description="FoveaEngine DiffSynth Unified Bridge")
    parser.add_argument("--backend", required=True, choices=BACKENDS, help="Reconstruction backend")
    parser.add_argument("--input", required=True, help="Input directory (frames) or video file")
    parser.add_argument("--output", required=True, help="Output workspace directory")
    parser.add_argument("--device", default="cuda", help="Computation device")
    parser.add_argument("--target_size", type=int, default=952, help="Max inference resolution")
    parser.add_argument("--fps", type=int, default=2, help="FPS for video extraction")
    parser.add_argument("--task", default="reconstruct", help="Task mode (reconstruct/reshoot/expand)")
    parser.add_argument("--loop_steps", type=int, default=8, help="Refinement loop steps K (for DVLT compute knob)")
    parser.add_argument("--dry-run", action="store_true", dest="dry_run",
                        help="Allow placeholder outputs for integration testing (no real inference)")
    args = parser.parse_args()
    t_start = time.time()

    print(f"[DiffSynth Bridge] Backend: {args.backend}, Task: {args.task}")
    print(f"[DiffSynth Bridge] Input: {args.input}")

    if args.backend == "vista4d" and not args.dry_run:
        print("[DiffSynth Bridge] ERROR: Vista4D backend is NOT implemented "
              "(rendering and Wan inference are not wired).", file=sys.stderr)
        print("  Pass --dry-run only for integration tests.", file=sys.stderr)
        sys.exit(2)

    if not args.dry_run and not check_diffsynth():
        print("[DiffSynth Bridge] ERROR: DiffSynth-Studio not installed.", file=sys.stderr)
        print("  Install: pip install diffsynth", file=sys.stderr)
        print("  Full setup: run scripts/setup_diffsynth.bat (or .sh)", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(args.output).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.backend == "worldmirror2":
        _run_worldmirror2(args, output_dir)
    elif args.backend == "vista4d":
        _run_vista4d(args, output_dir)
    elif args.backend == "anyrecon":
        _run_anyrecon(args, output_dir)
    elif args.backend == "dvlt":
        _run_dvlt(args, output_dir)

    # Write completion marker
    marker = output_dir / ".diffsynth_done"
    marker.write_text(json.dumps({
        "backend": args.backend,
        "task": args.task,
        "input": args.input,
        "dry_run": args.dry_run,
        "elapsed_s": round(time.time() - t_start, 1)
    }))
    print(f"[DiffSynth Bridge] Done. Marker: {marker}")


def _run_worldmirror2(args, output_dir):
    """WorldMirror 2.0: feed-forward single-pass reconstruction."""
    t_start = time.time()
    try:
        from hyworld2.worldrecon.pipeline import WorldMirrorPipeline
    except ImportError:
        print("[DiffSynth Bridge] hyworld2 not installed. Run scripts/setup_worldmirror.bat", file=sys.stderr)
        sys.exit(1)

    pipeline = WorldMirrorPipeline.from_pretrained("tencent/HY-World-2.0", subfolder="HY-WorldMirror-2.0")
    pipeline(
        str(args.input), output_path=str(output_dir), target_size=args.target_size,
        fps=args.fps, video_strategy="new", strict_output_path=str(output_dir)
    )
    print(f"[DiffSynth Bridge] WorldMirror 2.0 done in {time.time() - t_start:.1f}s")


def _run_vista4d(args, output_dir):
    """Vista4D: 4D point cloud reconstruction + novel viewpoint video synthesis."""
    if args.dry_run:
        print("[DiffSynth Bridge] Vista4D DRY-RUN: no reconstruction, render, or inference was performed.")
        return

    print("[DiffSynth Bridge] ERROR: Vista4D backend is NOT implemented "
          "(rendering and Wan inference are not wired).", file=sys.stderr)
    sys.exit(2)


def _run_anyrecon(args, output_dir):
    """AnyRecon: arbitrary-view reconstruction from sparse inputs."""
    t_start = time.time()
    try:
        import diffsynth
    except ImportError:
        print("[DiffSynth Bridge] DiffSynth-Studio not installed.", file=sys.stderr)
        sys.exit(1)

    input_path = Path(args.input).resolve()
    if not input_path.is_dir():
        print(f"[DiffSynth Bridge] AnyRecon expects a frames directory, got: {input_path}", file=sys.stderr)
        sys.exit(1)

    # Collect sparse input frames
    image_files = sorted([
        str(input_path / f) for f in os.listdir(input_path)
        if f.lower().endswith(('.png', '.jpg', '.jpeg'))
    ])
    if len(image_files) < 2:
        print(f"[DiffSynth Bridge] AnyRecon needs at least 2 frames, found {len(image_files)}", file=sys.stderr)
        sys.exit(1)

    print(f"[DiffSynth Bridge] AnyRecon: {len(image_files)} sparse frames")
    # Phase 1: Initial 3D geometry from COLMAP/DUSt3R
    # Phase 2: Geometry-driven view selection
    # Phase 3: Wan 2.1 I2V inference with AnyRecon LoRA
    # Phase 4: 3D geometry memory update (iterative loop)

    # Implémentation réelle non disponible (nécessite AnyRecon LoRA + pipeline Wan I2V).
    # On échoue explicitement plutôt que de retourner un succès silencieusement faux.
    if not getattr(args, "dry_run", False):
        print("[DiffSynth Bridge] ERROR: AnyRecon backend is NOT implemented "
              "(requires AnyRecon LoRA weights + Wan I2V pipeline).", file=sys.stderr)
        print("  Use --backend worldmirror2, or pass --dry-run for integration tests.", file=sys.stderr)
        sys.exit(2)

    print(f"[DiffSynth Bridge] AnyRecon DRY-RUN placeholder done in {time.time() - t_start:.1f}s")


def _run_dvlt(args, output_dir):
    """DVLT (Déjà View): Multi-view unposed reconstruction with compute loop knob."""
    t_start = time.time()
    try:
        import torch  # noqa: F401
        # import package from cloned nv-tlabs/dvlt repo
        from dvlt.models.looping_transformer import LoopingTransformerReconstruction  # noqa: F401
    except ImportError:
        print("[DiffSynth Bridge] ERROR: DVLT (nv-tlabs/dvlt) is not installed.", file=sys.stderr)
        print("  To install: git clone https://github.com/nv-tlabs/dvlt && pip install -e .", file=sys.stderr)
        sys.exit(1)

    input_path = Path(args.input).resolve()
    if not input_path.is_dir():
        print(f"[DiffSynth Bridge] DVLT expects an input frames directory, got: {input_path}", file=sys.stderr)
        sys.exit(1)

    image_files = sorted([
        str(input_path / f) for f in os.listdir(input_path)
        if f.lower().endswith(('.png', '.jpg', '.jpeg'))
    ])
    if len(image_files) < 2:
        print(f"[DiffSynth Bridge] DVLT needs at least 2 frames, found {len(image_files)}", file=sys.stderr)
        sys.exit(1)

    print(f"[DiffSynth Bridge] DVLT: Processing {len(image_files)} unposed frames on {args.device}...")
    print(f"[DiffSynth Bridge] DVLT: Compute Loop refinement steps (K) = {args.loop_steps}")

    # 1. Instancier le Looping Transformer de Déjà View
    # model = LoopingTransformerReconstruction.from_pretrained("nvidia/dvlt")
    # model.to(args.device)
    
    # 2. Inférence avec le "Compute Knob" K configuré
    # outputs = model.reconstruct(image_files, refinement_steps=args.loop_steps)
    
    # 3. Sauvegarder les profondeurs, les poses estimées et les ray maps (nuage de points)
    # outputs.save_depth_maps(str(output_dir / "depth"))
    # outputs.save_camera_params(str(output_dir / "camera_params.json"))
    # outputs.save_point_cloud(str(output_dir / "points.ply"))

    # Inférence réelle non câblée : on échoue explicitement hors --dry-run
    # plutôt que d'écrire de fausses poses (audit B8).
    if not getattr(args, "dry_run", False):
        print("[DiffSynth Bridge] ERROR: DVLT inference is NOT wired yet "
              "(model instantiation/reconstruct calls are stubbed).", file=sys.stderr)
        print("  Pass --dry-run to generate placeholder outputs for integration tests.", file=sys.stderr)
        sys.exit(2)

    (output_dir / "depth").mkdir(parents=True, exist_ok=True)
    camera_params = output_dir / "camera_params.json"
    camera_params.write_text(json.dumps({
        "extrinsics": [
            {
                "camera_id": 0,
                "matrix": [
                    [1.0, 0.0, 0.0, 0.0],
                    [0.0, 1.0, 0.0, 0.0],
                    [0.0, 0.0, 1.0, 0.0],
                    [0.0, 0.0, 0.0, 1.0]
                ]
            },
            {
                "camera_id": 1,
                "matrix": [
                    [0.9, 0.0, 0.1, 0.2],
                    [0.0, 1.0, 0.0, 0.0],
                    [-0.1, 0.0, 0.9, 0.5],
                    [0.0, 0.0, 0.0, 1.0]
                ]
            }
        ],
        "intrinsics": [
            {
                "camera_id": 0,
                "matrix": [
                    [525.0, 0.0, 320.0],
                    [0.0, 525.0, 240.0],
                    [0.0, 0.0, 1.0]
                ]
            },
            {
                "camera_id": 1,
                "matrix": [
                    [525.0, 0.0, 320.0],
                    [0.0, 525.0, 240.0],
                    [0.0, 0.0, 1.0]
                ]
            }
        ],
        "num_cameras": 2
    }))

    print("[DiffSynth Bridge] DVLT DRY-RUN: wrote placeholder depth/ and camera_params.json.")
    print(f"[DiffSynth Bridge] DVLT finished in {time.time() - t_start:.1f}s")


if __name__ == "__main__":
    main()
