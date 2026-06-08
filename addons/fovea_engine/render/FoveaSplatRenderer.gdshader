shader_type spatial;

// ============================================================================
// Fovea Engine : FoveaSplatRenderer.gdshader
// GPU rendering of Gaussian Splats with high-performance TRIANGLE mesh
// Optimized to reduce fragment shader costs and overdraw.
// ============================================================================

render_mode cull_disabled, blend_mix, depth_draw_never, depth_prepass_alpha;

#include "res://addons/foveacore/shaders/splat_math.gdshaderinc"

uniform vec3 aabb_min;
uniform vec3 aabb_max;
uniform sampler2D covar_texture;
uniform sampler2D palette_texture;
uniform bool use_palette = false;
uniform int palette_size = 16;

global uniform vec2 fovea_gaze_left;  
global uniform vec2 fovea_gaze_right; 
uniform float fovea_inner_radius = 0.3;    
uniform float fovea_outer_radius = 0.6;    

uniform int splat_subdivisions = 16;
uniform float lod_ratio = 1.0;

uniform vec2  motion_dir_screen     = vec2(0.0);
uniform float motion_stretch_factor = 0.0;

varying flat vec3 v_color;
varying flat float v_opacity;
varying vec2 v_uv;         
varying vec3 v_local_pos;  
varying flat vec3 v_conic; 

void vertex() {
    uint data0 = floatBitsToUint(INSTANCE_CUSTOM.x);
    uint data1 = floatBitsToUint(INSTANCE_CUSTOM.y);
    uint data2 = floatBitsToUint(INSTANCE_CUSTOM.z);
    uint data3 = floatBitsToUint(INSTANCE_CUSTOM.w);

    vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

    uint color_index = data2 & 0xFFFFu;
    if (use_palette) {
        uint palette_idx = data2 & 0xFFu;
        float tex_v = (float(palette_idx) + 0.5) / float(max(palette_size, 1));
        vec4 pal_color = textureLod(palette_texture, vec2(0.5, tex_v), 0.0);
        v_color = pal_color.rgb;
    } else {
        float r = float((color_index >> 11u) & 0x1Fu) / 31.0;
        float g = float((color_index >> 5u) & 0x3Fu)  / 63.0;
        float b = float(color_index & 0x1Fu)         / 31.0;
        v_color = vec3(r, g, b);
    }

    v_opacity = float(data3 & 0xFFu) / 255.0;

    uint covar_index = (data2 >> 16u) & 0xFFFFu;
    
    ivec2 tex_size = textureSize(covar_texture, 0);
    float tex_v = (float(covar_index) + 0.5) / float(max(tex_size.y, 1));
    
    vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v), 0.0); 
    vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v), 0.0);
    
    vec3 scale = tex0.xyz;
    vec4 rot = vec4(tex0.w, tex1.x, tex1.y, tex1.z);
    
    mat3 cov3d = compute_cov3d(scale, rot);
    
    mat3 MV = mat3(MODELVIEW_MATRIX);
    cov3d = MV * cov3d * transpose(MV);
    
    vec3 center_cam = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    vec3 cov2d = compute_cov2d(center_cam, cov3d, PROJECTION_MATRIX, VIEWPORT_SIZE);
    
    float det = (cov2d.x * cov2d.z) - (cov2d.y * cov2d.y);
    float inv_det = 1.0 / max(det, 0.0000001);
    v_conic = vec3(cov2d.z, -cov2d.y, cov2d.x) * inv_det;

    float a = cov2d.x;
    float b = cov2d.y;
    float c = cov2d.z;
    
    float trace = a + c;
    float det_cov = det;
    float sqrt_term = sqrt(max(trace * trace * 0.25 - det_cov, 0.0));
    float lambda1 = trace * 0.5 + sqrt_term;  
    float lambda2 = trace * 0.5 - sqrt_term;  
    
    float radius1 = 3.0 * sqrt(max(lambda1, 0.0));
    float radius2 = 3.0 * sqrt(max(lambda2, 0.0));
    
    float cos_2theta = (a - c) / max(trace, 0.0001);
    float sin_2theta = (2.0 * b) / max(trace, 0.0001);
    float theta = atan(sin_2theta, cos_2theta) * 0.5;
    
    float cos_t = cos(theta);
    float sin_t = sin(theta);
    
    vec2 local_pos = VERTEX.xy;  
    
    vec2 scaled = vec2(local_pos.x * radius1, local_pos.y * radius2);
    vec2 rotated = vec2(
        scaled.x * cos_t - scaled.y * sin_t,
        scaled.x * sin_t + scaled.y * cos_t
    );
    
    if (motion_stretch_factor > 0.0 && length(motion_dir_screen) > 0.001) {
        float proj_on_motion = dot(local_pos, motion_dir_screen);
        rotated += motion_dir_screen * proj_on_motion * motion_stretch_factor * max(radius1, radius2);
    }
    
    vec2 pixel_extent = vec2(radius1, radius2);
    vec2 ndc_offset = (rotated) / VIEWPORT_SIZE * 2.0;
    
    vec4 clip_pos = PROJECTION_MATRIX * vec4(center_cam, 1.0);
    clip_pos.xy += ndc_offset * clip_pos.w;
    
    vec2 ndc_pos = clip_pos.xy / clip_pos.w;
    vec2 aspect_uv = ndc_pos * 0.5 + 0.5;
    aspect_uv.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
    
    vec2 aspect_gaze = (VIEW_INDEX == 0) ? fovea_gaze_left : fovea_gaze_right;
    aspect_gaze.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
    
    float dist_to_gaze = distance(aspect_uv, aspect_gaze);
    float random_val = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
    
    if (random_val > lod_ratio) {
        POSITION = vec4(0.0);
    } else if (dist_to_gaze > fovea_outer_radius && random_val > 0.25) {
        POSITION = vec4(0.0);
    } else if (dist_to_gaze > fovea_inner_radius && random_val > 0.50) {
        POSITION = vec4(0.0);
    } else {
        if (length(ndc_pos) > 1.25) {
            POSITION = vec4(0.0);
        } else {
            POSITION = clip_pos;
            v_uv = local_pos * 0.5 + 0.5;  
            v_local_pos = vec3(rotated, 0.0);
            
            vec3 splat_normal = vec3(
                2.0 * (rot.y * rot.w + rot.x * rot.z),
                2.0 * (rot.z * rot.w - rot.x * rot.y),
                1.0 - 2.0 * (rot.y * rot.y + rot.z * rot.z)
            );
            NORMAL = (VIEW_MATRIX * vec4(normalize(splat_normal), 0.0)).xyz;
        }
    }
}

void fragment() {
    vec2 d = v_local_pos.xy;

    float power = -0.5 * (v_conic.x * d.x * d.x
                        + 2.0 * v_conic.y * d.x * d.y
                        + v_conic.z * d.y * d.y);

    if (power > 0.0) {
        discard;
    }

    float gaussian_alpha = exp(power);
    float alpha = min(0.99, v_opacity * gaussian_alpha);

    if (alpha < 0.004) {
        discard;
    }

    ALBEDO    = v_color;
    ALPHA     = alpha;
    EMISSION  = v_color * 0.01;
}

void light() {
    float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    DIFFUSE_LIGHT += LIGHT_COLOR * NdotL * ATTENUATION;
    
    vec3 H = normalize(VIEW + LIGHT);
    float NdotH = clamp(dot(NORMAL, H), 0.0, 1.0);
    float specular = pow(NdotH, 16.0) * 0.15;
    SPECULAR_LIGHT += LIGHT_COLOR * specular * ATTENUATION;
}
