"""
TripoSplat bridge for FoveaEngine.
Feed-forward reconstruction: single image -> 3DGS (.ply).

Usage:
    python triposplat_bridge.py --input <image_path> --output <workspace_dir> --density 262144
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="FoveaCore TripoSplat Bridge")
    parser.add_argument("--input", required=True, help="Input single image file")
    parser.add_argument("--output", required=True, help="Output workspace directory")
    parser.add_argument("--device", default="cuda", help="Computation device (cuda/cpu)")
    parser.add_argument("--density", type=int, default=262144, help="Target number of Gaussians (up to 262144)")
    parser.add_argument("--ckpt_dir", default="ckpts", help="Directory where model checkpoints are stored")
    args = parser.parse_args()

    input_image = Path(args.input).resolve()
    output_dir = Path(args.output).resolve()

    if not input_image.exists() or not input_image.is_file():
        print(f"Error: Input image file not found: {input_image}", file=sys.stderr)
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"TripoSplat Bridge: Input image = {input_image}")
    print(f"TripoSplat Bridge: Output -> {output_dir}")
    print(f"TripoSplat Bridge: Density (num_gaussians) = {args.density}")

    # Try to import TripoSplat dependencies
    try:
        import torch
        import numpy as np
        import safetensors
        from PIL import Image
        HAS_DEPS = True
    except ImportError as e:
        print(f"Error: Required dependencies (torch, numpy, safetensors, pillow) not installed.\n  {e}", file=sys.stderr)
        sys.exit(1)

    # Try to import TripoSplat pipeline
    try:
        from triposplat import TripoSplatPipeline
        HAS_TRIPOSPLAT = True
    except ImportError as e:
        print(f"Error: triposplat not found. Ensure TripoSplat repo is cloned and added to PYTHONPATH.\n  {e}", file=sys.stderr)
        print("\nTo set up TripoSplat:", file=sys.stderr)
        print("  1. git clone https://github.com/VAST-AI-Research/TripoSplat", file=sys.stderr)
        print("  2. Ensure the cloned repo is in your PYTHONPATH or run from its root.", file=sys.stderr)
        sys.exit(1)

    ckpt_dir = Path(args.ckpt_dir).resolve()
    
    # Auto-download checkpoints if not present
    diffusion_ckpt = ckpt_dir / "diffusion_models" / "triposplat_fp16.safetensors"
    if not diffusion_ckpt.exists():
        print(f"TripoSplat Bridge: Checkpoints not found in {ckpt_dir}. Downloading from HuggingFace...")
        try:
            from huggingface_hub import snapshot_download
            snapshot_download(repo_id='VAST-AI/TripoSplat', local_dir=str(ckpt_dir))
            print("TripoSplat Bridge: Download complete.")
        except Exception as e:
            print(f"Error: Failed to download checkpoints automatically: {e}", file=sys.stderr)
            print("Please download manually and place in 'ckpts/' directory.", file=sys.stderr)
            sys.exit(1)

    t_start = time.time()

    try:
        print("TripoSplat Bridge: Initializing pipeline...")
        pipe = TripoSplatPipeline(
            ckpt_path=str(ckpt_dir / "diffusion_models" / "triposplat_fp16.safetensors"),
            decoder_path=str(ckpt_dir / "vae" / "triposplat_vae_decoder_fp16.safetensors"),
            dinov3_path=str(ckpt_dir / "clip_vision" / "dino_v3_vit_h.safetensors"),
            flux2_vae_encoder_path=str(ckpt_dir / "vae" / "flux2-vae.safetensors"),
            rmbg_path=str(ckpt_dir / "background_removal" / "birefnet.safetensors"),
            device=args.device
        )
    except Exception as e:
        print(f"Error loading TripoSplat model: {e}", file=sys.stderr)
        sys.exit(1)

    print("TripoSplat Bridge: Model loaded. Running inference...")

    try:
        # Run inference
        gaussian, prepared = pipe.run(
            str(input_image),
            num_gaussians=args.density,
            show_progress=True
        )

        # Save outputs
        ply_path = output_dir / "gaussians.ply"
        gaussian.save_ply(str(ply_path))
        
        # Save optional splat file
        splat_path = output_dir / "gaussians.splat"
        gaussian.save_splat(str(splat_path))

        elapsed = time.time() - t_start
        print(f"TripoSplat Bridge: Done in {elapsed:.1f}s")
        print(f"TripoSplat Bridge: Saved PLY to {ply_path} ({ply_path.stat().st_size / 1e6:.1f} MB)")

        # Write completion marker for GDScript to detect
        marker = output_dir / ".triposplat_done"
        marker.write_text(json.dumps({
            "engine": "FoveaCore TripoSplat",
            "input": str(input_image),
            "density": args.density,
            "elapsed_s": round(elapsed, 1),
        }))
        print("TripoSplat Bridge: Completion marker written.")

    except Exception as e:
        print(f"Error during TripoSplat inference: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
