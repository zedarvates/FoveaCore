"""
WorldMirror 2.0 bridge for FoveaEngine.
Drop-in replacement for star_bridge.py using Tencent Hunyuan's WorldMirror 2.0.
Feed-forward reconstruction: video/images -> depth, normals, cameras, point cloud, 3DGS.

Usage:
    python worldmirror_bridge.py --input <frames_dir> --output <workspace_dir>
    python worldmirror_bridge.py --input frames/ --output workspace/ --target_size 1904 --device cuda
"""
import argparse
import json
import os
import sys
import time
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="FoveaCore WorldMirror 2.0 Bridge")
    parser.add_argument("--input", required=True, help="Input frames directory")
    parser.add_argument("--output", required=True, help="Output workspace directory")
    parser.add_argument("--device", default="cuda", help="Computation device (cuda/cpu)")
    parser.add_argument("--target_size", type=int, default=952, help="Max inference resolution")
    parser.add_argument("--fps", type=int, default=2, help="FPS for video frame extraction (ignored for image dirs)")
    parser.add_argument("--no_save_depth", action="store_true", help="Disable depth map output")
    parser.add_argument("--no_save_normal", action="store_true", help="Disable normal map output")
    parser.add_argument("--no_save_gs", action="store_true", help="Disable 3DGS output")
    parser.add_argument("--no_save_camera", action="store_true", help="Disable camera params output")
    parser.add_argument("--no_save_points", action="store_true", help="Disable point cloud output")
    parser.add_argument("--save_colmap", action="store_true", help="Also export COLMAP sparse format")
    args = parser.parse_args()

    input_dir = Path(args.input).resolve()
    output_dir = Path(args.output).resolve()

    if not input_dir.exists():
        print(f"Error: Input directory not found: {input_dir}", file=sys.stderr)
        sys.exit(1)

    image_files = sorted([
        f for f in os.listdir(input_dir)
        if f.lower().endswith(('.png', '.jpg', '.jpeg', '.bmp'))
    ])
    if not image_files:
        print(f"Error: No images found in {input_dir}", file=sys.stderr)
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"WorldMirror 2.0 Bridge: {len(image_files)} frames in {input_dir}")
    print(f"WorldMirror 2.0 Bridge: Output -> {output_dir}")
    print(f"WorldMirror 2.0 Bridge: Target resolution = {args.target_size}px")

    # Try to import WorldMirror 2.0
    try:
        from hyworld2.worldrecon.pipeline import WorldMirrorPipeline
        HAS_WM2 = True
    except ImportError as e:
        print(f"Error: hyworld2 not installed. Please run setup.\n  {e}", file=sys.stderr)
        print("\nTo install WorldMirror 2.0:", file=sys.stderr)
        print("  1. git clone https://github.com/Tencent-Hunyuan/HY-World-2.0", file=sys.stderr)
        print("  2. pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124", file=sys.stderr)
        print("  3. pip install -r <hyworld2_repo>/requirements.txt", file=sys.stderr)
        print("  4. Ensure hyworld2/ is in PYTHONPATH", file=sys.stderr)
        sys.exit(1)

    t_start = time.time()

    try:
        pipeline = WorldMirrorPipeline.from_pretrained(
            "tencent/HY-World-2.0",
            subfolder="HY-WorldMirror-2.0",
        )
    except Exception as e:
        print(f"Error loading WorldMirror 2.0 model: {e}", file=sys.stderr)
        print("Ensure HuggingFace hub is accessible and ~5GB free disk space for model weights.", file=sys.stderr)
        sys.exit(1)

    print(f"WorldMirror 2.0 Bridge: Model loaded. Running inference...")

    try:
        result = pipeline(
            str(input_dir),
            output_path=str(output_dir),
            target_size=args.target_size,
            fps=args.fps,
            video_strategy="new",
            save_depth=not args.no_save_depth,
            save_normal=not args.no_save_normal,
            save_gs=not args.no_save_gs,
            save_camera=not args.no_save_camera,
            save_points=not args.no_save_points,
            save_colmap=args.save_colmap,
            strict_output_path=str(output_dir),
            log_time=True,
        )

        elapsed = time.time() - t_start
        print(f"WorldMirror 2.0 Bridge: Done in {elapsed:.1f}s")

        # Verify critical outputs
        ply_path = output_dir / "gaussians.ply"
        cam_path = output_dir / "camera_params.json"
        if ply_path.exists():
            ply_size = ply_path.stat().st_size
            print(f"WorldMirror 2.0 Bridge: gaussians.ply ({ply_size / 1e6:.1f} MB)")
        if cam_path.exists():
            print(f"WorldMirror 2.0 Bridge: camera_params.json")

        # Write completion marker for GDScript to detect
        marker = output_dir / ".worldmirror_done"
        marker.write_text(json.dumps({
            "engine": "FoveaCore WorldMirror-2.0",
            "input": str(input_dir),
            "target_size": args.target_size,
            "frames": len(image_files),
            "elapsed_s": round(elapsed, 1),
        }))
        print(f"WorldMirror 2.0 Bridge: Completion marker written.")

    except Exception as e:
        print(f"Error during WorldMirror 2.0 inference: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
