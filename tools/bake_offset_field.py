#!/usr/bin/env python3
"""FoveaEngine — Bake Offset Field (item 127)
Converts a NumPy vector field (Nx×Ny×Nz×3) to a Godot .tres resource
readable by FoveaNeuralOffsetField.

Usage:
    python tools/bake_offset_field.py --input field.npy --output offset_field.tres \
        --resolution 16 --bounds "-2,-2,-2,4,4,4"
"""

import numpy as np
import json
import struct
import sys
import os
from pathlib import Path

def bake(input_path: str, output_path: str, resolution: int = 16,
         bounds: tuple = (-2, -2, -2, 4, 4, 4)):
    """Convert .npy field → Godot .tres resource"""
    
    data = np.load(input_path)
    print(f"Loaded field: {data.shape}")
    
    assert len(data.shape) == 4, f"Expected 4D (Nx×Ny×Nz×3), got {data.shape}"
    assert data.shape[3] == 3, f"Last dim must be 3 (xyz), got {data.shape[3]}"
    
    # Flatten to 1D array of floats
    flat = data.flatten().astype(np.float32)
    
    # Write .tres (Godot resource format)
    # Format: [gd_resource type="Resource" load_steps=2 format=3]
    #         [resource]
    #         script = ExtResource(...)
    #         grid_resolution = 16
    #         data = PackedFloat32Array(...)
    
    script_path = "res://addons/foveacore/scripts/animation/fovea_neural_offset_field.gd"
    
    with open(output_path, 'w') as f:
        f.write("[gd_resource type="Resource" load_steps=2 format=3]

")
        f.write("[ext_resource type="Script" path="%s" id="1"]

" % script_path)
        f.write("[resource]
")
        f.write("script = ExtResource("1")
")
        f.write("grid_resolution = %d
" % resolution)
        
        # Pack float32 array as base64 binary
        bytes_data = flat.tobytes()
        import base64
        b64 = base64.b64encode(bytes_data).decode('ascii')
        
        # Write in chunks for readability
        f.write("data = PackedFloat32Array([
")
        chunk_size = 64
        for i in range(0, len(flat), chunk_size):
            chunk = flat[i:i+chunk_size]
            f.write("	" + ", ".join(f"{v:.6f}" for v in chunk) + ",
")
        f.write("])
")
        
        # Write bounds as metadata
        f.write("grid_bounds = AABB(%s, %s)
" % (
            "Vector3(%s)" % ", ".join(f"{b:.3f}" for b in bounds[:3]),
            "Vector3(%s)" % ", ".join(f"{b:.3f}" for b in bounds[3:])
        ))
    
    data_size = len(flat) * 4
    print(f"Baked: {data_size/1024:.1f} KB → {output_path}")
    return True


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Bake Neural Offset Field for FoveaEngine")
    parser.add_argument("--input", required=True, help="Input .npy file (Nx×Ny×Nz×3)")
    parser.add_argument("--output", default="offset_field.tres", help="Output .tres path")
    parser.add_argument("--resolution", type=int, default=16, help="Grid resolution")
    parser.add_argument("--bounds", default="-2,-2,-2,4,4,4", 
                        help="AABB: min_x,min_y,min_z,max_x,max_y,max_z")
    args = parser.parse_args()
    
    bounds = tuple(float(x) for x in args.bounds.split(","))
    assert len(bounds) == 6, "bounds must have 6 values"
    
    bake(args.input, args.output, args.resolution, bounds)


if __name__ == "__main__":
    main()
