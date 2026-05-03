shader_type spatial;

// ============================================================================
// FoveaEngine : splat_render_triangle.gdshader
// Rendu GPU des Gaussian Splats avec maillage TRIANGLE (pas d'ellipse par fragment)
// Optimisation : élimine le calcul de covariance et exp() par fragment
// ============================================================================

// Optimisations extrêmes pour VR : Pas d'ombres, pas de culling, blending additif ou alpha
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_prepass_alpha;

// Inclusion de notre librairie mathématique
#include "res://addons/foveacore/shaders/splat_math.gdshaderinc"

// Paramètres de bounding box pour la dé-quantisation
uniform vec3 aabb_min;
uniform vec3 aabb_max;

// Codebook Texture (2xK, FORMAT_RGBAF) pour la Vector Quantization
uniform sampler2D covar_texture;

// Palette Texture (1D verticale, FORMAT_RGBA8) pour quantification couleur
uniform sampler2D palette_texture;
uniform bool use_palette = false;
uniform int palette_size = 16;

// Paramètres de Fovéation (Eye Tracking / Zone Culling)
global uniform vec2 fovea_gaze_left;  // Centre du regard œil gauche (0..1)
global uniform vec2 fovea_gaze_right; // Centre du regard œil droit (0..1)
uniform float fovea_inner_radius = 0.3;    // Zone 100%
uniform float fovea_outer_radius = 0.6;    // Zone 50% (Au-delà = 25%)

// Nombre de segments pour l'ellipse (doit correspondre à la génération CPU)
uniform int splat_subdivisions = 16;

// Données transmises du Vertex au Fragment
varying flat vec3 v_color;
varying flat float v_opacity;
varying vec2 v_uv;         // UV du vertex (0..1)
varying vec3 v_local_pos;  // Position locale dans le splat (ellipse unité étirée)
varying flat vec3 v_conic; // Covariance inverse (cov22, cov12, cov11) - conservée pour compatibilité

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

    // Extraction de la couleur (palette ou RGB565 selon use_palette)
    uint color_index = data2 & 0xFFFFu;
    if (use_palette) {
        uint palette_idx = data2 & 0xFFu;
        float tex_v = (float(palette_idx) + 0.5) / float(max(palette_size, 1));
        vec4 pal_color = textureLod(palette_texture, vec2(0.5, tex_v), 0.0);
        v_color = pal_color.rgb;
    } else {
        float r = float((color_index >> 11) & 0x1Fu) / 31.0;
        float g = float((color_index >> 5) & 0x3Fu)  / 63.0;
        float b = float(color_index & 0x1Fu)         / 31.0;
        v_color = vec3(r, g, b);
    }

    // Extraction de l'opacité
    v_opacity = float(data3 & 0xFFu) / 255.0;

    // --- 2. CALCUL DE LA COVARIANCE (Anisotropie / Ellipses via Codebook) ---
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
    // Le maillage de base est un cercle unité subdivisé (16 triangles)
    // On étire les sommets via la matrice de transformation de l'ellipse
    
    // VERTEX.xy est la position locale dans le cercle unité (-1..1)
    // On l'utilise pour étirer selon les axes de l'ellipse
    
    // Calcul des axes principaux de l'ellipse via décomposition de Cholesky
    // Cov2D = [[a, b], [b, c]] où a=cov2d.x, b=cov2d.y, c=cov2d.z
    float a = cov2d.x;
    float b = cov2d.y;
    float c = cov2d.z;
    
    // Échelle des axes (racines des valeurs propres approximées)
    // Pour une ellipse x^T * Cov^-1 * x = 1, on utilise la décomposition de Cholesky
    // L = [[L11, 0], [L21, L22]] tel que Cov^-1 = L * L^T
    // Mais on veut la transformation directe: point_local -> point_ellipse
    // On utilise la décomposition de la matrice de covariance elle-même
    
    float trace = a + c;
    float det_cov = det;
    float sqrt_term = sqrt(max(trace * trace * 0.25 - det_cov, 0.0));
    float lambda1 = trace * 0.5 + sqrt_term;  // Valeur propre 1
    float lambda2 = trace * 0.5 - sqrt_term;  // Valeur propre 2
    
    // Rayons de l'ellipse (3 sigma = 99.7% de la distribution)
    float radius1 = 3.0 * sqrt(max(lambda1, 0.0));
    float radius2 = 3.0 * sqrt(max(lambda2, 0.0));
    
    // Angle de rotation de l'ellipse
    float cos_2theta = (a - c) / max(trace, 0.0001);
    float sin_2theta = (2.0 * b) / max(trace, 0.0001);
    float theta = atan(sin_2theta, cos_2theta) * 0.5;
    
    float cos_t = cos(theta);
    float sin_t = sin(theta);
    
    // Matrice de transformation: rotation * échelle
    // On transforme le vertex local (cercle unité) vers l'ellipse
    vec2 local_pos = VERTEX.xy;  // Position dans le maillage triangle (cercle unité)
    
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
            v_uv = local_pos * 0.5 + 0.5;  // UV pour le fragment shader
            v_local_pos = vec3(rotated / pixel_extent, 0.0);  // Normalisé
        }
    }
}

void fragment() {
    // Calcul simplifié: on utilise la distance au centre pour l'alpha
    // L'ellipse est déjà formée par la géométrie, donc pas besoin de exp()
    // On utilise un falloff doux pour les bords
    
    float dist_sq = dot(v_local_pos.xy, v_local_pos.xy);
    
    // Si on est en dehors du cercle unité (marge de sécurité), on discard
    if (dist_sq > 1.05) {
        discard;
    }
    
    // Falloff doux (évite les bords durs)
    float alpha = smoothstep(1.0, 0.85, dist_sq) * v_opacity;
    
    if (alpha < 0.01) {
        discard;
    }
    
    ALBEDO = v_color;
    ALPHA = alpha;
    EMISSION = v_color * 0.05;
}