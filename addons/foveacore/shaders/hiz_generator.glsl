#[compute]
#version 450

// ============================================================================
// FoveaEngine : hiz_generator.glsl
// Génération de la pyramide Hi-Z (mipmap de profondeur conservative) sur le GPU.
// ============================================================================

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D src_tex;
layout(set = 0, binding = 1, image2D) uniform writeonly image2D dest_tex;

layout(push_constant) uniform Params {
    vec2 src_pixel_size; // 1.0 / resolution_source
} params;

void main() {
    ivec2 dest_coords = ivec2(gl_GlobalInvocationID.xy);
    ivec2 dest_size = imageSize(dest_tex);
    if (dest_coords.x >= dest_size.x || dest_coords.y >= dest_size.y) return;

    // Calcul des UVs du centre de la cellule 2x2 correspondante
    vec2 src_uv = (vec2(dest_coords) * 2.0 + 1.0) * params.src_pixel_size;
    
    // Échantillonner de manière conservative (MAX de profondeur pour le standard-Z)
    float d0 = textureLod(src_tex, src_uv + vec2(-0.5, -0.5) * params.src_pixel_size, 0.0).r;
    float d1 = textureLod(src_tex, src_uv + vec2(0.5, -0.5) * params.src_pixel_size, 0.0).r;
    float d2 = textureLod(src_tex, src_uv + vec2(-0.5, 0.5) * params.src_pixel_size, 0.0).r;
    float d3 = textureLod(src_tex, src_uv + vec2(0.5, 0.5) * params.src_pixel_size, 0.0).r;
    
    float max_depth = max(max(d0, d1), max(d2, d3));
    
    imageStore(dest_tex, dest_coords, vec4(max_depth, 0.0, 0.0, 1.0));
}
