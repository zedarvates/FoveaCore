import os
import argparse
import cv2
import numpy as np

def main():
    parser = argparse.ArgumentParser(description="Generate temporal variance masks for turntable videos")
    parser.add_argument("--input", default="f:/foveaengine/fovea-engine/reconstructions/furby_real_test/input", help="Directory containing input frames")
    parser.add_argument("--output", default="f:/foveaengine/fovea-engine/reconstructions/furby_real_test/masks", help="Directory to save generated masks")
    parser.add_argument("--threshold", type=float, default=12.0, help="Variance threshold")
    args = parser.parse_args()

    input_dir = args.input
    mask_folder = args.output
    os.makedirs(mask_folder, exist_ok=True)

    frames = sorted([f for f in os.listdir(input_dir) if f.endswith(".png")])
    if not frames:
        print("No frames found in input directory.")
        return

    print(f"Analyzing {len(frames)} frames from {input_dir}...")

    # Load all frames
    all_imgs = []
    for f in frames:
        img = cv2.imread(os.path.join(input_dir, f))
        all_imgs.append(img)
    all_imgs = np.array(all_imgs)
    n_frames, h, w, c = all_imgs.shape

    # Calculate variance over time
    variance = np.var(all_imgs, axis=0) # Shape: (H, W, C)
    mean_var = np.mean(variance, axis=2) # Shape: (H, W)

    # We want a mask where moving elements (variance > threshold) are 255 (white)
    # and static elements (variance <= threshold) are 0 (black).
    moving_mask = (mean_var > args.threshold).astype(np.uint8) * 255

    # Apply morphological operations to clean up the mask (fill holes, remove noise)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    moving_mask = cv2.morphologyEx(moving_mask, cv2.MORPH_CLOSE, kernel)
    moving_mask = cv2.morphologyEx(moving_mask, cv2.MORPH_OPEN, kernel)

    # Ensure the mask covers the center region where the Furby is
    contours, _ = cv2.findContours(moving_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    final_mask = np.zeros_like(moving_mask)
    for cnt in contours:
        # Only fill reasonably large contours
        if cv2.contourArea(cnt) > 2000:
            cv2.drawContours(final_mask, [cnt], -1, 255, -1)

    # Dilate to cover boundaries
    kernel_dil = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (25, 25))
    final_mask = cv2.dilate(final_mask, kernel_dil, iterations=1)

    # Apply Region of Interest (ROI) bounding box
    # Furby is in the center
    roi_x_start = 220
    roi_x_end = 630
    roi_y_start = 80
    roi_y_end = 480

    roi_mask = np.zeros_like(final_mask)
    roi_mask[roi_y_start:roi_y_end, roi_x_start:roi_x_end] = 255

    # Intersect final_mask with roi_mask
    final_mask = cv2.bitwise_and(final_mask, roi_mask)

    # Save the masks
    for i, f in enumerate(frames):
        cv2.imwrite(os.path.join(mask_folder, f), final_mask)

    print(f"Successfully generated {len(frames)} masks in {mask_folder}")

if __name__ == "__main__":
    main()
