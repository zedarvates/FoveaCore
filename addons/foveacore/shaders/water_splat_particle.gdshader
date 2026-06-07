shader_type spatial;

// ============================================================================
// FoveaEngine : water_splat_particle.gdshader
// Rendu GPU de splats d'eau avec advection, impact d'obstacle et recyclage.
// ============================================================================

render_mode cull_disabled, blend_mix, depth_draw_never, depth_prepass_alpha;

#include "res://addons/foveacore/shaders/splat_math.gdshaderinc"

// Bounding box pour dé-quantisation
uniform vec3 aabb_min;
uniform vec3 aabb_max;

// Codebooks pour quantification
uniform sampler2D covar_texture;
uniform sampler2D palette_texture;
uniform bool use_palette = false;
uniform int palette_size = 16;

// Fovéation (Eye Tracking)
global uniform vec2 fovea_gaze_left;
global uniform vec2 fovea_gaze_right;
uniform float fovea_inner_radius = 0.3;
uniform float fovea_outer_radius = 0.6;

// --- PARAMÈTRES DU FLUX D'EAU (ADVECTION) ---
uniform vec3 flow_direction = vec3(1.0, 0.0, 0.0);
uniform float flow_speed = 2.0; // Vitesse en m/s
uniform float flow_cycle_duration = 4.0; // Durée de vie d'un cycle en s
uniform float max_distance = 8.0; // Distance max parcourue avant recyclage
uniform float water_opacity = 0.6;

// --- PARAMÈTRES DE L'OBSTACLE (COLLISION & SPLASH) ---
uniform vec3 obstacle_position = vec3(2.0, 0.0, 0.0); // Pierre
uniform float obstacle_radius = 1.0;
uniform vec3 splash_velocity = vec3(1.5, 4.0, 0.5); // Rebond
uniform float gravity = 9.8;
uniform float splash_duration = 1.2; // Temps en l'air avant disparition

// --- EFFETS OPTIQUES DE L'EAU (RÉFRACTION & TRANSPARENCE) ---
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.03;

// Données transmises au fragment
varying flat vec3 v_color;
varying flat float v_opacity;
varying vec2 v_uv;
varying vec3 v_local_pos;
varying flat vec3 v_conic;

