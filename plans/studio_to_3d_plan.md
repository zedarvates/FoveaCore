# FoveaCore — StudioTo3D Implementation Plan

## Overview

The goal is to create a set of tools within FoveaEngine to automate the conversion of video captured in a controlled "studio" environment (white background) into game-ready 3D assets using a hybrid **Gaussian Splatting + Low-Poly Mesh** approach.

## 1. Pipeline Architecture

```mermaid
graph TD
    subgraph Studio Input
        V[Video Capture]
        C[Calibration/Config]
    end

    subgraph Pre-processing
        FE[Frame Extraction]
        BM[Background Masking]
        QC[Quality Control / Blur Filtering]
    end

    subgraph Reconstruction (External/Tools)
        SFM[SfM - COLMAP/OpenMVG]
        GS[Gaussian Splat Training]
        PM[Photogrammetry - Mesh Extraction]
    end

    subgraph FoveaEngine Integration
        IM[Import Manager]
        LPS[Low-Poly Simplification (QEM)]
        SPR[Splat Renderer Linking]
        PV[StudioTo3D Preview Tool]
    end

    V --> FE
    C --> BM
    FE --> BM
    BM --> QC
    QC --> SFM
    SFM --> GS
    SFM --> PM
    GS --> IM
    PM --> LPS
    LPS --> IM
    IM --> SPR
    IM --> PV
```

## 2. Key Components

### 2.1 StudioProcessor (GDScript)

- **Functions:**
  - `extract_frames(video_path: String, fps_limit: int)`
  - `mask_background(frame: Image, threshold: float)` (Optimized for white backgrounds)
  - `detect_blur(frame: Image) -> float`

### 2.2 ReconstructionManager (GDScript)

- **Functions:**
  - `start_reconstruction(session_name: String)`
  - `export_dataset(target_dir: String)`
  - `call_reconstruction_backend()` (Interfacing with Python/CLI tools)

### 2.3 StudioTo3D Editor Plugin (Godot UI)

- A dedicated panel in the Godot editor to:
  - Select video files.
  - Preview frame extraction.
  - Adjust mask thresholds.
  - Monitor reconstruction progress.
  - Review and export final results (Low-poly + Splats).

## 3. Detailed Tasks

### Phase 1: Tooling UI & Pre-processing (Completed)

- [x] Create `reconstruction` script directory.
- [x] Implement `studio_processor.gd` for basic frame/mask logic.
- [x] Create `studio_to_3d_panel.tscn` for the Editor UI.
- [x] Define `ReconstructionSession` resource to store metadata.

### Phase 2: Mesh & Splat Extraction (Completed)

- [x] Integrate/Bridge with `GaussianSplat` rendering.
- [x] Integrate `DatasetExporter` for 3DGS workspace.
- [x] Connect `MeshSimplifier` (QEM/Clustering) for low-poly.
- [x] Automated point cloud extraction logic.

### Phase 3: Automation & Polish (Completed)

- [x] Integration of external tool execution (COLMAP/3DGS).
- [x] Advanced Chroma Keying (Green/Blue screen support).
- [x] High-performance 3D preview in-editor.
- [x] Dataset quality metrics.

### Phase 4: Creative Rendering & Interaction (Completed)

- [x] SplatBrush implementation for manual editing.
- [x] GazeTracker OpenXR link for foveated optimization.
- [x] PhysicsProxy dynamic generation (Splats + RigidBody link).
- [x] Layered Splat Rendering (Base, Saturation, Light, Shadow).
- [x] Dynamic Lighting Animation (Shadow displacement & Highlights).
- [x] Hierarchical Variable-size Splatting (MIP-Splatting).
- [x] Textured Stamp Splatting (Sponge, Stone, Brushes).
- [x] Soft Matter & Liquid Interaction (Vortex & Elastic deformation).

---

## 4. Phase 5: Algorithmic Optimization & Advanced Tooling (Ongoing)

- [ ] **Migration to Compute Shaders**: Porting interaction/lighting logic to GPU for massive scale.
- [ ] **Entropy Splat Compression**: Developing a custom format to reduce file sizes by ~70%.
- [ ] **Real-Time Splat Decals**: Tool to "spray" environmental effects (moss, rust) on splat objects.
- [ ] **Multiplayer Splat-Sync**: Networking support for shared physical splat interactions.

---

## 5. Pending & High-Priority Validation

- [ ] **Eye-Tracking Connectivity**: Connect the GazeTracker logic to the actual OpenXR eye-tracking runtime (requires specific XR interface setup).
- [ ] **Hardware Validation**: Perform comprehensive end-to-end testing on physical equipment (Quest Pro / Vision Pro).
- [ ] **GitHub Documentation Sync**: Refresh repository README and Wiki after successful hardware verification.

---

## 5. Risks & Mitigations (Resolved)

- **Heavy Processing**: Resolved by background process execution via `ReconstructionBackend`.
- **Masking Quality**: Resolved by multi-mode (Chroma/Luma) keying system.
- **VR Performance**: Resolved by Foveated Layered Rendering and Hierarchical Splatting.
