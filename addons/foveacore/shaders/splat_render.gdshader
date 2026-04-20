shader_type spatial;

// ============================================================================
// FoveaEngine : splat_render.gdshader
// Rendu GPU final des Gaussian Splats avec Anisotropie et Fovéation
// ============================================================================

// Optimisations extrêmes pour VR : Pas d'ombres, pas de culling, blending additif ou alpha
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_prepass_alpha;

// Inclusion de notre librairie mathématique (Assurez-vous que le chemin est correct)
#include "res://addons/foveacore/shaders/splat_math.gdshaderinc"

// Paramètres de bounding box pour la dé-quantisation (à envoyer via ShaderMaterial)
uniform vec3 aabb_min;
uniform vec3 aabb_max;

// Codebook Texture (2xK, FORMAT_RGBAF) pour la Vector Quantization
uniform sampler2D covar_texture;

// Paramètres de Fovéation (Eye Tracking / Zone Culling)
global uniform vec2 fovea_gaze_left;  // Centre du regard œil gauche (0..1)
global uniform vec2 fovea_gaze_right; // Centre du regard œil droit (0..1)
uniform float fovea_inner_radius = 0.3;    // Zone 100%
uniform float fovea_outer_radius = 0.6;    // Zone 50% (Au-delà = 25%)

// Données transmises du Vertex au Fragment
varying flat vec3 v_color;
varying flat float v_opacity;
varying vec2 v_uv;         // Déplacement en pixels depuis le centre
varying flat vec3 v_conic; // Covariance inverse (cov22, cov12, cov11)

void vertex() {
    // --- 1. DÉCODAGE DES 16 OCTETS (Spatial & Vector Quantization) ---
    uint data0 = floatBitsToUint(INSTANCE_CUSTOM.x);
    uint data1 = floatBitsToUint(INSTANCE_CUSTOM.y);
    uint data2 = floatBitsToUint(INSTANCE_CUSTOM.z);
    uint data3 = floatBitsToUint(INSTANCE_CUSTOM.w);

    // Extraction de la position 3D quantifiée
    uint qx = data0 & 0xFFFFu;
    uint qy = (data0 >> 16) & 0xFFFFu;
    uint qz = data1 & 0xFFFFu;
    vec3 q_pos = vec3(float(qx), float(qy), float(qz)) / 65535.0;
    vec3 world_pos = aabb_min + q_pos * (aabb_max - aabb_min);

    // Extraction de la couleur (RGB565 -> RGB standard)
    uint color_index = data2 & 0xFFFFu;
    float r = float((color_index >> 11) & 0x1Fu) / 31.0;
    float g = float((color_index >> 5) & 0x3Fu)  / 63.0;
    float b = float(color_index & 0x1Fu)         / 31.0;
    v_color = vec3(r, g, b);

    // Extraction de l'opacité
    v_opacity = float(data3 & 0xFFu) / 255.0;

    // --- 2. CALCUL DE LA COVARIANCE (Anisotropie / Ellipses via Codebook) ---
    uint covar_index = (data2 >> 16) & 0xFFFFu; // Les 16 bits supérieurs
    
    // Lecture du codebook dans la texture (Largeur 2, Hauteur = nb de clusters)
    ivec2 tex_size = textureSize(covar_texture, 0);
    float tex_v = (float(covar_index) + 0.5) / float(max(tex_size.y, 1)); // Échantillonage au centre du pixel
    
    // tex0 contient [scale.x, scale.y, scale.z, rot.w]
    vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v), 0.0); 
    // tex1 contient [rot.x, rot.y, rot.z, padding]
    vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v), 0.0);
    
    vec3 scale = tex0.xyz;
    vec4 rot = vec4(tex0.w, tex1.x, tex1.y, tex1.z); // Reconstruction du Quaternion

    mat3 cov3d = compute_cov3d(scale, rot);
    vec3 center_cam = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
    vec3 cov2d = compute_cov2d(center_cam, cov3d, PROJECTION_MATRIX, VIEWPORT_SIZE);

    float det = (cov2d.x * cov2d.z) - (cov2d.y * cov2d.y);
    float inv_det = 1.0 / max(det, 0.0000001);
    v_conic = vec3(cov2d.z, -cov2d.y, cov2d.x) * inv_det;

    // --- 3. DIMENSIONNEMENT ET ALIGNEMENT DU QUAD ---
    float radius_x = ceil(3.0 * sqrt(cov2d.x));
    float radius_y = ceil(3.0 * sqrt(cov2d.z));
    vec2 pixel_extent = vec2(radius_x, radius_y);

    vec2 ndc_offset = pixel_extent / VIEWPORT_SIZE;
    vec4 clip_pos = PROJECTION_MATRIX * vec4(center_cam, 1.0);
    clip_pos.xy += VERTEX.xy * ndc_offset * clip_pos.w * 2.0;

    // --- 4. FOVEATED RENDERING (Culling géométrique par densité) ---
    vec2 ndc_pos = clip_pos.xy / clip_pos.w;
    vec2 aspect_uv = ndc_pos * 0.5 + 0.5;
    aspect_uv.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y; // Correction de ratio
    
    // Multiview VR : VIEW_INDEX 0 = Gauche, 1 = Droite
    vec2 aspect_gaze = (VIEW_INDEX == 0) ? fovea_gaze_left : fovea_gaze_right;
    aspect_gaze.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
    
    float dist_to_gaze = distance(aspect_uv, aspect_gaze);
    float random_val = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
    
    // Élimination pseudo-aléatoire des splats en fonction de l'éloignement du regard
    if (dist_to_gaze > fovea_outer_radius && random_val > 0.25) {
        POSITION = vec4(0.0); // 75% de splats en moins en périphérie !
    } else if (dist_to_gaze > fovea_inner_radius && random_val > 0.50) {
        POSITION = vec4(0.0); // 50% de splats en moins en zone intermédiaire
    } else {
        // Optimisation VR : Hidden Area Mask (HAM) Culling
        // Les lentilles sont rondes, on élimine mathématiquement les coins "morts" de l'écran carré.
        // ndc_pos.xy va de -1.0 à 1.0. Une distance > 1.25 (ajustable selon le casque) est invisible.
        if (length(ndc_pos.xy) > 1.25) {
            POSITION = vec4(0.0);
        } else {
            POSITION = clip_pos;
            v_uv = VERTEX.xy * pixel_extent;
        }
    }
}

void fragment() {
    float power = -0.5 * (v_conic.x * v_uv.x * v_uv.x + v_conic.z * v_uv.y * v_uv.y) - v_conic.y * v_uv.x * v_uv.y;
    if (power > 0.0) discard;
    float alpha = exp(power) * v_opacity;
    if (alpha < 0.02) discard;

    ALBEDO = v_color;
    ALPHA = alpha;
}