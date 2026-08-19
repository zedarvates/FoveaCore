shader_type spatial;

// ============================================================================
// FoveaEngine : splat_render_triangle_palette.gdshader
// Rendu GPU des Gaussian Splats avec palette de couleurs indexée (8-bit)
// Optimisation : palette partagée + dithering pour réduire le banding
// ============================================================================

// Optimisations extrêmes pour VR : Pas d'ombres, pas de culling, blending additif ou alpha
render_mode cull_disabled, blend_mix, depth_draw_never, depth_prepass_alpha;

// Inclusion de notre librairie mathématique
#include "res://addons/foveacore/shaders/splat_math.gdshaderinc"

// Paramètres de bounding box pour la dé-quantisation
uniform vec3 aabb_min;
uniform vec3 aabb_max;

// Codebook Texture (2xK, FORMAT_RGBAF) pour la Vector Quantization (covariance)
uniform sampler2D covar_texture;
uniform bool covar_scale_is_linear = false;

// Palette verticale 1×N (FORMAT_RGBA8), matching setup_palette().
uniform sampler2D palette_texture : filter_nearest, repeat_disable;
uniform int palette_size = 256;
uniform bool use_palette = true; // Uniforme de compatibilite

// Paramètres de Fovéation (Eye Tracking / Zone Culling)
global uniform vec2 fovea_gaze_left;  // Centre du regard œil gauche (0..1)
global uniform vec2 fovea_gaze_right; // Centre du regard œil droit (0..1)
uniform float fovea_inner_radius = 0.3;    // Zone 100%
uniform float fovea_outer_radius = 0.6;    // Zone 50% (Au-delà = 25%)

// Nombre de segments pour l'ellipse (doit correspondre à la génération CPU)
uniform int splat_subdivisions = 16;

// Activer/désactiver le dithering Floyd-Steinberg
uniform bool use_dithering = true;
uniform float dither_strength = 1.0;

// Layered Splatting toggle
uniform bool enable_foveated_rendering = false;
uniform bool enable_layered_splatting = true;

// Surface Waves (Dynamic, Repeating & Looping)
uniform bool  enable_waves          = false;
uniform float wave_speed            = 1.0;
uniform float wave_amplitude        = 0.2;
uniform float wave_frequency        = 0.5;
uniform float wave_tiling_size      = 10.0;
uniform float wave_loop_period      = 4.0;

// Dynamic Specular Highlights
uniform vec3  light_direction     = vec3(0.0, -1.0, 0.0);
uniform float specular_strength   = 0.5;
uniform float specular_shininess  = 32.0;

// Données transmises du Vertex au Fragment
varying flat vec3 v_color;        // Couleur interpolée (RGB)
varying flat float v_opacity;     // Opacité
varying flat int v_palette_index; // Index dans la palette (0-255)
varying vec2 v_uv;                // UV du vertex (0..1)
varying vec3 v_local_pos;         // Position locale dans le splat
varying vec3 v_conic;             // Covariance inverse
varying vec2 v_screen_pos;        // Position écran pour dithering
varying float v_specular;

