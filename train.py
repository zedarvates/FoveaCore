import os
import sys
import math
import struct
import argparse
import random

def main():
    parser = argparse.ArgumentParser(description="FoveaCore 3DGS Mock Trainer")
    parser.add_argument("-s", "--source_path", required=True, help="Path to the reconstruction source directory")
    parser.add_argument("-m", "--model_path", required=True, help="Path to the output directory")
    parser.add_argument("--iterations", type=int, default=7000, help="Number of training iterations")
    args = parser.parse_args()

    print(f"Mock Trainer: Starting training for {args.iterations} iterations...")
    print(f"Mock Trainer: Source={args.source_path}")
    print(f"Mock Trainer: Model Path={args.model_path}")

    # Output path for the PLY file expected by Godot
    output_dir = os.path.join(args.model_path, "point_cloud", f"iteration_{args.iterations}")
    os.makedirs(output_dir, exist_ok=True)
    ply_path = os.path.join(output_dir, "point_cloud.ply")

    # Generate a beautiful 3D Bonsai Tree point cloud
    splats = []

    # 1. Trunk (brown cylinders and branches)
    trunk_points = 1500
    for i in range(trunk_points):
        # Trunk main column (height from -0.5 to 1.5, slightly tapering)
        t = random.uniform(0, 1)
        height = -0.5 + t * 2.0
        radius = 0.15 * (1.0 - t * 0.5) # tapering
        
        # Add some trunk twisting/curvature
        angle = t * 2.0 * math.pi * 0.1
        center_x = 0.2 * math.sin(t * math.pi)
        center_z = 0.2 * (1.0 - math.cos(t * math.pi))

        theta = random.uniform(0, 2 * math.pi)
        r = radius * random.uniform(0.7, 1.0)
        x = center_x + r * math.cos(theta)
        z = center_z + r * math.sin(theta)
        y = height

        # Brown color: R=0.45, G=0.32, B=0.18
        # f_dc = (color - 0.5) / 0.28209
        f_dc_0 = (0.45 - 0.5) / 0.28209
        f_dc_1 = (0.32 - 0.5) / 0.28209
        f_dc_2 = (0.18 - 0.5) / 0.28209

        # Opacity (logit space, logit=3.0 -> opacity ~0.95)
        opacity = 3.0
        # Scale (log space, log(0.04) ~ -3.2)
        scale = -3.2

        splats.append((x, y, z, opacity, scale, scale, scale, 1.0, 0.0, 0.0, 0.0, f_dc_0, f_dc_1, f_dc_2))

    # 2. Main branches branching off
    branch_count = 5
    for b in range(branch_count):
        branch_points = 500
        # Start branch from a height on the trunk
        start_t = 0.3 + b * 0.12
        start_height = -0.5 + start_t * 2.0
        start_x = 0.2 * math.sin(start_t * math.pi)
        start_z = 0.2 * (1.0 - math.cos(start_t * math.pi))

        # Branch direction
        b_angle = (b * (2 * math.pi / branch_count)) + random.uniform(-0.2, 0.2)
        length = random.uniform(0.6, 1.2)

        for i in range(branch_points):
            t = random.uniform(0, 1)
            # Branch curver outwards and upwards
            dist = length * t
            y = start_height + 0.3 * (t ** 1.5)
            x = start_x + dist * math.cos(b_angle)
            z = start_z + dist * math.sin(b_angle)

            # Add thickness
            r_thickness = 0.05 * (1.0 - t * 0.7)
            theta = random.uniform(0, 2 * math.pi)
            r = r_thickness * random.uniform(0, 1.0)
            x += r * math.sin(b_angle) * math.cos(theta)
            z -= r * math.cos(b_angle) * math.cos(theta)
            y += r * math.sin(theta)

            # Brown color
            f_dc_0 = (0.45 - 0.5) / 0.28209
            f_dc_1 = (0.32 - 0.5) / 0.28209
            f_dc_2 = (0.18 - 0.5) / 0.28209

            opacity = 3.0
            scale = -3.5

            splats.append((x, y, z, opacity, scale, scale, scale, 1.0, 0.0, 0.0, 0.0, f_dc_0, f_dc_1, f_dc_2))

            # 3. Bioluminescent Green/Cyan leaves at the tips of the branches
            if t > 0.4:
                # Add leaves branching off
                leaf_points = 3
                for _ in range(leaf_points):
                    lx = x + random.uniform(-0.15, 0.15)
                    ly = y + random.uniform(-0.1, 0.1)
                    lz = z + random.uniform(-0.15, 0.15)

                    # Bioluminescent Green/Cyan color: R=0.15, G=0.85, B=0.55
                    f_dc_0 = (0.15 - 0.5) / 0.28209
                    f_dc_1 = (0.85 - 0.5) / 0.28209
                    f_dc_2 = (0.55 - 0.5) / 0.28209

                    opacity = 2.5 # ~0.92 opacity
                    scale = -3.8  # smaller leaf splats

                    # Random rotation for leaves
                    q0 = random.uniform(-1, 1)
                    q1 = random.uniform(-1, 1)
                    q2 = random.uniform(-1, 1)
                    q3 = random.uniform(-1, 1)
                    q_len = math.sqrt(q0**2 + q1**2 + q2**2 + q3**2)
                    if q_len > 0:
                        q0 /= q_len
                        q1 /= q_len
                        q2 /= q_len
                        q3 /= q_len
                    else:
                        q0, q1, q2, q3 = 1.0, 0.0, 0.0, 0.0

                    splats.append((lx, ly, lz, opacity, scale, scale, scale, q0, q1, q2, q3, f_dc_0, f_dc_1, f_dc_2))

    # 4. Dense crown on top of the trunk
    crown_points = 4000
    for i in range(crown_points):
        # Cluster around center x=0, z=0.5, y=1.8 (top of trunk)
        r = random.uniform(0.1, 0.8)
        theta = random.uniform(0, 2 * math.pi)
        phi = random.uniform(0, math.pi)
        
        # Flattened crown ellipsoid
        dx = r * math.sin(phi) * math.cos(theta) * 1.2
        dz = r * math.sin(phi) * math.sin(theta) * 1.2
        dy = r * math.cos(phi) * 0.6

        x = 0.1 + dx
        z = 0.4 + dz
        y = 1.6 + dy

        # Bioluminescent leaf color
        f_dc_0 = (0.15 - 0.5) / 0.28209
        f_dc_1 = (0.85 - 0.5) / 0.28209
        f_dc_2 = (0.55 - 0.5) / 0.28209

        opacity = 2.0
        scale = -3.7

        q0 = random.uniform(-1, 1)
        q1 = random.uniform(-1, 1)
        q2 = random.uniform(-1, 1)
        q3 = random.uniform(-1, 1)
        q_len = math.sqrt(q0**2 + q1**2 + q2**2 + q3**2)
        if q_len > 0:
            q0 /= q_len; q1 /= q_len; q2 /= q_len; q3 /= q_len
        else:
            q0, q1, q2, q3 = 1.0, 0.0, 0.0, 0.0

        splats.append((x, y, z, opacity, scale, scale, scale, q0, q1, q2, q3, f_dc_0, f_dc_1, f_dc_2))

    # Write the binary PLY file
    num_points = len(splats)
    print(f"Mock Trainer: Writing {num_points} splats to {ply_path}...")
    
    with open(ply_path, "wb") as f:
        # Header
        f.write(b"ply\n")
        f.write(b"format binary_little_endian 1.0\n")
        f.write(f"element vertex {num_points}\n".encode())
        f.write(b"property float x\n")
        f.write(b"property float y\n")
        f.write(b"property float z\n")
        f.write(b"property float opacity\n")
        f.write(b"property float scale_0\n")
        f.write(b"property float scale_1\n")
        f.write(b"property float scale_2\n")
        f.write(b"property float rot_0\n")
        f.write(b"property float rot_1\n")
        f.write(b"property float rot_2\n")
        f.write(b"property float rot_3\n")
        f.write(b"property float f_dc_0\n")
        f.write(b"property float f_dc_1\n")
        f.write(b"property float f_dc_2\n")
        f.write(b"end_header\n")

        # Binary data (14 float32 values per vertex)
        for s in splats:
            data = struct.pack("<14f", *s)
            f.write(data)

    print("Mock Trainer: Training completed successfully! Output file created.")

if __name__ == "__main__":
    main()
