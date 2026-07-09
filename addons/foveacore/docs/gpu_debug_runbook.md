# GPU Debugging Runbook (item 334)
## FoveaEngine — Developer Reference

### Tools
- **RenderDoc**: Capture single frames, inspect compute shader outputs
- **Vulkan Validation Layers**: Enable with `RenderingDevice.set_external_logger()`
- **GPU Timestamps**: Available in `FoveaStats` panel

### Common Issues
1. **Black screen / no splats rendered**
   - Check compute shader compilation in editor log
   - Verify `uniform_set` bindings match GLSL layout
   - Ensure `animated_buf` is written before culling pass

2. **Animation not visible**
   - Verify `anim_enabled` == 1 in push constants
   - Check `layer_mask` includes the splat's layer
   - Ensure `splat_animate.glsl` dispatch completes before culling

3. **Performance spike**
   - Check GPU timestamps in FoveaStats
   - Reduce workgroups: `ceili(total_splats / 256.0)`
   - Verify no redundant `rd.sync` between compute passes

4. **VRAM leak**
   - Use `rd.get_memory_usage()` to track allocations
   - Verify all buffers freed in `_cleanup_asset_cache()`