void vertex() {
    // --- 1. DÉCODAGE DES 16 OCTETS ---
    uint data0 = floatBitsToUint(INSTANCE_CUSTOM.x);
    uint data1 = floatBitsToUint(INSTANCE_CUSTOM.y);
    uint data2 = floatBitsToUint(INSTANCE_CUSTOM.z);
    uint data3 = floatBitsToUint(INSTANCE_CUSTOM.w);

    uint qx = data0 & 0xFFFFu;
    uint qy = (data0 >> 16u) & 0xFFFFu;
    uint qz = data1 & 0xFFFFu;
    vec3 q_pos = vec3(float(qx), float(qy), float(qz)) / 65535.0;
    vec3 world_pos = aabb_min + q_pos * (aabb_max - aabb_min);

    // Décodage couleur
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
    float original_opacity = float(data3 & 0xFFu) / 255.0;

    // --- 2. DÉCODAGE ET CALCUL DE LA COVARIANCE / TAILLE DE BASE (3DGS) ---
    uint covar_index = (data2 >> 16u) & 0xFFFFu;
    ivec2 tex_size = textureSize(covar_texture, 0);
    float tex_v_cov = (float(covar_index) + 0.5) / float(max(tex_size.y, 1));
    
    vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v_cov), 0.0); 
    vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v_cov), 0.0);
    
    vec3 scale = tex0.xyz;
    vec4 rot = vec4(tex0.w, tex1.x, tex1.y, tex1.z);

    // Rayon réel approximatif en mètres de la gaussienne
    float radius_m = (exp(scale.x) + exp(scale.y) + exp(scale.z)) / 3.0;

    // --- 3. LOGIQUE D'ADVECTION LOCALE ET RECYCLAGE CENTRÉ (GPU PARTICLE) ---
    // Distance locale proportionnelle à la taille du splat
    // max_distance agit ici comme un facteur multiplicateur de rayon (ex: 2.0 fois le rayon)
    float local_max_dist = radius_m * max_distance;

    // Calcul de la durée de cycle locale pour que la vitesse physique de déplacement soit uniforme (flow_speed en m/s)
    float local_cycle_duration = local_max_dist / max(flow_speed, 0.05);

    // Calcul d'un offset pseudo-aléatoire propre à chaque splat pour désynchroniser le cycle
    float rand_seed = fract(sin(float(INSTANCE_ID) * 12.9898 + world_pos.x * 78.233) * 43758.5453);
    float local_time = TIME + rand_seed * local_cycle_duration;
    float phase = fract(local_time / local_cycle_duration);

    // Décodage de la direction d'écoulement (globale ou peinte localement)
    uint nx_u = (data1 >> 16u) & 0xFFu;
    uint nz_u = (data1 >> 24u) & 0xFFu;
    vec3 flow_dir_norm;
    if (nx_u == 0u && nz_u == 0u) {
        flow_dir_norm = normalize(flow_direction);
    } else {
        vec3 local_flow_dir = vec3(
            (float(nx_u) / 255.0) * 2.0 - 1.0,
            0.0,
            (float(nz_u) / 255.0) * 2.0 - 1.0
        );
        flow_dir_norm = normalize(local_flow_dir);
    }

    // Écoulement centré symétriquement : commence à (P0 - 0.5*L) et finit à (P0 + 0.5*L)
    vec3 start_pos = world_pos - flow_dir_norm * (0.5 * local_max_dist);
    float u_current = phase * local_max_dist;
    vec3 current_pos = start_pos + flow_dir_norm * u_current;

    // Détection d'impact analytique par rapport à start_pos
    vec3 to_obstacle = obstacle_position - start_pos;
    float u_closest = dot(to_obstacle, flow_dir_norm);
    vec3 perp_vec = to_obstacle - u_closest * flow_dir_norm;
    float perp_dist_sq = dot(perp_vec, perp_vec);
    float r_sq = obstacle_radius * obstacle_radius;

    // Détection de l'intersection de la trajectoire locale avec l'obstacle
    bool will_hit = (perp_dist_sq < r_sq) && (u_closest > 0.0) && (u_closest < local_max_dist);
    float u_impact = will_hit ? (u_closest - sqrt(r_sq - perp_dist_sq)) : 99999.0;

    vec3 final_sim_pos = current_pos;
    float current_opacity = original_opacity * water_opacity;
    float decay_factor = 1.0;
    bool is_splashing = false;

    if (will_hit && u_current >= u_impact) {
        float d_splash = u_current - u_impact;
        float t_splash = d_splash / max(flow_speed, 0.1);

        if (t_splash < splash_duration) {
            is_splashing = true;
            decay_factor = clamp(1.0 - (t_splash / splash_duration), 0.0, 1.0);
            
            // Trajectoire balistique parabolique : position d'impact + V*t - 0.5*g*t^2
            vec3 impact_point = start_pos + flow_dir_norm * u_impact;
            
            // Vitesse de projection avec perturbation aléatoire pour l'aspect volatil
            vec3 randomized_velocity = splash_velocity + vec3(
                sin(float(INSTANCE_ID) * 45.1) * 0.4,
                cos(float(INSTANCE_ID) * 12.5) * 0.5,
                sin(float(INSTANCE_ID) * 78.9) * 0.4
            );
            
            final_sim_pos = impact_point + randomized_velocity * t_splash - vec3(0.0, 0.5 * gravity * t_splash * t_splash, 0.0);
            current_opacity *= decay_factor; // Fade-out progressif
        } else {
            // Splash expiré : invisible avant téléportation
            current_opacity = 0.0;
        }
    } else {
        // Enveloppe de fondu pour l'amont et l'aval du cycle de la micro-boucle
        float fade_envelope = sin(phase * 3.14159);
        current_opacity *= fade_envelope;
    }

    v_opacity = current_opacity;

    // --- 4. CALCUL DU SPLAT (SPHÉRICISATION DU SPLASH ET COVARIANCE 2D) ---
    if (is_splashing) {
        // Rendre le splat sphérique (gouttelette d'écume volatile) et le réduire
        float max_s = max(scale.x, max(scale.y, scale.z));
        scale = vec3(max_s) + log(decay_factor);
    }

    mat3 cov3d = compute_cov3d(scale, rot);
    
    // Application de la position simulée à l'espace de la caméra
    vec3 center_cam = (VIEW_MATRIX * vec4(final_sim_pos, 1.0)).xyz;
    
    // Calcul de la normale de surface en espace vue avec rides sinusoïdales temporelles (Lumière dynamique)
    vec3 splat_normal = vec3(0.0, 1.0, 0.0);
    splat_normal.x += sin(final_sim_pos.x * 6.0 + TIME * 3.0) * 0.15;
    splat_normal.z += cos(final_sim_pos.z * 5.0 - TIME * 2.5) * 0.15;
    splat_normal = normalize(splat_normal);
    NORMAL = (VIEW_MATRIX * vec4(splat_normal, 0.0)).xyz;
    vec3 cov2d = compute_cov2d(center_cam, cov3d, PROJECTION_MATRIX, VIEWPORT_SIZE);
    
    float det = (cov2d.x * cov2d.z) - (cov2d.y * cov2d.y);
    float inv_det = 1.0 / max(det, 0.0000001);
    v_conic = vec3(cov2d.z, -cov2d.y, cov2d.x) * inv_det;

    // --- 4. MAILLAGE ET PROJECTION (TRIANGLE ET NDC) ---
    vec2 local_pos = VERTEX.xy;
    v_local_pos = vec3(local_pos, 0.0);
    
    float a = cov2d.x;
    float b = cov2d.y;
    float c = cov2d.z;
    float trace = a + c;
    float sqrt_term = sqrt(max(trace * trace * 0.25 - det, 0.0));
    float lambda1 = trace * 0.5 + sqrt_term;
    float lambda2 = trace * 0.5 - sqrt_term;
    
    float radius1 = 3.0 * sqrt(max(lambda1, 0.0));
    float radius2 = 3.0 * sqrt(max(lambda2, 0.0));
    
    float cos_2theta = (a - c) / max(trace, 0.0001);
    float sin_2theta = (2.0 * b) / max(trace, 0.0001);
    float theta = atan(sin_2theta, cos_2theta) * 0.5;
    
    float cos_t = cos(theta);
    float sin_t = sin(theta);
    
    vec2 scaled = vec2(local_pos.x * radius1, local_pos.y * radius2);
    vec2 rotated = vec2(
        scaled.x * cos_t - scaled.y * sin_t,
        scaled.x * sin_t + scaled.y * cos_t
    );
    
    vec2 ndc_offset = rotated / VIEWPORT_SIZE * 2.0;
    vec4 clip_pos = PROJECTION_MATRIX * vec4(center_cam, 1.0);
    clip_pos.xy += ndc_offset * clip_pos.w;
    
    vec2 ndc_pos = clip_pos.xy / clip_pos.w;
    
    // Fovéation basique pour VR
    vec2 aspect_uv = ndc_pos * 0.5 + 0.5;
    aspect_uv.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
    
    vec2 aspect_gaze = (VIEW_INDEX == 0) ? fovea_gaze_left : fovea_gaze_right;
    aspect_gaze.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
    
    float dist_to_gaze = distance(aspect_uv, aspect_gaze);
    float rand_fovea = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
    
    if (dist_to_gaze > fovea_outer_radius && rand_fovea > 0.3) {
        POSITION = vec4(0.0);
    } else {
        POSITION = clip_pos;
        v_uv = local_pos * 0.5 + 0.5;
    }
}

