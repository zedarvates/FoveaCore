#!/usr/bin/env python3
import sys
import os
import json

def get_roi_rembg(image_path):
    try:
        from rembg import remove
        from PIL import Image
        
        input_image = Image.open(image_path)
        output_image = remove(input_image)
        bbox = output_image.getbbox() # returns (left, upper, right, lower)
        if bbox:
            left, upper, right, lower = bbox
            w = right - left
            h = lower - upper
            return {
                "x": int(left),
                "y": int(upper),
                "width": int(w),
                "height": int(h),
                "method": "rembg"
            }
    except Exception as e:
        print(f"# rembg method failed: {e}", file=sys.stderr)
    return None

def get_roi_opencv(image_path):
    try:
        import cv2
        
        img = cv2.imread(image_path)
        if img is None:
            return None
            
        height, width = img.shape[:2]
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Estimate background brightness from corners
        corners = [
            int(gray[0, 0]),
            int(gray[0, width - 1]),
            int(gray[height - 1, 0]),
            int(gray[height - 1, width - 1])
        ]
        mean_bg = sum(corners) / 4.0
        
        # Apply blur to remove noise
        blur = cv2.GaussianBlur(gray, (5, 5), 0)
        
        if mean_bg > 127:
            # Light background -> threshold to find dark objects
            _, thresh = cv2.threshold(blur, int(mean_bg - 30), 255, cv2.THRESH_BINARY_INV)
        else:
            # Dark background -> threshold to find light objects
            _, thresh = cv2.threshold(blur, int(mean_bg + 30), 255, cv2.THRESH_BINARY)
            
        contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            return None
            
        # Get largest contour by area
        largest_contour = max(contours, key=cv2.contourArea)
        # Check if it has a reasonable size
        if cv2.contourArea(largest_contour) < (width * height * 0.005):
            return None
            
        x, y, w, h = cv2.boundingRect(largest_contour)
        
        # Add some padding
        padding = 15
        x = max(0, x - padding)
        y = max(0, y - padding)
        w = min(width - x, w + 2 * padding)
        h = min(height - y, h + 2 * padding)
        
        return {
            "x": int(x),
            "y": int(y),
            "width": int(w),
            "height": int(h),
            "method": "opencv"
        }
    except Exception as e:
        print(f"# OpenCV method failed: {e}", file=sys.stderr)
    return None

def get_roi_pil_fallback(image_path):
    try:
        from PIL import Image
        
        img = Image.open(image_path).convert("RGB")
        w, h = img.size
        
        # Sample corner colors
        corners = [
            img.getpixel((0, 0)),
            img.getpixel((w - 1, 0)),
            img.getpixel((0, h - 1)),
            img.getpixel((w - 1, h - 1))
        ]
        avg_r = sum(c[0] for c in corners) / 4.0
        avg_g = sum(c[1] for c in corners) / 4.0
        avg_b = sum(c[2] for c in corners) / 4.0
        
        min_x, min_y = w, h
        max_x, max_y = 0, 0
        threshold = 35 # RGB distance threshold
        
        # Scan image with a step size of 2 for speed
        for y in range(0, h, 2):
            for x in range(0, w, 2):
                r, g, b = img.getpixel((x, y))
                diff = abs(r - avg_r) + abs(g - avg_g) + abs(b - avg_b)
                if diff > threshold:
                    if x < min_x: min_x = x
                    if y < min_y: min_y = y
                    if x > max_x: max_x = x
                    if y > max_y: max_y = y
                    
        if max_x >= min_x and max_y >= min_y:
            padding = 10
            x = max(0, min_x - padding)
            y = max(0, min_y - padding)
            width = min(w - x, (max_x - min_x) + 2 * padding)
            height = min(h - y, (max_y - min_y) + 2 * padding)
            
            return {
                "x": int(x),
                "y": int(y),
                "width": int(width),
                "height": int(height),
                "method": "pil_fallback"
            }
    except Exception as e:
        print(f"# PIL fallback method failed: {e}", file=sys.stderr)
    return None

def get_image_size(image_path):
    try:
        from PIL import Image
        img = Image.open(image_path)
        return img.size
    except Exception:
        try:
            import cv2
            img = cv2.imread(image_path)
            if img is not None:
                return img.shape[1], img.shape[0]
        except Exception:
            pass
    return 800, 800

def main():
    import argparse
    parser = argparse.ArgumentParser(description="Auto-ROI detection")
    parser.add_argument("image_path", nargs="?", help="Path to input image")
    parser.add_argument("--input", help="Path to input image")
    parser.add_argument("--model", help="Path to model")
    args = parser.parse_args()
    
    image_path = args.input if args.input else args.image_path
    if not image_path:
        print("Error: No image path provided.", file=sys.stderr)
        sys.exit(1)
        
    if not os.path.exists(image_path):
        print(f"Error: Image path '{image_path}' does not exist.", file=sys.stderr)
        sys.exit(1)
        
    # 1. Try rembg
    roi = get_roi_rembg(image_path)
    
    # 2. Try OpenCV
    if roi is None:
        roi = get_roi_opencv(image_path)
        
    # 3. Try PIL corner difference fallback
    if roi is None:
        roi = get_roi_pil_fallback(image_path)
        
    # 4. Final safety fallback (center 80% box)
    if roi is None:
        w, h = get_image_size(image_path)
        x = int(w * 0.1)
        y = int(h * 0.1)
        width = int(w * 0.8)
        height = int(h * 0.8)
        roi = {
            "x": x,
            "y": y,
            "width": width,
            "height": height,
            "method": "safety_fallback"
        }
        
    # Print the result to stdout as JSON
    print(json.dumps(roi))

if __name__ == "__main__":
    main()
