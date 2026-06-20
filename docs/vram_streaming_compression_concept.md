# Out-of-Core VRAM Streaming & 12-Byte VQ 1024 Compression Concept

This document outlines the design and compression specifications for FoveaEngine's open-world streaming architecture (A4) and its high-density VR-optimized splat formatting (A7).

## 1. Out-of-Core VRAM Streaming (A4)

To render large open-world environments that exceed GPU memory limits, FoveaEngine employs an **Out-of-Core VRAM Streaming Cache**.

### Spatial Chunking
- Splats are grouped spatially into hierarchical chunks.
- Chunks are index-mapped using 3D Morton/Z-order curves. This maximizes cache locality during frustum culling.
- Chunks are stored on SSD as pre-serialized blocks.

### Cache Lifecycle Pipeline
```
┌───────────┐      Threaded Load      ┌───────────┐     GPU Upload      ┌────────────┐
│    SSD    │  ────────────────────►  │ System RAM│  ────────────────►  │ GPU VRAM   │
│ (Chunks)  │                         │ (Buffers) │                     │ (Draw Buf) │
└───────────┘                         └───────────┘                     └────────────┘
```

1. **Camera Movement**: The camera enters a new sector.
2. **Frustum & LOD Evaluation**: `fovea_streaming_manager` evaluates chunk distances and calculates the LOD target.
3. **Async Read**: Chunks falling inside the loading radius are read from SSD to system RAM asynchronously using Godot background worker threads.
4. **VRAM Upload**: Chunks are uploaded to pre-allocated VRAM ring buffers.
5. **Culling Dispatch**: The GPU Compute Culler runs directly on the active VRAM slots, avoiding CPU-GPU bottlenecks.

---

## 2. 12-Byte VQ 1024 Compression Format (A7)

For VR and high-bandwidth streaming scenarios, the standard 16-byte `PackedSplat` format is compressed down to **12 bytes (96 bits)** using Vector Quantization (VQ) with a codebook size of 1024 indices (10 bits).

### Bit Allocation Layout

| Field | Description | Bit Width | Offset | Range / Quantization |
| :--- | :--- | :--- | :--- | :--- |
| **Position X** | Local quantized X coordinate | 16 bits | data0 (0..15) | [0..65535] mapped to AABB |
| **Position Y** | Local quantized Y coordinate | 16 bits | data0 (16..31)| [0..65535] mapped to AABB |
| **Position Z** | Local quantized Z coordinate | 16 bits | data1 (0..15) | [0..65535] mapped to AABB |
| **Normal U** | Octahedral normal U mapping | 8 bits | data1 (16..23)| [-1.0 .. 1.0] |
| **Normal V** | Octahedral normal V mapping | 8 bits | data1 (24..31)| [-1.0 .. 1.0] |
| **Color Index**| Vector Quantized Color index | 10 bits | data2 (0..9)  | [0..1023] index in color codebook |
| **Covar Index**| Vector Quantized Covariance index | 10 bits | data2 (10..19)| [0..1023] index in covariance codebook |
| **Opacity** | Splat opacity value | 8 bits | data2 (20..27)| [0..255] mapped to [0.0 .. 1.0] |
| **Flags** | Layers / Dithering flags | 4 bits | data2 (28..31)| Bitflags |

### 32-Bit Word Alignment (GPU-friendly)

- **data0 (uint32)**: `[Position Y (16b)] [Position X (16b)]`
- **data1 (uint32)**: `[Normal V (8b)] [Normal U (8b)] [Position Z (16b)]`
- **data2 (uint32)**: `[Flags (4b)] [Opacity (8b)] [Covar Index (10b)] [Color Index (10b)]`

### GPU Decompression
In the fragment and vertex shaders, VQ indices are resolved using a single lookup into a small, fast 1D texture or UBO storing the color and anisotropy codebooks.

This layout achieves a **25% VRAM footprint reduction** compared to the 16-byte format, allowing FoveaEngine to render larger scenes within identical VRAM limits.
