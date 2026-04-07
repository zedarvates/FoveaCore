# FoveaCore — Phase 4: Advanced Features Implementation Plan

## Overview

This phase aims to push the boundaries of FoveaEngine by integrating state-of-the-art VR rendering techniques, AI-driven style transfer, and advanced spatial interaction tools.

## 1. Advanced Architecture

```mermaid
graph TD
    subgraph VR Interaction
        GZ[OpenXR Gaze Tracker]
        PH[Hybrid Physics Engine]
        SB["SplatBrush (Cleaning/Nettoyage)"]
    end

    subgraph Advanced Rendering
        LF[LoRA Inference Factory]
        DF[Dynamic Foveation Control]
        IS[Instance Segmentation (MOS)]
    end

    GZ --> DF
    SB --> IS
    PH --> IS
    DF --> LF
    LF --> IS
```

## 2. Key Modules to Implement

### 2.1 SplatBrushEngine (GDScript / Tool)

- **Functions:**
  - `brush_paint(position: Vector3, radius: float, mode: ERASE|DENSITY|COLOR)`
  - `isolate_cluster(threshold: float)`
  - `spatial_denoiser()`

### 2.2 FoveaPhysicsLinker (Node3D)

- **Functions:**
  - `generate_collision_from_lowpoly(mesh: Mesh)`
  - `bind_splats_to_body(rigid_body: RigidBody3D)`

### 2.3 GazeTrackerLinker (OpenXR)

- **Functions:**
  - `update_gaze_from_xr(eye_data: Dictionary)`
  - `feed_foveated_renderer(point: Vector3)`

### 2.4 LoRABridge (AI Extension)

- **Functions:**
  - `load_onnx_lora(model_path: String)`
  - `apply_style_to_textures(base_texture: Texture2D)`

## 3. Immediate Implementation Tasks

- [x] Create `addons/foveacore/scripts/advanced/` directory.
- [x] Implement `splat_brush_engine.gd` for in-editor splat manipulation.
- [x] Implement `gaze_tracker_linker.gd` for OpenXR eye-tracking support.
- [x] Implement `physics_proxy_generator.gd` for hybrid interaction.
- [x] Update `plugin.gd` to register these new components.
- [x] Implement `neural_style_bridge.gd` for LoRA/ONNX support.
- [x] Implement `layered_foveated_renderer.gd` (Digital Painting Optimization).
- [x] Implement `layered_splat_generator.gd` (Saturation/Light/Shadow extraction).

## 4. Performance Goals

- < 1ms overhead for Eye-tracking.
- Support for > 1M points in the SplatBrush editor.
- Consistent collision physics with < 5% error vs visual volume.
