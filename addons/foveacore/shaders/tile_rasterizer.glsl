#[compute]
#version 450

// ============================================================================
// FoveaEngine : tile_rasterizer.glsl
// Rendu GPU par tuiles d'écran (16x16) via Compute Shader.
// ============================================================================

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

struct PackedSplat {
    uint data0; // pos_x (16 bits), pos_y (16 bits)
    uint data1; // pos_z (16 bits), norm_u (8 bits), norm_v (8 bits)
    uint data2; // color_index RGB565 (16 bits), covar_index (16 bits)
    uint data3; // opacity (8 bits), layer_id (8 bits), padding (16 bits)
};

// Set 0 - Bindings
layout(set = 0, binding = 0, std430) restrict readonly buffer InputSplats {
    PackedSplat splats[];
};

layout(set = 0, binding = 1) uniform sampler2D covar_texture;
layout(set = 0, binding = 2) uniform sampler2D palette_texture;
layout(set = 0, binding = 3, rgba8) uniform writeonly image2D dest_image;

// Compteur atomique pour savoir combien ont survécu au culling
layout(set = 0, binding = 4, std430) restrict readonly buffer CounterBuffer {
    uint valid_splat_count;
};

// Push Constants
layout(push_constant, std430) uniform Params {
    mat4 model_view_matrix;
    mat4 projection_matrix;
    vec3 camera_position;
    uint total_splats; // Gardé pour la compatibilité d'alignement push constants
    vec3 aabb_min;
    float pad1;
    vec3 aabb_max;
    float pad2;
    uint use_palette;
    uint palette_size;
} params;

// Mémoire partagée de la tuile (256 threads)
shared uint shared_splat_indices[256];
shared uint shared_splat_count;

// Math helper - projection 3D -> 2D
mat3 compute_cov3d_local(vec3 scale, vec4 rot) {
    mat3 S = mat3(0.0);
    S[0][0] = exp(scale.x);
    S[1][1] = exp(scale.y);
    S[2][2] = exp(scale.z);
    
    float r = rot.x, x = rot.y, y = rot.z, z = rot.w;
    mat3 R;
    R[0] = vec3(1.0 - 2.0 * (y*y + z*z), 2.0 * (x*y - r*z),       2.0 * (x*z + r*y));
    R[1] = vec3(2.0 * (x*y + r*z),       1.0 - 2.0 * (x*x + z*z), 2.0 * (y*z - r*x));
    R[2] = vec3(2.0 * (x*z - r*y),       2.0 * (y*z + r*x),       1.0 - 2.0 * (x*x + y*y));
    
    mat3 M = R * S;
    return M * transpose(M);
}

vec3 compute_cov2d_local(vec3 center_cam, mat3 cov3d, mat4 proj_matrix, vec2 viewport_size) {
    float t = clamp(center_cam.z, -1000.0, -0.1); // Z négatif devant la caméra
    
    float focal_x = proj_matrix[0][0] * viewport_size.x * 0.5;
    float focal_y = proj_matrix[1][1] * viewport_size.y * 0.5;
    
    mat3 J;
    J[0] = vec3(focal_x / t, 0.0,         -(focal_x * center_cam.x) / (t * t));
    J[1] = vec3(0.0,         -focal_y / t, (focal_y * center_cam.y) / (t * t));
    J[2] = vec3(0.0,         0.0,         0.0);
    
    mat3 T = J;
    mat3 cov2d_mat = transpose(T) * cov3d * T;
    
    float cov11 = cov2d_mat[0][0] + 0.3;
    float cov12 = cov2d_mat[0][1];
    float cov22 = cov2d_mat[1][1] + 0.3;
    
    return vec3(cov11, cov12, cov22);
}

