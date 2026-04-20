shader_type canvas_item;

// Uniforms
uniform sampler2D splat_texture : hint_albedo;
uniform vec4 splat_color : hint_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float radius = 0.5; // radius in UV space (0‑1)
uniform float falloff = 2.0; // exponent for Gaussian falloff

// NEW: Style parameters for enrichment
uniform float outline_thickness = 0.0; // in UV units
uniform vec4 outline_color = vec4(0.0, 0.0, 0.0, 1.0); // black outline
uniform float grain_intensity = 0.0; // 0‑1
uniform int style_mode = 0; // 0 = none, 1 = outline, 2 = grain, 3 = both
// NEW: Shadow projection parameters
uniform float shadow_strength = 0.3; // Strength of projected shadows (0‑1)
uniform float shadow_blur = 0.02;    // Blur radius for soft shadows
uniform float depth_bias = 0.001;    // Offset to prevent shadow acne
uniform bool use_shadow_projection = true; // Enable/disable shadow projection

void fragment() {
    // UV centered at (0.5, 0.5)
    vec2 uv_centered = UV - vec2(0.5);
    float dist = length(uv_centered) / radius;
    // Gaussian falloff (exp(-dist^2 * falloff))
    float alpha = exp(-dist * dist * falloff);
    
    // Sample texture (optional, can be a white 1x1 for pure Gaussian)
    vec4 tex = texture(splat_texture, UV);
    vec4 base_color = splat_color * tex * alpha;
    
    // Discard fragments outside radius for performance
    if (dist > 1.0) {
        discard;
    }
    
    // APPLY STYLE ENRICHMENTS
    // Outline: sample neighboring pixels and create edge effect
    if (outline_thickness > 0.0) {
        vec3 outline = vec3(0.0);
        float outline_alpha = 0.0;
        for (float dx = -outline_thickness; dx <= outline_thickness; float dx += 0.5) {
            for (float dy = -outline_thickness; dy <= outline_thickness; float dy += 0.5) {
                vec2 sample_uv = UV + vec2(dx, dy);
                vec4 sample_tex = texture(splat_texture, sample_uv);
                float sample_dist = length(sample_uv - vec2(0.5)) / radius;
                float sample_alpha = exp(-sample_dist * sample_dist * falloff);
                vec4 sample_color = splat_color * sample_tex * sample_alpha;
                // If neighbor is transparent but current is not, it's an edge
                if (sample_alpha < 0.1 && alpha > 0.1) {
                    outline += sample_color.rgb;
                    outline_alpha += 1.0;
                }
            }
        }
        if (outline_alpha > 0.0) {
            outline /= outline_alpha;
            base_color.rgb = mix(base_color.rgb, outline, 0.3);
        }
    }
    
    // Grain: add subtle noise
    if (grain_intensity > 0.0) {
        // Simple noise based on UV and time (Godot provides TIME)
        float noise = sin(UV.x * 100.0 + TIME * 0.5) * 0.5 + 0.5;
        float grain = mix(0.0, noise * grain_intensity, 0.5);
        base_color.rgb += grain;
    }
    
    // SHADOW PROJECTION: Create fake projected shadows based on splat depth
    if (use_shadow_projection && shadow_strength > 0.0) {
        // Calculate shadow intensity based on depth (closer to center = stronger shadow)
        float shadow_intensity = (1.0 - dist) * shadow_strength;
        shadow_intensity = clamp(shadow_intensity, 0.0, shadow_strength);
        
        // Apply soft shadow blur by sampling neighboring pixels
        if (shadow_blur > 0.0) {
            vec3 shadow_sum = vec3(0.0);
            float shadow_count = 0.0;
            for (float dx = -shadow_blur; dx <= shadow_blur; float dx += 0.5) {
                for (float dy = -shadow_blur; dy <= shadow_blur; float dy += 0.5) {
                    vec2 sample_uv = UV + vec2(dx, dy);
                    vec2 sample_centered = sample_uv - vec2(0.5);
                    float sample_dist = length(sample_centered) / radius;
                    if (sample_dist <= 1.0) {
                        float sample_alpha = exp(-sample_dist * sample_dist * falloff);
                        float sample_shadow = (1.0 - sample_dist) * shadow_strength;
                        sample_shadow = clamp(sample_shadow, 0.0, shadow_strength);
                        shadow_sum += vec3(sample_shadow);
                        shadow_count += 1.0;
                    }
                }
            }
            if (shadow_count > 0.0) {
                shadow_intensity = shadow_sum.x / shadow_count; // Average shadow intensity
            }
        }
        
        // Apply shadow to darken the color
        base_color.rgb *= (1.0 - shadow_intensity);
    }
    
    COLOR = base_color;
}