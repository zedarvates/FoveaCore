shader_type spatial;

// ============================================================================
// FoveaEngine : splat_render_triangle_palette.gdshader
// Rendu GPU des Gaussian Splats avec palette de couleurs indexée (8-bit)
// Optimisation : palette partagée + dithering pour réduire le banding
// ============================================================================

// Optimisations extrêmes pour VR : Pas d'ombres, pas de culling, blending additif ou alpha
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_prepass_alpha;

// Inclusion de notre librairie mathématique
#include "res://addons/foveacore/shaders/splat_math.gdshaderinc"

// Paramètres de bounding box pour la dé-quantisation
uniform vec3 aabb_min;
uniform vec3 aabb_max;

// Codebook Texture (2xK, FORMAT_RGBAF) pour la Vector Quantization (covariance)
uniform sampler2D covar_texture;

// Palette de couleurs (256 couleurs RGB, format RGBA32F)
// Chaque ligne = 16 couleurs, 16 lignes = 256 couleurs
uniform sampler2D color_palette;
uniform int palette_size = 256;

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

// Données transmises du Vertex au Fragment
varying flat vec3 v_color;        // Couleur interpolée (RGB)
varying flat float v_opacity;     // Opacité
varying flat int v_palette_index; // Index dans la palette (0-255)
varying vec2 v_uv;                // UV du vertex (0..1)
varying vec3 v_local_pos;         // Position locale dans le splat
varying vec3 v_conic;             // Covariance inverse
varying vec2 v_screen_pos;        // Position écran pour dithering

void vertex() {
    // --- 1. DÉCODAGE DES 16 OCTETS (Spatial & Vector Quantization) ---
    uint data0 = floatBitsToUint(INSTANCE_CUSTOM.x);
    uint data1 = floatBitsToUint(INSTANCE_CUSTOM.y);
    uint data2 = floatBitsToUint(INSTANCE_CUSTOM.z);
    uint data3 = floatBitsToUint(INSTANCE_CUSTOM.w);

    // Extraction de la position 3D quantifiée (16 bits par axe)
    uint qx = data0 & 0xFFFFu;
    uint qy = (data0 >> 16) & 0xFFFFu;
    uint qz = data1 & 0xFFFFu;
    vec3 q_pos = vec3(float(qx), float(qy), float(qz)) / 65535.0;
    vec3 world_pos = aabb_min + q_pos * (aabb_max - aabb_min);

    // Extraction de l'index de palette (8 bits) au lieu de RGB565
    // L'index est stocké dans les 8 bits de poids faible de data2
    v_palette_index = int(data2 & 0xFFu);
    
    // Extraction de l'opacité (8 bits)
    v_opacity = float((data3 >> 8) & 0xFFu) / 255.0;

    // --- 2. CALCUL DE LA COVARIANCE (Anisotropie via Codebook) ---
    uint covar_index = (data2 >> 16) & 0xFFFFu;
    
    ivec2 tex_size = textureSize(covar_texture, 0);
    float tex_v = (float(covar_index) + 0.5) / float(max(tex_size.y, 1));
    
    vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v), 0.0); 
    vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v), 0.0);
    
    vec3 scale = tex0.xyz;
    vec4 rot = vec4(tex0.w, tex1.x, tex1.y, tex1.z);
    
    mat3 cov3d = compute_cov3d(scale, rot);
    vec3 center_cam = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
    vec3 cov2d = compute_cov2d(center_cam, cov3d, PROJECTION_MATRIX, VIEWPORT_SIZE);
    
    float det = (cov2d.x * cov2d.z) - (cov2d.y * cov2d.y);
    float inv_det = 1.0 / max(det, 0.0000001);
    v_conic = vec3(cov2d.z, -cov2d.y, cov2d.x) * inv_det;

    // --- 3. TRANSFORMATION DU MAILLAGE TRIANGLE ---
    // VERTEX.xy est la position locale dans le cercle unité (-1..1)
    
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
    
    vec2 local_pos = VERTEX.xy;
    
    // Appliquer échelle puis rotation
    vec2 scaled = vec2(local_pos.x * radius1, local_pos.y * radius2);
    vec2 rotated = vec2(
        scaled.x * cos_t - scaled.y * sin_t,
        scaled.x * sin_t + scaled.y * cos_t
    );
    
    // Conversion en offset NDC
    vec2 pixel_extent = vec2(radius1, radius2);
    vec2 ndc_offset = (rotated) / VIEWPORT_SIZE * 2.0;
    
    // --- 4. FOVEATED RENDERING ---
    vec4 clip_pos = PROJECTION_MATRIX * vec4(center_cam, 1.0);
    clip_pos.xy += ndc_offset * clip_pos.w;
    
    v_screen_pos = clip_pos.xy / clip_pos.w;  // Pour dithering
    
    vec2 ndc_pos = clip_pos.xy / clip_pos.w;
    vec2 aspect_uv = ndc_pos * 0.5 + 0.5;
    aspect_uv.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
    
    vec2 aspect_gaze = (VIEW_INDEX == 0) ? fovea_gaze_left : fovea_gaze_right;
    aspect_gaze.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
    
    float dist_to_gaze = distance(aspect_uv, aspect_gaze);
    float random_val = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
    
    if (dist_to_gaze > fovea_outer_radius && random_val > 0.25) {
        POSITION = vec4(0.0);
    } else if (dist_to_gaze > fovea_inner_radius && random_val > 0.50) {
        POSITION = vec4(0.0);
    } else {
        if (length(ndc_pos) > 1.25) {
            POSITION = vec4(0.0);
        } else {
            POSITION = clip_pos;
            v_uv = local_pos * 0.5 + 0.5;
            v_local_pos = vec3(rotated / pixel_extent, 0.0);
        }
    }
}

// Fonction de dithering Floyd-Steinberg
float apply_floyd_steinberg_dither(vec2 screen_pos, float intensity) {
    if (!use_dithering) return intensity;
    
    // Crée un motif de dithering basé sur la position écran
    // Utilise un motif Bayer 4x4 pour un dithering régulier
    vec2 dither_coord = floor(screen_pos * VIEWPORT_SIZE / 4.0);
    float dither_pattern = fract(
        sin(dot(dither_coord, vec2(12.9898, 78.233))) * 43758.5453
    );
    
    // Ajoute du bruit proportionnel à la force du dithering
    float dither_noise = (dither_pattern - 0.5) * 0.08 * dither_strength;
    
    // Applique aussi un motif spatial pour réduire le banding
    vec2 wave = sin(screen_pos.xy * 20.0 + vec2(0.0, 1.0)) * 0.02;
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
    // Convertit l'index de palette (0-255) en coordonnées texture
    // Palette organisée en grille 16x16 (256 couleurs)
    float palette_x = float(v_palette_index % 16);
    float palette_y = float(v_palette_index / 16);
    vec2 palette_uv = (vec2(palette_x, palette_y) + 0.5) / 16.0;
    
    vec3 color_from_palette = texture(color_palette, palette_uv).rgb;
    
    // Applique le dithering pour réduire le banding
    float dither_factor = apply_floyd_steinberg_dither(v_screen_pos, 1.0);
    
    // Légère variation de couleur pour casser les bandes
    vec3 dithered_color = color_from_palette * dither_factor;
    
    // Gamma correction
    dithered_color = pow(dithered_color, vec3(2.2));
    
    ALBEDO = dithered_color;
    ALPHA = alpha;
    EMISSION = dithered_color * 0.05;
    
    // Dithering sur l'alpha aussi pour les bords transparents
    ALPHA = apply_floyd_steinberg_dither(v_screen_pos, alpha);
}