void main() {
    ivec2 pixel_coords = ivec2(gl_GlobalInvocationID.xy);
    ivec2 dest_size = imageSize(dest_image);
    vec2 viewport_size = vec2(dest_size);
    
    // Bounds de la tuile 16x16 courante
    ivec2 tile_id = ivec2(gl_WorkGroupID.xy);
    vec2 tile_min = vec2(tile_id * 16);
    vec2 tile_max = tile_min + vec2(16.0);
    
    // Couleur finale accumulée
    vec4 final_color = vec4(0.0);
    
    uint splat_limit = min(valid_splat_count, 65536u);
    uint thread_idx = gl_LocalInvocationIndex; // 0..255
    
    // Initialiser le compteur partagé
    if (thread_idx == 0) {
        shared_splat_count = 0;
    }
    barrier();
    
    // Traiter les splats en chunks de 256
    for (uint chunk_offset = 0; chunk_offset < splat_limit; chunk_offset += 256) {
        uint splat_idx = chunk_offset + thread_idx;
        
        bool overlaps_tile = false;
        
        if (splat_idx < splat_limit) {
            PackedSplat s = splats[splat_idx];
            
            // Décoder position spatiale
            uint qx = s.data0 & 0xFFFFu;
            uint qy = (s.data0 >> 16) & 0xFFFFu;
            uint qz = s.data1 & 0xFFFFu;
            
            vec3 q_pos = vec3(float(qx), float(qy), float(qz)) / 65535.0;
            vec3 world_pos = params.aabb_min + q_pos * (params.aabb_max - params.aabb_min);
            
            // Projeter dans l'espace caméra
            vec4 cam_pos = params.model_view_matrix * vec4(world_pos, 1.0);
            
            if (cam_pos.z < -0.1) {
                // Covariance 3D et 2D
                uint covar_index = (s.data2 >> 16) & 0xFFFFu;
                ivec2 tex_size = textureSize(covar_texture, 0);
                float tex_v = (float(covar_index) + 0.5) / float(max(tex_size.y, 1));
                vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v), 0.0);
                vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v), 0.0);
                
                vec3 scale = tex0.xyz;
                vec4 rot = vec4(tex0.w, tex1.x, tex1.y, tex1.z);
                
                mat3 cov3d = compute_cov3d_local(scale, rot);
                mat3 MV = mat3(params.model_view_matrix);
                cov3d = MV * cov3d * transpose(MV);
                
                vec3 cov2d = compute_cov2d_local(cam_pos.xyz, cov3d, params.projection_matrix, viewport_size);
                
                // Centre en espace écran
                vec4 clip_pos = params.projection_matrix * cam_pos;
                vec2 ndc_pos = clip_pos.xy / clip_pos.w;
                vec2 screen_pos = (ndc_pos * 0.5 + 0.5) * viewport_size;
                
                // Calcul du rayon de l'ellipse
                float trace = cov2d.x + cov2d.z;
                float det = (cov2d.x * cov2d.z) - (cov2d.y * cov2d.y);
                float sqrt_term = sqrt(max(trace * trace * 0.25 - det, 0.0));
                float radius = 3.0 * sqrt(max(trace * 0.5 + sqrt_term, 0.0));
                
                vec2 splat_min = screen_pos - vec2(radius);
                vec2 splat_max = screen_pos + vec2(radius);
                
                if (splat_max.x >= tile_min.x && splat_min.x <= tile_max.x &&
                    splat_max.y >= tile_min.y && splat_min.y <= tile_max.y) {
                    overlaps_tile = true;
                }
            }
        }
        
        if (overlaps_tile) {
            uint dest_idx = atomicAdd(shared_splat_count, 1);
            if (dest_idx < 256) {
                shared_splat_indices[dest_idx] = splat_idx;
            }
        }
        
        barrier();
        
        // Blending par pixel
        if (pixel_coords.x < dest_size.x && pixel_coords.y < dest_size.y) {
            uint active_count = min(shared_splat_count, 256u);
            for (uint i = 0; i < active_count; i++) {
                if (final_color.a >= 0.99) break;
                
                uint s_idx = shared_splat_indices[i];
                PackedSplat s = splats[s_idx];
                
                uint qx = s.data0 & 0xFFFFu;
                uint qy = (s.data0 >> 16) & 0xFFFFu;
                uint qz = s.data1 & 0xFFFFu;
                vec3 q_pos = vec3(float(qx), float(qy), float(qz)) / 65535.0;
                vec3 world_pos = params.aabb_min + q_pos * (params.aabb_max - params.aabb_min);
                vec4 cam_pos = params.model_view_matrix * vec4(world_pos, 1.0);
                
                uint covar_index = (s.data2 >> 16) & 0xFFFFu;
                ivec2 tex_size = textureSize(covar_texture, 0);
                float tex_v = (float(covar_index) + 0.5) / float(max(tex_size.y, 1));
                vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v), 0.0);
                vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v), 0.0);
                vec3 scale = tex0.xyz;
                vec4 rot = vec4(tex0.w, tex1.x, tex1.y, tex1.z);
                mat3 cov3d = compute_cov3d_local(scale, rot);
                mat3 MV = mat3(params.model_view_matrix);
                cov3d = MV * cov3d * transpose(MV);
                vec3 cov2d = compute_cov2d_local(cam_pos.xyz, cov3d, params.projection_matrix, viewport_size);
                
                vec4 clip_pos = params.projection_matrix * cam_pos;
                vec2 ndc_pos = clip_pos.xy / clip_pos.w;
                vec2 screen_pos = (ndc_pos * 0.5 + 0.5) * viewport_size;
                
                float det = (cov2d.x * cov2d.z) - (cov2d.y * cov2d.y);
                float inv_det = 1.0 / max(det, 0.0000001);
                vec3 conic = vec3(cov2d.z, -cov2d.y, cov2d.x) * inv_det;
                
                vec2 d = vec2(pixel_coords) - screen_pos;
                float power = -0.5 * (conic.x * d.x * d.x + 2.0 * conic.y * d.x * d.y + conic.z * d.y * d.y);
                
                if (power <= 0.0) {
                    float alpha_gauss = exp(power);
                    float opacity = float(s.data3 & 0xFFu) / 255.0;
                    float alpha = min(0.99, opacity * alpha_gauss);
                    
                    if (alpha >= 0.004) {
                        vec3 color;
                        if (params.use_palette == 1) {
                            uint palette_idx = s.data2 & 0xFFu;
                            float p_v = (float(palette_idx) + 0.5) / float(max(params.palette_size, 1u));
                            color = textureLod(palette_texture, vec2(0.5, p_v), 0.0).rgb;
                        } else {
                            uint color_index = s.data2 & 0xFFFFu;
                            float r = float((color_index >> 11u) & 0x1Fu) / 31.0;
                            float g = float((color_index >> 5u) & 0x3Fu)  / 63.0;
                            float b = float(color_index & 0x1Fu)         / 31.0;
                            color = vec3(r, g, b);
                        }
                        
                        float weight = alpha * (1.0 - final_color.a);
                        final_color.rgb += color * weight;
                        final_color.a += weight;
                    }
                }
            }
        }
        
        barrier();
        
        if (thread_idx == 0) {
            shared_splat_count = 0;
        }
        barrier();
    }
    
    if (pixel_coords.x < dest_size.x && pixel_coords.y < dest_size.y) {
        vec4 bg = vec4(0.0, 0.0, 0.0, 1.0);
        vec4 result = vec4(final_color.rgb + bg.rgb * (1.0 - final_color.a), 1.0);
        imageStore(dest_image, pixel_coords, result);
    }
}
