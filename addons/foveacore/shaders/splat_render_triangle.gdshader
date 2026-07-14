shader_type spatial;

// ============================================================================
// FoveaEngine : splat_render_triangle.gdshader
// Rendu GPU des Gaussian Splats avec maillage TRIANGLE (pas d'ellipse par fragment)
// Optimisation : élimine le calcul de covariance et exp() par fragment
// ============================================================================

// Optimisations extrêmes pour VR : Pas d'ombres, pas de culling, blending additif ou alpha
render_mode cull_disabled, blend_mix, depth_draw_never, depth_prepass_alpha;

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

// Niveau de détail stochastique (1.0 = complet, 0.0 = masqué)
uniform float lod_ratio = 1.0;

// Layered Splatting toggle
uniform bool enable_layered_splatting = true;

// Uniforms pour le rendu GPU-driven (VRAM-to-VRAM)
uniform usampler2D output_texture;
uniform usampler2D counter_texture;
uniform bool enable_gpu_driven = false;

// Motion-Adaptive Splatting (Phase 3)
// Direction de la vélocité caméra projetée en espace écran (normalisée)
uniform vec2  motion_dir_screen     = vec2(0.0);
// Facteur d'étirement le long de la direction du mouvement (0.0 = désactivé)
uniform float motion_stretch_factor = 0.0;

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
varying flat vec3 v_color;
varying flat float v_opacity;
varying vec2 v_uv;         // UV du vertex (0..1)
varying vec3 v_local_pos;  // Position locale dans le splat (ellipse unité étirée)
varying flat vec3 v_conic; // Covariance inverse (cov22, cov12, cov11) - conservée pour compatibilité
varying float v_specular;

