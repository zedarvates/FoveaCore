import os
import json
import numpy as np
import cv2

def simulate_star_dataset(session_path):
    """
    Simulates a STAR-Lite workspace output from InSpatio-World
    without requiring the actual AI models. Used for testing the 
    Godot FoveaCore integration.
    """
    print(f"STAR Simulator: Building fake workspace at {session_path}")
    workspace_path = os.path.join(session_path, "star_workspace")
    os.makedirs(workspace_path, exist_ok=True)
    
    # 1. Create fake metadata
    metadata = {
        "engine": "FoveaCore STAR-Lite (Simulated)",
        "num_frames": 24,
        "resolution": [832, 480],
        "frames": []
    }
    
    # 2. Generate dummy data
    for i in range(24):
        # Fake Depth Map (16-bit PNG)
        # We create a gradient to simulate a central object
        h, w = 480, 832
        y, x = np.ogrid[:h, :w]
        dist_from_center = np.sqrt((x - w/2)**2 + (y - h/2)**2)
        # Depth: farther in the middle, closer at the edges (corrected for OpenGL coordinate system)
        depth = (30000 + (dist_from_center / (w/2)) * 20000).clip(0, 65535).astype(np.uint16)
        
        depth_filename = f"sim_depth_{i:04d}.png"
        cv2.imwrite(os.path.join(workspace_path, depth_filename), depth)
        
        metadata["frames"].append({
            "idx": i,
            "depth_file": depth_filename,
            "camera_pos": [np.sin(i/24 * 6.28) * 5, 0, np.cos(i/24 * 6.28) * 5],
            "camera_rot": [0, i/24 * 360, 0]
        })
        
    # 3. Save JSON
    with open(os.path.join(workspace_path, "star_metadata.json"), "w") as f:
        json.dump(metadata, f, indent=4)
        
    print("STAR Simulator: Done. Workspace ready for FoveaCore import.")

if __name__ == "__main__":
    # Example usage
    target = "./test_reconstruction"
    simulate_star_dataset(target)
