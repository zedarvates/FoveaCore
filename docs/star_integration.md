# InSpatio-World STAR-Lite Integration

FoveaEngine now includes a fast monocular reconstruction path inspired by the **InSpatio-World** STAR (Spatiotemporal Autoregressive) architecture. This approach allows for near-instant 3D object generation from monocular "studio-style" videos without the heavy processing time of COLMAP.

## 🚀 Key Features

### 1. DA3 Depth Bridge (`star_bridge.py`)
- Interfaces with **Depth-Anything-3** for sub-centimetric depth estimation.
- Generates 16-bit specialized depth maps anchored to a 4D workspace.
- Exports `star_metadata.json` for seamless Godot import.

### 2. STAR Proxy Shader
- Implements **Parallax Mapping** using DA3 depth maps.
- Dynamically deforms the proxy quad based on head tracking in VR.
- Maintains spatial consistency using a causal temporal anchor.

### 3. Advanced ROI Painting
- New "Paint & Eraser" UI for selecting the region of interest.
- High-precision mask-to-coordinate mapping.

## 🛠️ Usage

### Fast Monocular Path
1. Open the **StudioTo3D** panel in Godot.
2. Select a video on a white background.
3. Enable the **`use_fast_sync`** option.
4. Click **Run**.
5. The engine will skip COLMAP and use the **STAR Bridge** to generate a depth-aware interactive proxy.

### Simulation Mode
If you do not have the DA3 weights installed, you can use the **STAR Simulator** to test the VR logic:
```bash
python addons/foveacore/scripts/reconstruction/star_simulator.py --target res://my_test_reconstruction
```

## ⚠️ Requirements
- **Python Environment**: Requires `torch`, `cv2`, `numpy`.
- **InSpatio Models**: For full quality, ensure `depth_anything_3` weights are available in your path.
