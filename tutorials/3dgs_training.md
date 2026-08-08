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

For native serialization and experimental runtime testing, convert your `.ply` file into a compressed binary `.fovea` asset. Validate performance on your target renderer and hardware; this conversion is not a frame-rate guarantee.

### Using the Godot Editor UI
1. Select the public `FoveaSplat3D` node in the Scene tree.
2. Set `source_path` to the `.ply` asset you want to convert and wait for it to load.
3. In the **Fovea Actions** inspector section, click **Convert to .fovea**.
4. The editor writes a `.fovea` file next to the source file, using the same base name.
5. FoveaEngine writes the native asset with:
   - a color palette of up to 256 entries;
   - a covariance codebook of up to 1024 entries;
   - Morton spatial ordering and quantized positions within the asset bounds.

Coplanar merging is a separate experimental runtime option; it is not part of this export step.

### Using GDScript Programmatically
```gdscript
var splat := FoveaSplat3D.new()
add_child(splat)
splat.source_path = "res://reconstructions/input.ply"
await get_tree().process_frame

if not splat.export_to_fovea("res://reconstructions/output.fovea"):
	push_error("Fovea export failed")
```

---

## 3. Editing with the SplatBrush (VR Sculpting & Cleaning)

FoveaEngine includes an interactive real-time editor to clean floaters, shape volume geometry, and paint physical flow currents.

### Editor Setup
1. Open the scene `res://addons/foveacore/scenes/splat_brush_playground.tscn`.
2. Ensure you have your VR headset connected via OpenXR (e.g., Quest, Vive) or use the Desktop fallback camera.
3. Select the public `FoveaSplat3D` node you wish to edit.

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
Treat brush and clay-deformer output as experimental. Keep a copy of the source asset, verify the result visually, then export a new `.fovea` asset through the Fovea inspector action when the target renderer supports the path.
