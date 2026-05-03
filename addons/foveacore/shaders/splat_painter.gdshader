shader_type spatial;

// ============================================================================
// FoveaEngine : splat_painter.gdshader (VERSION TRIANGLE)
// Shader artistique pour Gaussian Splats avec maillage triangulaire
// Simule des coups de pinceau et texture de toile
// ============================================================================

render_mode unshaded, cull_disabled, depth_draw_always, transparency_alpha_prepass;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float brush_strength : hint_range(0.0, 1.0) = 0.3;
uniform float brush_scale : hint_range(1.0, 50.0) = 10.0;
uniform sampler2D noise_texture : hint_default_white, filter_nearest;
uniform bool enable_brush_strokes : bool = true;
uniform bool enable_canvas_texture : bool = true;
uniform vec2 canvas_tiling : vec2(5.0, 5.0);

// Position locale du vertex dans le splat (pour effets directionnels)
varying vec3 v_local_pos;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    UV = UV;
    
    // Passe la position locale au fragment shader
    v_local_pos = VERTEX.xyz;
}

void fragment() {
    vec4 src_color = base_color * COLOR;

    // Appliquer grain de toile
    if (enable_canvas_texture) {
        vec2 canvas_uv = world_position.xz * canvas_tiling;
        float grain = texture(noise_texture, canvas_uv).r;
        src_color.rgb += (grain - 0.5) * 0.05 * brush_strength;
    }

    // Appliquer coups de pinceau directionnels (basé sur position locale)
    if (enable_brush_strokes) {
        // Utilise la position locale pour créer des stries directionnelles
        float stroke_dir = atan(v_local_pos.y, v_local_pos.x);
        float stroke = sin(v_local_pos.x * brush_scale) 
                     * sin(v_local_pos.y * brush_scale)
                     * sin(v_local_pos.z * brush_scale * 0.5)
                     * cos(stroke_dir * 3.0);
        stroke = stroke * 0.5 + 0.5;
        vec3 stroke_color = mix(src_color.rgb, src_color.rgb * 0.8, stroke * brush_strength);
        src_color.rgb = stroke_color;
    }

    ALBEDO = src_color.rgb;
    ALPHA = src_color.a;
    EMISSION = src_color.rgb * 0.1;
}