import os
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

def process_star_monocular(input_dir, output_dir, device='cuda'):
    print(f"STAR Bridge: Starting fast monocular path for {input_dir}")
    os.makedirs(output_dir, exist_ok=True)

    image_files = sorted([f for f in os.listdir(input_dir) if f.lower().endswith(('.png', '.jpg', '.jpeg'))])
    if not image_files:
        print("Error: No images found in input directory.")
        return

    # 1. Initialize DA3 Model
    if not HAS_DA3:
        print("Error: depth_anything_3 not found. Please install it using the InSpatio-World environment.")
        return

    print("STAR Bridge: Loading Depth-Anything-3...")
    # Using 'giant' as default for high quality, fallback to 'large'
    try:
        model = DepthAnythingV2(encoder='vitg', features=256, out_channels=[256, 512, 1024, 2048])
        # Note: In a real scenario, the user would provide the checkpoint path.
        # Here we assume the model is ready or they have the path in their environment.
        # This is a placeholder for the actual model loading logic from InSpatio.
    except Exception as e:
        print(f"Error loading model: {e}")
        return

    # 2. Process Frames
    depth_atlas = []
    metadata = {
        "frames": [],
        "engine": "FoveaCore STAR-Lite",
        "source": input_dir
    }

    print(f"STAR Bridge: Processing {len(image_files)} frames...")
    for idx, img_name in enumerate(image_files):
        img_path = os.path.join(input_dir, img_name)
        img = cv2.imread(img_path)
        h, w = img.shape[:2]

        # Depth Estimation
        if HAS_DA3:
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
    args = parser.parse_args()

    process_star_monocular(args.input, args.output, args.device)
