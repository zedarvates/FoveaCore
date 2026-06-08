# 🎓 3DGS Training, Baking, & SplatBrush Guide — FoveaEngine

This guide covers offline training of 3D Gaussian Splats, conversion into the optimized `.fovea` binary format, and VR sculpting/cleaning using the **SplatBrush** editor.

---

## 1. Traditional Offline 3DGS Training

When feed-forward neural reconstruction (WorldMirror 2.0 / DVLT) is not used, you can train a Gaussian Splat model using traditional SfM points.

### Prerequisites
- Install [NVIDIA CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit).
- Clone the reference 3DGS training repository:
  ```bash
  git clone --recursive https://github.com/graphdeco-inria/gaussian-splatting
  cd gaussian-splatting
  conda env create --file environment.yml
  conda activate gaussian_splatting
  ```

### Training Pipeline Steps
1. **Prepare Images**: Place your images in a folder named `input/`.
2. **Compute Camera Poses**: Run COLMAP structure from motion:
   ```bash
   python convert.py -s <path_to_input_folder>
   ```
3. **Train the Splat Model**: Run the optimization (typically 7,000 iterations is sufficient for FoveaEngine):
   ```bash
   python train.py -s <path_to_input_folder> --iterations 7000
   ```
4. **Locate the Output**: The trained PLY file is saved at:
   `output/<session_id>/point_cloud/iteration_7000/point_cloud.ply`

---

## 2. Baking & Optimizing to `.fovea` Format

To run the assets at 90+ FPS in VR, convert your `.ply` file into a compressed binary `.fovea` asset:

### Using the Godot Editor UI
1. Select the `FoveaSplattable` node in the Scene tree.
2. In the inspector, locate the **Export Options**.
3. Under **Target Path**, specify `res://reconstructions/my_model.fovea`.
4. Click the **Export to .fovea** button.
5. FoveaEngine will run the fast-path optimizer (Rust GDExtension) in the background to perform:
   - NaN/Inf removal.
   - 1024-cluster covariance Vector Quantization.
   - 8-bit index color quantization.
   - Spatial grid relative quantization (16-bit).
   - Coplanar splat merging (reducing overlapping overdraw).

### Using GDScript Programmatically
```gdscript
var asset_loader = FoveaAssetLoader.new()
# Converts and quantizes in a background thread
asset_loader.convert_ply_to_fovea("res://reconstructions/input.ply", "res://reconstructions/output.fovea")
```

---

## 3. Editing with the SplatBrush (VR Sculpting & Cleaning)

FoveaEngine includes an interactive real-time editor to clean floaters, shape volume geometry, and paint physical flow currents.

### Editor Setup
1. Open the scene `res://addons/foveacore/scenes/splat_brush_playground.tscn`.
2. Ensure you have your VR headset connected via OpenXR (e.g., Quest, Vive) or use the Desktop fallback camera.
3. Select the `FoveaSplattable` node you wish to edit.

### Brush Modes
Using the VR controllers (or mouse on desktop):

1. **`ERASE` Mode**:
   - Deletes splats within the brush sphere. Use this to clean "floaters" or background noise left over by reconstruction.
2. **`DENSITY` Mode**:
   - Clones or duplicates splats to fill in sparse or empty areas.
3. **`COLOR` Mode**:
   - Modulates the RGB values of splats.
4. **`FLOW` Mode (Water & Particle Physics)**:
   - Paints directional vectors onto the splats. These vectors are read by `water_splat_particle.gdshader` to direct real-time fluid advection, simulating localized water currents flowing over objects.

### Saving Edits
All deformations done via `FoveaClayDeformer` or the brush engine are non-destructive and can be saved back to the `.fovea` resource by clicking **Save Splat Modifications** in the inspector.
