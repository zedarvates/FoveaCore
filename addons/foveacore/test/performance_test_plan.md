# Performance Test Plan for Proxy Reconstruction

## Overview
This document outlines the performance testing methodology for the Proxy Reconstruction system in FoveaCore. The goal is to validate the +40-60% FPS gain target on dense scenes.

## Test Environment
- **Hardware**: Quest 3 / PC VR (test both)
- **Godot Version**: 4.x
- **Scene**: Dense forest / urban environment

## Test Scenarios

### 1. Baseline Measurement
- Measure FPS with full 3D reconstruction (no proxies)
- Record: Average FPS, frame time, GPU usage

### 2. Proxy Mode Tests
| Distance | Foveation Level | Expected Density | Target FPS |
|----------|-----------------|-------------------|------------|
| 0-2m     | Any             | 100%              | Baseline   |
| 2-5m     | Low (1)         | 70%               | +20%       |
| 5-10m    | Med (2)         | 50%               | +40%       |
| 10m+     | High (3)        | 30%               | +60%       |

### 3. Metrics to Track
- **FPS**: Frames per second (target: 72+ on Quest, 90+ on PC)
- **Frame Time**: ms per frame (target: <13.8ms for 72fps)
- **GPU Time**: Rendering time in ms
- **Draw Calls**: Number of draw calls (proxy should reduce this)
- **Triangle Count**: Triangles rendered per frame

### 4. Test Procedure
1. Start with baseline scene (no proxies)
2. Enable proxy mode at increasing distances
3. Measure FPS with FPS counter
4. Compare results against baseline

### 5. Expected Results
- **Near (0-2m)**: No difference (full quality)
- **Mid (2-5m)**: 15-25% FPS improvement
- **Far (5-10m)**: 30-45% FPS improvement  
- **Very Far (10m+)**: 50-60% FPS improvement

### 6. Verification Checklist
- [ ] Proxy mesh renders correctly at all distances
- [ ] No visual artifacts or flickering
- [ ] Smooth transitions between proxy/original
- [ ] Foveation level changes work correctly
- [ ] Style effects (outline, grain) render properly
- [ ] Shadow projection visible and correct

## Notes
- Test on actual hardware (Quest 3) for accurate results
- Use Godot's built-in profiler for detailed metrics
- Run tests multiple times and average results