void fragment() {
    float dist_sq = dot(v_local_pos.xy, v_local_pos.xy);
    if (dist_sq > 1.05) {
        discard;
    }
    
    // Limiter l'opacité selon le profil gaussien
    float alpha = smoothstep(1.0, 0.85, dist_sq) * v_opacity;
    if (alpha < 0.005) {
        discard;
    }
    
    // Réfraction de l'arrière-plan en espace écran
    vec2 refract_offset = v_local_pos.xy * refraction_strength * smoothstep(1.0, 0.0, dist_sq);
    vec3 bg_color = texture(screen_texture, SCREEN_UV + refract_offset).rgb;
    
    // Mélanger la couleur de l'eau avec l'image réfractée de l'arrière-plan
    vec3 final_color = mix(bg_color, v_color, 0.3);
    
    // Effet Fresnel local (brillance spéculaire blanche sur les bords extérieurs du splat)
    float local_fresnel = pow(dist_sq, 3.0);
    vec3 specular_highlight = vec3(0.95, 0.98, 1.0);
    final_color = mix(final_color, specular_highlight, local_fresnel * 0.45);
    
    ALBEDO = final_color;
    ALPHA = alpha;
    EMISSION = final_color * 0.02; // Légère émission réduite pour valoriser la lumière dynamique
}

void light() {
    // Éclairage diffus Lambertien doux
    float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
    DIFFUSE_LIGHT += LIGHT_COLOR * NdotL * ATTENUATION * 0.35;
    
    // Brillance spéculaire spéculaire Blinn-Phong pour l'éclat de l'eau
    vec3 H = normalize(VIEW + LIGHT);
    float NdotH = clamp(dot(NORMAL, H), 0.0, 1.0);
    float specular = pow(NdotH, 64.0) * 0.75;
    SPECULAR_LIGHT += LIGHT_COLOR * specular * ATTENUATION;
}
