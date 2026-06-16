# FoveaEngine — Architecture Overview

This document describes the end-to-end architecture of FoveaEngine, showing how a source video is processed, reconstructed into 3D Gaussian Splats, and rendered in real-time with foveated and hybrid rendering techniques.

---

## 🗺️ Pipeline Architecture Diagram

The diagram below represents the complete data flow from the raw video recording to the final HMD/VR display:

```mermaid
graph TD
    %% Reconstruction Pipeline
    subgraph Reconstruction Pipeline (StudioTo3D)
        A["Source Video (.mp4/.mkv/.webm)"] --> B["StudioProcessor (FFmpeg + Blur Filter)"]
        B --> C["DatasetExporter (Frames & Masks)"]
        C --> D{"Reconstruction Pathway"}
        D -- "Standard SfM (COLMAP)" --> E["ReconstructionBackend (COLMAP SfM)"]
        D -- "Fast Path (STAR)" --> F["ReconstructionBackend (STAR-Lite Python)"]
        D -- "Feed-Forward (WorldMirror 2.0)" --> G["ReconstructionBackend (WorldMirror 2.0 Inference)"]
        E --> H["3DGS Training (train.py)"]
        F --> H
        H --> I["PLY Output (point_cloud.ply)"]
        G --> I
    end

    %% Asset Registration & Setup
    I --> J["PLYLoader (Binary/ASCII Parser)"]
    J --> K["FoveaSplattable (Scene Node3D)"]
    
    %% Runtime Rendering & Culling Pipeline
    subgraph Runtime Rendering Pipeline
        K --> L["SurfaceExtractor (Visible-face Extractor)"]
        L --> M["SplatGenerator (Barycentric Sampler)"]
        M --> N["FoveatedController / EyeCuller (Frustum Culling)"]
        N --> O["OcclusionCuller (Hi-Z Depth pass)"]
        O --> P["SplatSorter (GPU Bitonic Sort)"]
        P --> Q["SplatRenderer / HybridRenderer (MultiMeshInstance3D)"]
    end

    %% Display
    Q --> R["VR Viewport / HMD Display"]

    %% Styling and Customizations
    S["StyleEngine (FBM / Worley Noise / Materials)"] -.-> M
```

---

## 🔍 Component Descriptions

### 1. Reconstruction Pipeline (StudioTo3D)

*   **Source Video**: The input video capture of an object or scene (turntable or hand-held pan).
*   **StudioProcessor**: Invokes **FFmpeg** to extract frames at target framerates. Computes a Laplacian variance blur score to automatically drop blurry frames.
*   **DatasetExporter**: Formats the extracted frames, generates white/chroma masks, creates `.gdignore` to prevent Godot from import-blocking large frame datasets, and writes session metadata JSON.
*   **Reconstruction Pathways**:
    *   *COLMAP*: Traditional Structure-from-Motion (SfM) reconstructing camera poses and sparse points.
    *   *STAR*: Monocular depth-based geometry syncing (DA3) for fast geometry retrieval.
    *   *WorldMirror 2.0*: A feed-forward, neural-network-driven reconstruction path that produces a `.ply` file in a single step.
*   **3DGS Training**: Python-based training script (`train.py`) optimized to run over the sparse points to output a fully-fledged 3D Gaussian Splat PLY.

### 2. Loading & Scene Tree Setup

*   **PLYLoader**: Parses ASCII or Binary little-endian PLY files. Properly maps quaternion rotations (`rot_0..3` w-first order to Godot `x, y, z, w` order) and extracts spherical harmonics (`f_dc_0/1/2`) or raw color RGB (uchar/float).
*   **FoveaSplattable**: The Node3D editor/runtime component. Animates, segments, or updates splat configurations, and manages the lifecycle of the underlying splat resources.

### 3. Runtime Rendering & Culling

*   **SurfaceExtractor**: Extracts polygonal surface coordinates to establish spatial density constraints.
*   **SplatGenerator**: Places splats onto the extracted surfaces using barycentric coordinate sampling.
*   **FoveatedController / EyeCuller**: Implements frustum culling. Updates planes and checks AABBs to prevent off-screen splats from consuming GPU resources.
*   **OcclusionCuller**: Utilizes depth buffer rendering to discard occluded splats before rasterization.
*   **SplatSorter**: Computes depth coordinates and runs a GPU Bitonic Sort Compute Shader (or O(N) spatial clustering fallback) to ensure correct alpha-blending order (back-to-front).
*   **SplatRenderer / HybridRenderer**: Renders splats via GPU instancing using `MultiMeshInstance3D` for optimal performance (90+ FPS in VR), or falls back to low-poly mesh rendering.
