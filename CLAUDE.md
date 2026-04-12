# CLAUDE.md - FoveaEngine Development Guide

## Build & Test Commands
- **GDExtension**: `scons target=template_debug platform=windows` (if source available)
- **Godot Project**: Open in Godot 4.6.2 Stable
- **Test Scene**: `godot --scene res://test/fovea_test_scene.tscn`
- **Reconstruction Tools**:
  - `python addons/foveacore/scripts/reconstruction/star_bridge.py`: Monocular bridge.
  - `python addons/foveacore/scripts/reconstruction/star_simulator.py`: Logic simulator.

## External Dependencies
- **FFmpeg**: Required for frame extraction. Path set in Project Settings.
- **COLMAP**: Required for SfM path (Standard).
- **InSpatio-World**: Required for Fast Path (DA3/STAR).
- **Depth-Anything-3**: Model weights for precise monocular depth.

## Code Style & Architecture
- **GDScript**: Use 4.x features (typed arrays, lambdas). Avoid chaining void methods.
- **C++/GDExtension**: Core performance logic (Splat sorting, Foveation).
- **StudioTo3D**: Modular pipeline (Extraction -> Geometry -> Training).
- **STAR Architecture**: Causal temporal cache + DA3 Depth Maps for 4D consistency.

## Git Workflow
- Keep commits focused on specific features/fixes.
- Use `rtk` for optimized token usage during commit/push operations.