void vertex() {
    v_specular = 0.0;
    // --- 1. DÉCODAGE DES 16 OCTETS (Spatial & Vector Quantization) ---
    uint data0 = floatBitsToUint(INSTANCE_CUSTOM.x);
    uint data1 = floatBitsToUint(INSTANCE_CUSTOM.y);
    uint data2 = floatBitsToUint(INSTANCE_CUSTOM.z);
    uint data3 = floatBitsToUint(INSTANCE_CUSTOM.w);

    // Position de l'instance/splat dans le monde via MODEL_MATRIX
    vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

    // Extraction de l'index de palette (8 bits) au lieu de RGB565
    v_palette_index = int(data2 & 0xFFu);
    
    // Extraction de l'opacité (8 bits)
    v_opacity = float(data3 & 0xFFu) / 255.0;
    
    // Extraction du type de couche (layer_type)
    uint layer_type = (data3 >> 8u) & 0xFFu;

    // --- 2. CALCUL DE LA COVARIANCE (Anisotropie via Codebook) ---
    uint covar_index = (data2 >> 16u) & 0xFFFFu;
    
    ivec2 tex_size = textureSize(covar_texture, 0);
    float tex_v = (float(covar_index) + 0.5) / float(max(tex_size.y, 1));
    
    vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v), 0.0); 
    vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v), 0.0);
    
    vec3 scale = tex0.xyz;
    vec4 rot = vec4(tex0.w, tex1.x, tex1.y, tex1.z);
    
    mat3 cov3d = covar_scale_is_linear
        ? compute_cov3d_linear(scale, rot)
        : compute_cov3d(scale, rot);
    
    // Transformer la covariance de l'espace local à l'espace vue (inclut rotation/échelle d'instance)
    mat3 MV = mat3(MODELVIEW_MATRIX);
    cov3d = MV * cov3d * transpose(MV);
    
    vec3 wave_offset = vec3(0.0);
    if (enable_waves) {
        float looped_time = mod(TIME, wave_loop_period);
        float tiled_x = mod(world_pos.x, wave_tiling_size);
        float tiled_z = mod(world_pos.z, wave_tiling_size);
        float wave_angle = (tiled_x + tiled_z) * wave_frequency + (looped_time * wave_speed * (2.0 * PI / wave_loop_period));
        wave_offset.y = sin(wave_angle) * wave_amplitude;
    }
    
    vec3 center_cam = (MODELVIEW_MATRIX * vec4(wave_offset, 1.0)).xyz;
    vec3 cov2d = compute_cov2d(center_cam, cov3d, PROJECTION_MATRIX, VIEWPORT_SIZE);
    
    float det = (cov2d.x * cov2d.z) - (cov2d.y * cov2d.y);
    float inv_det = 1.0 / max(det, 0.0000001);
    v_conic = vec3(cov2d.z, -cov2d.y, cov2d.x) * inv_det;

    // --- 3. TRANSFORMATION DU MAILLAGE TRIANGLE ---
    float a = cov2d.x;
    float b = cov2d.y;
    float c = cov2d.z;
    
    float trace = a + c;
    float det_cov = det;
    float sqrt_term = sqrt(max(trace * trace * 0.25 - det_cov, 0.0));
    float lambda1 = trace * 0.5 + sqrt_term;
    float lambda2 = trace * 0.5 - sqrt_term;
    
    // Rayons de l'ellipse (3 sigma = 99.7% de la distribution)
    float radius1 = 3.0 * sqrt(max(lambda1, 0.0));
    float radius2 = 3.0 * sqrt(max(lambda2, 0.0));
    
    // Angle de rotation de l'ellipse
    float cos_2theta = (a - c) / max(trace, 0.0001);
    float sin_2theta = (2.0 * b) / max(trace, 0.0001);
    float theta = atan(sin_2theta, cos_2theta) * 0.5;
    
    float cos_t = cos(theta);
    float sin_t = sin(theta);
    
    // Calcul de la distance au regard basée sur le centre du splat
    vec4 center_clip = PROJECTION_MATRIX * vec4(center_cam, 1.0);
    vec2 center_ndc = center_clip.xy / center_clip.w;
    vec2 aspect_uv = center_ndc * 0.5 + 0.5;
    aspect_uv.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
    
    vec2 aspect_gaze = (VIEW_INDEX == 0) ? fovea_gaze_left : fovea_gaze_right;
    aspect_gaze.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
    
    float dist_to_gaze = distance(aspect_uv, aspect_gaze);
    bool is_in_focus = !enable_foveated_rendering || dist_to_gaze <= fovea_inner_radius;
    
    // Dynamic Foveated Layer Weight Calculation
    float layer_weight = 1.0;
    if (enable_foveated_rendering && enable_layered_splatting) {
        if (layer_type == 0u) {
            layer_weight = is_in_focus ? 0.8 : 0.3;
        } else if (layer_type == 1u) {
            layer_weight = is_in_focus ? 1.0 : 0.0;
        } else if (layer_type == 2u) {
            layer_weight = is_in_focus ? 1.2 : 0.1;
        } else if (layer_type == 3u) {
            layer_weight = is_in_focus ? 1.0 : 0.0;
        } else {
            layer_weight = is_in_focus ? 0.8 : 0.3;
        }
        
        v_opacity *= layer_weight;
        
        // Étirement du rayon pour masquer les trous
        float scale_factor = 1.0 + (dist_to_gaze / fovea_inner_radius);
        radius1 *= scale_factor;
        radius2 *= scale_factor;
    }
    
    vec2 local_pos = VERTEX.xy;
    vec2 scaled = vec2(local_pos.x * radius1, local_pos.y * radius2);
    vec2 rotated = vec2(
        scaled.x * cos_t - scaled.y * sin_t,
        scaled.x * sin_t + scaled.y * cos_t
    );
    
    vec2 pixel_extent = vec2(radius1, radius2);
    vec2 ndc_offset = (rotated) / VIEWPORT_SIZE * 2.0;
    
    // --- 4. FOVEATED RENDERING ---
    vec4 clip_pos = PROJECTION_MATRIX * vec4(center_cam, 1.0);
    clip_pos.xy += ndc_offset * clip_pos.w;
    
    v_screen_pos = clip_pos.xy / clip_pos.w;  // Pour dithering
    
    vec2 ndc_pos = clip_pos.xy / clip_pos.w;
    float random_val = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
    
    if (layer_weight <= 0.01) {
        POSITION = vec4(0.0);
    } else if (enable_foveated_rendering && dist_to_gaze > fovea_outer_radius && random_val > 0.25) {
        POSITION = vec4(0.0);
    } else if (enable_foveated_rendering && dist_to_gaze > fovea_inner_radius && random_val > 0.50) {
        POSITION = vec4(0.0);
    } else {
        if (length(ndc_pos) > 1.25) {
            POSITION = vec4(0.0);
        } else {
            POSITION = clip_pos;
            v_uv = local_pos * 0.5 + 0.5;
            v_local_pos = vec3(rotated / pixel_extent, 0.0);
            
            vec3 splat_normal = vec3(
                2.0 * (rot.y * rot.w + rot.x * rot.z),
                2.0 * (rot.z * rot.w - rot.x * rot.y),
                1.0 - 2.0 * (rot.y * rot.y + rot.z * rot.z)
            );
            NORMAL = (VIEW_MATRIX * vec4(normalize(splat_normal), 0.0)).xyz;
            
            // Dynamic specular reflections per-splat/per-vertex
            vec3 V = -normalize(center_cam);
            vec3 L_view = (VIEW_MATRIX * vec4(-normalize(light_direction), 0.0)).xyz;
            vec3 H = normalize(V + L_view);
            vec3 N = normalize(NORMAL);
            float NdotH = clamp(dot(N, H), 0.0, 1.0);
            v_specular = pow(NdotH, specular_shininess) * specular_strength;
        }
    }
}