void vertex() {
    v_specular = 0.0;
    // --- 1. DÉCODAGE DES 16 OCTETS (Spatial & Vector Quantization) ---
    uint data0;
    uint data1;
    uint data2;
    uint data3;
    vec3 decoded_local_pos = vec3(0.0);
    bool should_render = true;

    if (enable_gpu_driven) {
        uint valid_count = texelFetch(counter_texture, ivec2(0, 0), 0).r;
        if (uint(INSTANCE_ID) >= valid_count) {
            POSITION = vec4(0.0) / 0.0;
            should_render = false;
        } else {
            ivec2 tex_coord = ivec2(int(uint(INSTANCE_ID) % 1024u), int(uint(INSTANCE_ID) / 1024u));
            uvec4 tex_val = texelFetch(output_texture, tex_coord, 0);
            data0 = tex_val.r;
            data1 = tex_val.g;
            data2 = tex_val.b;
            data3 = tex_val.a;

            uint qx = data0 & 0xFFFFu;
            uint qy = (data0 >> 16u) & 0xFFFFu;
            uint qz = data1 & 0xFFFFu;
            vec3 q_pos = vec3(float(qx), float(qy), float(qz)) / 65535.0;
            decoded_local_pos = aabb_min + q_pos * (aabb_max - aabb_min);
        }
    } else {
        data0 = floatBitsToUint(INSTANCE_CUSTOM.x);
        data1 = floatBitsToUint(INSTANCE_CUSTOM.y);
        data2 = floatBitsToUint(INSTANCE_CUSTOM.z);
        data3 = floatBitsToUint(INSTANCE_CUSTOM.w);
    }

    if (should_render) {
        // Position de l'instance/splat dans le monde via MODEL_MATRIX
        vec3 world_pos;
        if (enable_gpu_driven) {
            world_pos = (MODEL_MATRIX * vec4(decoded_local_pos, 1.0)).xyz;
        } else {
            world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        }

        // Extraction de la couleur (palette ou RGB565 selon use_palette)
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

        // Extraction de l'opacité
        v_opacity = float(data3 & 0xFFu) / 255.0;
        
        // Extraction du type de couche (layer_type)
        uint layer_type = (data3 >> 8u) & 0xFFu;

        // --- 2. CALCUL DE LA COVARIANCE (Anisotropie / Ellipses via Codebook) ---
        uint covar_index = (data2 >> 16u) & 0xFFFFu;
        
        ivec2 tex_size = textureSize(covar_texture, 0);
        float tex_v = (float(covar_index) + 0.5) / float(max(tex_size.y, 1));
        
        vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v), 0.0); 
        vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v), 0.0);
        
        vec3 scale = tex0.xyz;
        vec4 rot = vec4(tex0.w, tex1.x, tex1.y, tex1.z);
        
        mat3 cov3d = compute_cov3d(scale, rot);
        
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
        
        vec3 center_cam;
        if (enable_gpu_driven) {
            center_cam = (MODELVIEW_MATRIX * vec4(decoded_local_pos + wave_offset, 1.0)).xyz;
        } else {
            center_cam = (MODELVIEW_MATRIX * vec4(wave_offset, 1.0)).xyz;
        }
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
        
        // Calcul de la distance au regard basée sur le centre du splat
        vec4 center_clip = PROJECTION_MATRIX * vec4(center_cam, 1.0);
        vec2 center_ndc = center_clip.xy / center_clip.w;
        vec2 aspect_uv = center_ndc * 0.5 + 0.5;
        aspect_uv.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
        
        vec2 aspect_gaze = (VIEW_INDEX == 0) ? fovea_gaze_left : fovea_gaze_right;
        aspect_gaze.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
        
        float dist_to_gaze = distance(aspect_uv, aspect_gaze);
        bool is_in_focus = dist_to_gaze <= fovea_inner_radius;
        
        // Dynamic Foveated Layer Weight Calculation
        float layer_weight = 1.0;
        if (enable_layered_splatting) {
            if (layer_type == 0u) {
                layer_weight = is_in_focus ? 0.8 : 0.3;
            } else if (layer_type == 1u) {
                layer_weight = is_in_focus ? 1.0 : 0.0;
            } else if (layer_type == 2u) {
                layer_weight = is_in_focus ? 1.2 : 0.1;
            } else if (layer_type == 3u) {
                layer_weight = is_in_focus ? 1.0 : 0.0;
            } else if (layer_type == 7u) {
                // LAYER_ANIM (Phase 7.3): flipbook/FX splats (flames, magic effects).
                // Frame culling is handled CPU-side (opacity zeroed for inactive
                // frames), so gaze focus should not additionally dim active frames.
                layer_weight = 1.0;
            } else {
                layer_weight = is_in_focus ? 0.8 : 0.3;
            }
            
            v_opacity *= layer_weight;
            
            // Étirement du rayon pour masquer les trous (LOD stochastique compensateur)
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
        
        // Motion Stretch
        if (motion_stretch_factor > 0.0 && length(motion_dir_screen) > 0.001) {
            float proj_on_motion = dot(local_pos, motion_dir_screen);
            rotated += motion_dir_screen * proj_on_motion * motion_stretch_factor * max(radius1, radius2);
        }
        
        vec2 ndc_offset = (rotated) / VIEWPORT_SIZE * 2.0;
        
        // --- 4. FOVEATED RENDERING ---
        vec4 clip_pos = PROJECTION_MATRIX * vec4(center_cam, 1.0);
        clip_pos.xy += ndc_offset * clip_pos.w;
        
        vec2 ndc_pos = clip_pos.xy / clip_pos.w;
        float random_val = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
        
        if (layer_weight <= 0.01) {
            POSITION = vec4(0.0);
        } else if (random_val > lod_ratio) {
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
}

void fragment() {
    // ============================================================================
    // Alpha Gaussien reel : exp(-0.5 * d^T * Sigma^-1 * d)
    // v_conic = (cov2d.z, -cov2d.y, cov2d.x) * inv_det  (conic inverse 2x2 symetrique)
    //   -> Sigma^-1 = | v_conic.x  v_conic.y |
    //                  | v_conic.y  v_conic.z |
    //
    // v_local_pos.xy est la position dans l'ellipse normalisee (apres rotation+scale)
    // cela signifie que d est deja dans l'espace de l'ellipse :
    // on utilise directement les coordonnees locales non-normalisees
    // stockees avant normalisation dans le vertex shader.
    // ============================================================================

    vec2 d = v_local_pos.xy;

    // Quadratic power : -0.5 * (a*dx^2 + 2b*dx*dy + c*dy^2)
    float power = -0.5 * (v_conic.x * d.x * d.x
                        + 2.0 * v_conic.y * d.x * d.y
                        + v_conic.z * d.y * d.y);

    // Un power positif signifie que le conic est invalide (degenere) -> discard
    if (power > 0.0) {
        discard;
    }

    // Alpha Gaussien : T = exp(power), module par l'opacite sigmoide du splat
    float gaussian_alpha = exp(power);
    float alpha = min(0.99, v_opacity * gaussian_alpha);

    // Seuil de visibilite : en dessous de ~0.4% on evite l'overdraw inutile
    if (alpha < 0.004) {
        discard;
    }

    ALBEDO    = v_color;
    ALPHA     = alpha;
    EMISSION  = v_color * 0.01 + vec3(v_specular);
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