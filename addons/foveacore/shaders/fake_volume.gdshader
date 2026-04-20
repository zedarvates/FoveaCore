shader_type spatial;

// ============================================================================
// FoveaEngine : fake_volume.gdshader
// Simule un volume 3D (Gaussian) sur un simple Quad 2D (Billboard)
// ============================================================================

// Mode non-éclairé pour correspondre à l'esthétique des splats, avec transparence
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled;

uniform sampler2D proxy_texture : source_color;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float radius = 0.5; // Rayon UV (0.0 à 1.0)
uniform float falloff = 4.0; // Dureté du bord du volume
uniform float depth_scale = 0.5; // Intensité de la fausse profondeur (Parallax)

void vertex() {
    // Effet Billboard (Sphérique) : Le quad fait toujours parfaitement face à la caméra VR
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
    vec2 uv_centered = UV - vec2(0.5);
    float dist = length(uv_centered) / radius;
    
    // Cloche gaussienne parfaite pour l'opacité
    float alpha = exp(-dist * dist * falloff);
    
    if (dist > 1.0 || alpha < 0.02) {
        discard; // On jette les coins du Quad pour économiser le GPU
    }
    
    vec4 tex = texture(proxy_texture, UV);
    ALBEDO = base_color.rgb * tex.rgb;
    ALPHA = alpha * tex.a * base_color.a;
    
    // Simulation de profondeur (Fake Volume) :
    // On pousse le pixel légèrement vers l'arrière en fonction de sa distance au centre.
    // Cela donne l'illusion que le Quad est une sphère 3D !
    DEPTH = FRAGCOORD.z + (dist * depth_scale * FRAGCOORD.w);
}