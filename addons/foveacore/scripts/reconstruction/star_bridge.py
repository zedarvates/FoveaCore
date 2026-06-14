import os
import sys
import argparse
import json
import cv2
import numpy as np

# We assume depth_anything_3 is installed if the user followed the InSpatio instructions
try:
    from depth_anything_3.dpt import DepthAnythingV2
    import torch
    HAS_DA3 = True
except ImportError:
    HAS_DA3 = False

def process_star_monocular(input_dir, output_dir, device='cuda', checkpoint=None, allow_heuristic=False):
    print(f"STAR Bridge: Starting fast monocular path for {input_dir}")
    os.makedirs(output_dir, exist_ok=True)

    image_files = sorted([f for f in os.listdir(input_dir) if f.lower().endswith(('.png', '.jpg', '.jpeg'))])
    if not image_files:
        print("STAR Bridge ERROR: No images found in input directory.", file=sys.stderr)
        sys.exit(1)

    # 1. Initialize DA3 Model — échec explicite si indisponible (audit B8),
    #    sauf si --allow-heuristic est passé (profondeur approximative assumée).
    model = None
    if not HAS_DA3:
        if not allow_heuristic:
            print("STAR Bridge ERROR: depth_anything_3 not found. "
                  "Install it (InSpatio-World env) or pass --allow-heuristic.", file=sys.stderr)
            sys.exit(1)
        print("STAR Bridge WARNING: DA3 missing — using heuristic depth (low quality).")
    else:
        if not checkpoint or not os.path.isfile(checkpoint):
            if not allow_heuristic:
                print("STAR Bridge ERROR: --checkpoint path to DA3 weights is required "
                      "(random weights would produce garbage depth). "
                      "Or pass --allow-heuristic.", file=sys.stderr)
                sys.exit(1)
            print("STAR Bridge WARNING: no valid checkpoint — using heuristic depth.")
        else:
            print(f"STAR Bridge: Loading Depth-Anything-3 from {checkpoint}...")
            try:
                model = DepthAnythingV2(encoder='vitg', features=256, out_channels=[256, 512, 1024, 2048])
                model.load_state_dict(torch.load(checkpoint, map_location=device))
                model = model.to(device).eval()
            except Exception as e:
                print(f"STAR Bridge ERROR: failed to load DA3 model: {e}", file=sys.stderr)
                if not allow_heuristic:
                    sys.exit(1)
                model = None
                print("STAR Bridge WARNING: falling back to heuristic depth.")

    # 2. Process Frames
    depth_atlas = []
    metadata = {
        "frames": [],
        "engine": "FoveaCore STAR-Lite",
        "source": input_dir,
        "depth_source": "da3" if model is not None else "heuristic",
        "poses_are_placeholder": True
    }

    print(f"STAR Bridge: Processing {len(image_files)} frames...")
    for idx, img_name in enumerate(image_files):
        img_path = os.path.join(input_dir, img_name)
        img = cv2.imread(img_path)
        h, w = img.shape[:2]

        # Depth Estimation
        if model is not None:
            try:
                depth = model.infer_image(img)
            except Exception as e:
                print(f"DA3 inference failed for {img_name}: {e}, using heuristic fallback")
                depth = _estimate_depth_heuristic(img)
        else:
            depth = _estimate_depth_heuristic(img)

        depth_name = f"depth_{idx:05d}.png"
        cv2.imwrite(os.path.join(output_dir, depth_name), depth)

        metadata["frames"].append({
            "id": idx,
            "image": img_name,
            "depth": depth_name,
            "intrinsic": [w, h, w/2, h/2], # Placeholder
            "extrinsic": np.eye(4).tolist() # Placeholder
        })

    # 3. Save STAR Metadata
    with open(os.path.join(output_dir, "star_metadata.json"), "w") as f:
        json.dump(metadata, f, indent=4)

    print(f"STAR Bridge: Completed. Results in {output_dir}")

def _estimate_depth_heuristic(img):
    """
    Fallback depth estimation using luminance and edge gradients.
    Produces a rough but deterministic depth map (16-bit unsigned).
    Brighter regions are assumed closer; edges suggest depth discontinuities.
    """
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32)
    sobel_x = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    sobel_y = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    gradient_mag = np.sqrt(sobel_x ** 2 + sobel_y ** 2)

    # Invert luminance: darker => further
    depth_base = 1.0 - gray / 255.0
    # Edge attenuation: edges reduce depth confidence, push further
    edge_factor = np.clip(gradient_mag / 255.0, 0.0, 0.5)
    depth_heuristic = (depth_base + edge_factor) * 65535.0 * 0.5
    depth_heuristic = np.clip(depth_heuristic, 0, 65535)
    return depth_heuristic.astype(np.uint16)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FoveaCore STAR-Lite Bridge")
    parser.add_argument("--input", required=True, help="Input images directory")
    parser.add_argument("--output", required=True, help="Output workspace directory")
    parser.add_argument("--device", default="cuda", help="Computation device")
    parser.add_argument("--checkpoint", default=None, help="Path to DA3 model weights (.pth)")
    parser.add_argument("--allow-heuristic", action="store_true", dest="allow_heuristic",
                        help="Allow low-quality heuristic depth when DA3/weights are unavailable")
    args = parser.parse_args()

    process_star_monocular(args.input, args.output, args.device, args.checkpoint, args.allow_heuristic)