// Fonction de dithering Floyd-Steinberg
float apply_floyd_steinberg_dither(vec2 pixel_pos, float intensity) {
    if (!use_dithering) return intensity;
    
    // Crée un motif de dithering basé sur la position écran
    // Utilise un motif Bayer 4x4 pour un dithering régulier
    vec2 dither_coord = floor(pixel_pos / 4.0);
    float dither_pattern = fract(
        sin(dot(dither_coord, vec2(12.9898, 78.233))) * 43758.5453
    );
    
    // Ajoute du bruit proportionnel à la force du dithering
    float dither_noise = (dither_pattern - 0.5) * 0.08 * dither_strength;
    
    // Applique aussi un motif spatial pour réduire le banding
    vec2 wave = sin(pixel_pos.xy * 0.05 + vec2(0.0, 1.0)) * 0.02;
    dither_noise += wave.x * wave.y * dither_strength;
    
    return clamp(intensity + dither_noise, 0.0, 1.0);
}

void fragment() {
    // Calcul simplifié: on utilise la distance au centre pour l'alpha
    float dist_sq = dot(v_local_pos.xy, v_local_pos.xy);
    
    if (dist_sq > 1.05) {
        discard;
    }
    
    // Falloff doux
    float alpha = smoothstep(1.0, 0.85, dist_sq) * v_opacity;
    
    if (alpha < 0.01) {
        discard;
    }
    
    // --- RÉCUPÉRATION DE LA COULEUR DE LA PALETTE ---
    float palette_v = (float(v_palette_index) + 0.5) / float(max(palette_size, 1));
    vec2 palette_uv = vec2(0.5, palette_v);
    
    vec3 color_from_palette = texture(palette_texture, palette_uv).rgb;
    
    // Applique le dithering pour réduire le banding
    float dither_factor = apply_floyd_steinberg_dither(FRAGCOORD.xy, 1.0);
    
    // Légère variation de couleur pour casser les bandes
    vec3 dithered_color = color_from_palette * dither_factor;
    
    // Gamma correction
    dithered_color = pow(dithered_color, vec3(2.2));
    
    ALBEDO = dithered_color;
    ALPHA = alpha;
    EMISSION = dithered_color * 0.01 + vec3(v_specular);
    
    // Dithering sur l'alpha aussi pour les bords transparents
    ALPHA = apply_floyd_steinberg_dither(FRAGCOORD.xy, alpha);
}

void light() {
    // Éclairage diffus Lambertien standard
    float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    DIFFUSE_LIGHT += LIGHT_COLOR * NdotL * ATTENUATION;
    
    // Brillance spéculaire de surface Blinn-Phong soft
    vec3 H = normalize(VIEW + LIGHT);
    float NdotH = clamp(dot(NORMAL, H), 0.0, 1.0);
    float specular = pow(NdotH, 16.0) * 0.15;
    SPECULAR_LIGHT += LIGHT_COLOR * specular * ATTENUATION;
}
