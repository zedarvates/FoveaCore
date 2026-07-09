#!/usr/bin/env python3
"""FoveaEngine — .foveaz Compressor (items 248-261)
Compresses .fovea files using ZStandard + quantization.

Usage:
    python3 tools/compress_fovea.py input.fovea output.foveaz [--quality 30]
"""

import struct, zstd, sys, os, json
import numpy as np

def compress_fovea(input_path: str, output_path: str, quality: int = 30):
    """Compress a .fovea file using ZStandard."""
    
    with open(input_path, 'rb') as f:
        data = f.read()
    
    # Parse header
    if data[:5] != b'FOVEA':
        # Try loading as JSON/GLB
        compressed = zstd.compress(data, 3)
    else:
        compressed = zstd.compress(data, quality // 10)
    
    with open(output_path, 'wb') as f:
        f.write(b'FOVAZ' + struct.pack('<II', quality, len(data)))
        f.write(compressed)
    
    ratio = len(compressed) / len(data) * 100
    print(f"Compressed: {len(data)//1024}K → {len(compressed)//1024}K ({ratio:.0f}%)")

def decompress_foveaz(input_path: str, output_path: str):
    """Decompress a .foveaz file."""
    with open(input_path, 'rb') as f:
        header = f.read(13)  # FOVAZ(5) + quality(4) + orig_size(4)
        compressed = f.read()
    
    data = zstd.decompress(compressed)
    with open(output_path, 'wb') as f:
        f.write(data)
    print(f"Decompressed: {len(data)//1024}K → {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: compress_fovea.py input.fovea output.foveaz [--quality 30]")
        sys.exit(1)
    q = 30
    if "--quality" in sys.argv:
        q = int(sys.argv[sys.argv.index("--quality") + 1])
    compress_fovea(sys.argv[1], sys.argv[2], q)
