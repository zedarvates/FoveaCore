# 👁️ FoveaEngine — Advanced 3DGS & Neural Reconstruction Engine

Welcome to **FoveaEngine**, a cutting-edge reconstruction and rendering pipeline for Godot 4.6+, specifically designed for high-fidelity VR experiences and artistic "Digital Painting" aesthetics.

---

## 🚀 Key Features

### 🎥 StudioTo3D Pipeline
An automated end-to-end workflow to transform studio videos into game-ready assets.
- **Automated Masking**: Chroma (Green/Blue/White) and Luma keying for subject isolation.
- **SfM & 3DGS Integration**: Direct bridge to COLMAP and Gaussian Splatting training.
- **Hybrid Export**: Generates both high-fidelity Splat layers and low-poly Mesh proxies for physics.

### 🎨 Layered Foveated Splatting
The engine doesn't just render points; it renders **artistic layers**.
- **Layers**: BASE, SATURATION, LIGHT, SHADOW.
- **Foveated Optimization**: Integration with OpenXR Eye-Tracking to render complexity only where the user looks.
- **Digital Painting Aesthetic**: Splats stack like glazes, creating a unique hand-painted look.

### ⚡ Advanced Interaction & Physics
- **SplatBrush Engine**: In-editor tool to sculpt, clean, and recolor splat clouds.
- **PhysicsProxy**: Automatic generation of collision hulls linked to splat visuals.
- **Soft Matter & Liquids**: Real-time deformation of splats (push/bounce) and stylized liquid swirls (Manga style water).

### ☀️ Dynamic Real-time Lighting
- **Lighting Animation**: Shadow splats that move with scene lights.
- **Specular Highlights**: Dynamic opacity modulation based on light direction.
- **Hierarchical Splatting**: Macro-splats for flat colors and micro-splats for high-detail areas (MIP-Splatting).

### 🖌️ Textured Stamp Rendering
- **Beyond Gaussians**: Support for alpha-textured stamps (Sponge, Stone, Dry Brush, Stipple, Hatching).
- **Roughness Analysis**: Automatic brush selection based on surface normal variance.

---

## 📂 Project Structure

- `addons/foveacore/`: The core plugin and scripts.
- `plans/`: Detailed architecture, implementation, and advanced feature documents.
- `scripts/reconstruction/`: The StudioTo3D backend and UI.
- `scripts/advanced/`: High-end rendering and interaction controllers.

---

## 🛠️ Usage

1. **Install Plugin**: Enable `FoveaCore` in Godot project settings.
2. **Reconstruction**: Open the `StudioTo3D` panel in the bottom dock.
3. **Rendering**: Use the `FoveaSplattable` node to display your results.
4. **Optimization**: Add the `EyeTrackingBridge` and `LayeredFoveatedController` to your scene.

---

## 📈 Roadmap (Completed Phases)

- [x] **Phase 1**: Core GS Rendering & Ply Loader.
- [x] **Phase 2**: StudioTo3D Automation & Masking.
- [x] **Phase 3**: SplatBrush & Foveated Logic.
- [x] **Phase 4**: Physical Interactions, Dynamic Lighting, and Hierarchical Splatting.
- [ ] **Phase 5**: Algorithmic Optimization & Advanced Tooling (Ongoing).
    - **Compute Shaders**: Interaction/Lighting logic to GPU.
    - **Splat Compression**: Custom format (~70% reduction).
    - **Splat Decals**: Environmental weathering spray tool.
    - **Multiplayer Sync**: Shared VR physical interactions.

- [ ] **Pending & Validation**:
    - [ ] **Eye-Tracking Connectivity**: Finalize runtime link with specific VR headsets (Quest Pro/Vision Pro).
    - [ ] **Hardware Validation**: Complete end-to-end test on real XR equipment via OpenXR.
    - [ ] **GitHub Update**: Refresh documentation after hardware verification.

---

## 🛡️ License

FoveaEngine is released under the **MIT License**. Created by the FoveaEngine Team for the next generation of VR developers.
