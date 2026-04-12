# Minimal VR Test Scene for Fake Volume Shader

This document describes a simple VR test setup to evaluate the perceptual impact of the **Fake Volume** shader (Gaussian splat on a quad) within the Godot engine.

## Scene Setup

1. **Root Node**: `Spatial` (or `XRNode` for XR rigs)
   - Represents the VR camera rig.
2. **Child Node**: `CameraRig` (or `VRControllerNode` as needed)
   - Handles stereoscopic rendering.
3. **Child Node**: `MeshInstance3D` named `FakeVolumeQuad`
   - Holds a `QuadMesh` (single quad) positioned at the origin.
   - Assign a `ShaderMaterial` using the `fake_volume_shader.gdshader` shader.
4. **Optional**: Add a `WorldEnvironment` node with a simple skybox or environment to provide visual context.

## Shader Material Setup

- Create a new `ShaderMaterial` resource.
- Set the shader to the content of `fake_volume_shader.gdshader` (see below).
- Assign a **1×1 white texture** to the `splat_texture` uniform (or use a pre‑baked Gaussian kernel).
- Adjust `radius` and `falloff` uniforms to fine‑tune the apparent volume.

## Shader Code (fake_volume_shader.gdshader)

```gdshader
shader_type canvas_item;

// Uniforms
uniform sampler2D splat_texture : hint_albedo;
uniform vec4 splat_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float radius = 0.5; // radius in UV space (0‑1)
uniform float falloff = 2.0; // exponent for Gaussian falloff

void fragment() {
    // UV centered at (0.5, 0.5)
    vec2 uv_centered = UV - vec2(0.5);
    float dist = length(uv_centered) / radius;
    // Gaussian falloff (exp(-dist^2 * falloff))
    float alpha = exp(-dist * dist * falloff);
    // Sample texture (optional, can be a white 1x1 for pure Gaussian)
    vec4 tex = texture(splat_texture, UV);
    COLOR = splat_color * tex * alpha;
    // Discard fragments outside radius for performance
    if (dist > 1.0) {
        discard;
    }
}
```

## Testing Procedure

1. **Run the Scene in VR Mode**
   - Launch the Godot project with VR support enabled (e.g., OpenXR, OpenVR, or OpenXR‑based plugin).
   - Ensure the `Spatial` node is set as the root and that the VR device is detected.

2. **Observe the Quad**
   - Position the `FakeVolumeQuad` a short distance in front of the camera (e.g., `z = -2` in world space).
   - Move the VR head around to view the quad from different angles.

3. **Perceptual Evaluation**
   - **Depth Illusion**: Determine whether the flat quad appears to have noticeable depth or volume.
   - **Smoothness**: Check for Gaussian falloff smoothness; adjust `falloff` if the edges look too harsh or too soft.
   - **Performance**: Monitor FPS to ensure the shader remains lightweight.

4. **Collect Feedback**
   - Record user impressions (e.g., “feels like a blob”, “hard to judge distance”, “looks natural”).
   - Note any visual artifacts (e.g., flickering, edge aliasing).

5. **Iterate**
   - Based on feedback, tweak `radius`, `falloff`, or `splat_color` to improve the illusion.
   - Consider adding simple lighting (e.g., a basic `LIGHT` node) to test fake shading effects.

## Integration Checklist

- [ ] Add `FakeVolumeQuad` to the VR scene hierarchy.
- [ ] Assign the `ShaderMaterial` with the fake volume shader.
- [ ] Provide a texture to `splat_texture` uniform.
- [ ] Adjust `radius` and `falloff` for desired visual effect.
- [ ] Run VR test and collect perceptual feedback.
- [ ] Document results and next steps in the project roadmap.
