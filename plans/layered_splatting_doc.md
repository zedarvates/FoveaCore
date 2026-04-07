# FoveaCore — Architecture Document Addendum
## Layered Foveated Splatting & StudioTo3D Pipeline

This document details the advanced rendering and reconstruction techniques implemented in FoveaCore to achieve high-fidelity VR performance.

---

### 1. Layered Foveated Splatting (Digital Painting Optimization)

#### 1.1 The Concept
Instead of rendering a monolith point cloud, FoveaCore decomposes objects into layers, mimicking traditional "Glaze" painting techniques. This allows for selective detail injection based on the user's focus.

| Layer Type | Content | Rendering Mode |
| :--- | :--- | :--- |
| **BASE** | Dominant colors and structural hull. | Continuous (Minimum 30% detail in periphery). |
| **SATURATION** | Chromatic accents and color details. | Foveated (Only visible in center 20° gaze). |
| **LIGHT** | Specular highlights, glints, and bloom. | Foveated (High intensity in center). |
| **SHADOW** | Ambient occlusion and deep shadows. | Foveated (Adds contrast and volume in focus). |

#### 1.2 Eye-Tracking Integration
The `EyeTrackingBridge` feeds real-time gaze coordinates to the `LayeredFoveatedController`. The controller dynamically scales the opacity and density of non-base layers.

**Benefits:**
- **Performance:** Reduces active splat count by ~50% in peripheral vision.
- **Aesthetic:** Creates a natural depth-of-field and artistic "focus" effect.
- **Latency:** Fewer draws in the peripheral buffer allow for higher refresh rates.

---

### 2. StudioTo3D Pipeline

#### 2.1 Automated Workflow
The StudioTo3D tool converts studio-captured videos (White/Green/Blue background) into game-ready 3D assets.

1.  **Frame Extraction:** Video is split into frames with automated quality scoring (`ReconstructionMetrics`).
2.  **Chroma/Luma Masking:** Subjects are isolated using advanced keying algorithms in `StudioProcessor`.
3.  **Structure from Motion (SfM):** COLMAP reconstruction yields the sparse point cloud and camera poses.
4.  **Gaussian Training:** 3DGS training uses the generated workspace (`DatasetExporter`).
5.  **Hybrid Export:**
    *   **High-Poly:** Gaussian Splats separated into drawing layers.
    *   **Low-Poly:** Simplified mesh for physics collision and occlusion.

#### 2.2 Hybrid Interaction
The `PhysicsProxyGenerator` bridges the visual splats with the physical world.
- **Visuals:** High-fidelity Gaussian Splats (Layered).
- **Physics:** Low-Poly mesh proxy generated via Vertex Clustering.
- **Sync:** The splats are children of the physics body, ensuring perfect tracking during movement.

---

### 3. Usage Guide

1.  **Reconstruction:** Open the `StudioTo3D` panel in the Godot Editor.
2.  **Cleaning:** Use the `SplatBrush` tool to remove noise or manually paint saturation/light density.
3.  **Deployment:** Drop a `FoveaSplattable` node into your scene and link the reconstruction session.
4.  **Optimization:** Ensure `EyeTrackingBridge` is active to enable layered foveation.
