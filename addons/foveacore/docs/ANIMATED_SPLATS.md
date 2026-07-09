# Animated Splats — FoveaEngine Phase 7

## Architecture

The animation subsystem has three layers:

### CPU Layer (scripts/animation/)
8 animator nodes that modify splat data per-frame:
- `FoveaAnimationSubsystem` — orchestrator
- `FoveaFlowFieldAnimator` — curl-noise flow
- `FoveaMorphCovarianceAnimator` — PULSE/BREATHE/WOBBLE
- `FoveaMaterialOscillation` — color/opacity animation
- `FoveaLodStretchAnimator` — distance-based stretch
- `FoveaFlipbookAnimator` — multi-frame playback
- `FoveaNeuralOffsetField` — 3D grid of offsets
- `FoveaBoneSkinAnimation` — LBS skinning

### GPU Layer (shaders/)
3 compute shaders:
- `splat_animate.glsl` — basic flow + stretch
- `splat_animate_advanced.glsl` — morph + flipbook + neural
- `cloth_simulation.glsl` — Verlet cloth

### Pipeline (gpu_culler_pipeline.gd)
Extended with animation passes that run before culling:
1. Base animation → animated buffer
2. Advanced animation (morph/flipbook/neural)
3. Cloth simulation
4. Skinning

## Data3 Layout
| Bits | Field |
|------|-------|
| 0-7  | opacity |
| 8-15 | layer_id |
| 16   | anim_active |
| 17-23 | anim_flags |
| 24-31 | padding |

## Performance Budget (target)
| Pass | 1M splats | 500K splats |
|------|-----------|-------------|
| Basic animate | <0.1ms | <0.05ms |
| Advanced | <0.2ms | <0.1ms |
| Cloth | <0.3ms | <0.15ms |
| Skinning | <0.3ms | <0.15ms |
