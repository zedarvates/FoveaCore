shader_type spatial;

// ============================================================================
// FoveaEngine : splat_render_artistic.gdshader
// Phase 3 — Artistic Shaders : Digital Painting aesthetic
//
// Trois modes de rendu artistique sélectionnables via `art_mode` :
//   0 = Standard (identique à splat_render_triangle.gdshader)
//   1 = Oil Painting  – postérisation + bords coup-de-pinceau + bruit de peinture
//   2 = Watercolor    – transparence douce + saturation centrée + granulation
//   3 = Crosshatch    – hachures orientables + variation de densité par NdotV
//
// Basé sur le même vertex shader que splat_render_triangle.gdshader
// (maillage triangle, covariance anisotrope, alpha gaussien réel).
// ============================================================================

render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_prepass_alpha;

#include "res://addons/foveacore/shaders/splat_math.gdshaderinc"

// ── Paramètres hérités du renderer standard ──────────────────────────────────
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

// ── Paramètres Motion-Adaptive LOD (partagés avec le renderer) ───────────────
uniform vec2  motion_dir_screen   = vec2(0.0);
uniform float motion_stretch_factor = 0.0;

// ── Paramètres Artistiques ───────────────────────────────────────────────────
/// Mode de rendu : 0=standard, 1=oil, 2=watercolor, 3=crosshatch
uniform int   art_mode            = 1;

/// [Oil] Niveaux de postérisation des couleurs (2..16, basse valeur = style aplats pop-art)
uniform float posterize_levels    = 6.0;
/// [Oil] Intensité de l'assombrissement des bords (coup de pinceau), 0 = désactivé
uniform float brushstroke_edge    = 0.25;
/// [Oil] Force du bruit de texture de peinture (0 = lisse, 0.15 = visible)
uniform float paint_noise         = 0.08;

/// [Watercolor] Exposant de l'alpha aux bords (> 1.0 = bords plus transparents)
uniform float wc_edge_softness    = 2.5;
/// [Watercolor] Boost de saturation au centre du splat (0.0 = aucun, 1.0 = max)
uniform float wc_saturation_boost = 0.4;
/// [Watercolor] Granulation (bruit de granulé de papier aquarelle)
uniform float wc_granulation      = 0.06;

/// [Crosshatch] Angle des hachures primaires en radians (0.785 = 45°)
uniform float hatch_angle         = 0.785;
/// [Crosshatch] Espacements entre hachures (en fragments)
uniform float hatch_spacing       = 6.0;
/// [Crosshatch] Largeur relative des lignes (0.1 = fines, 0.4 = épaisses)
uniform float hatch_width_ratio   = 0.25;

// ── Varyings ─────────────────────────────────────────────────────────────────
varying flat vec3  v_color;
varying flat float v_opacity;
varying vec2  v_uv;
varying vec3  v_local_pos;
varying flat vec3  v_conic;

// ── Vertex Shader (identique à splat_render_triangle + motion stretch) ────────
void vertex() {
	// 1. Décodage 16 octets
	uint data0 = floatBitsToUint(INSTANCE_CUSTOM.x);
	uint data1 = floatBitsToUint(INSTANCE_CUSTOM.y);
	uint data2 = floatBitsToUint(INSTANCE_CUSTOM.z);
	uint data3 = floatBitsToUint(INSTANCE_CUSTOM.w);

	uint qx = data0 & 0xFFFFu;
	uint qy = (data0 >> 16) & 0xFFFFu;
	uint qz = data1 & 0xFFFFu;
	vec3 q_pos   = vec3(float(qx), float(qy), float(qz)) / 65535.0;
	vec3 world_pos = aabb_min + q_pos * (aabb_max - aabb_min);

	// Couleur
	uint color_index = data2 & 0xFFFFu;
	if (use_palette) {
		uint palette_idx = data2 & 0xFFu;
		float tex_v = (float(palette_idx) + 0.5) / float(max(palette_size, 1));
		v_color = textureLod(palette_texture, vec2(0.5, tex_v), 0.0).rgb;
	} else {
		float r = float((color_index >> 11) & 0x1Fu) / 31.0;
		float g = float((color_index >> 5)  & 0x3Fu) / 63.0;
		float b = float(color_index & 0x1Fu)         / 31.0;
		v_color = vec3(r, g, b);
	}
	v_opacity = float(data3 & 0xFFu) / 255.0;

	// 2. Covariance / Ellipse
	uint covar_index = (data2 >> 16) & 0xFFFFu;
	ivec2 tex_size = textureSize(covar_texture, 0);
	float tex_v    = (float(covar_index) + 0.5) / float(max(tex_size.y, 1));
	vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v), 0.0);
	vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v), 0.0);
	vec3 scale = tex0.xyz;
	vec4 rot   = vec4(tex0.w, tex1.x, tex1.y, tex1.z);

	mat3 cov3d    = compute_cov3d(scale, rot);
	vec3 center_cam = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	vec3 cov2d    = compute_cov2d(center_cam, cov3d, PROJECTION_MATRIX, VIEWPORT_SIZE);

	float det     = (cov2d.x * cov2d.z) - (cov2d.y * cov2d.y);
	float inv_det = 1.0 / max(det, 0.0000001);
	v_conic = vec3(cov2d.z, -cov2d.y, cov2d.x) * inv_det;

	// 3. Calcul des axes de l'ellipse
	float a = cov2d.x, b = cov2d.y, c = cov2d.z;
	float trace     = a + c;
	float sqrt_term = sqrt(max(trace * trace * 0.25 - det, 0.0));
	float lambda1   = trace * 0.5 + sqrt_term;
	float lambda2   = trace * 0.5 - sqrt_term;
	float radius1   = 3.0 * sqrt(max(lambda1, 0.0));
	float radius2   = 3.0 * sqrt(max(lambda2, 0.0));
	float cos_2t    = (a - c) / max(trace, 0.0001);
	float sin_2t    = (2.0 * b) / max(trace, 0.0001);
	float theta     = atan(sin_2t, cos_2t) * 0.5;
	float cos_t     = cos(theta), sin_t = sin(theta);

	vec2 local_pos  = VERTEX.xy;
	vec2 scaled     = vec2(local_pos.x * radius1, local_pos.y * radius2);
	vec2 rotated    = vec2(
		scaled.x * cos_t - scaled.y * sin_t,
		scaled.x * sin_t + scaled.y * cos_t
	);

	// 4. Motion Stretch (Phase 3 : Motion-Adaptive Splatting)
	// Étire chaque vertex dans la direction de la vélocité caméra (motion blur natif)
	if (motion_stretch_factor > 0.0 && length(motion_dir_screen) > 0.001) {
		float proj   = dot(local_pos, motion_dir_screen);
		float max_r  = max(radius1, radius2);
		rotated += motion_dir_screen * proj * motion_stretch_factor * max_r;
	}

	vec2 ndc_offset = rotated / VIEWPORT_SIZE * 2.0;

	// 5. Foveated Rendering + LOD stochastique
	vec4 clip_pos = PROJECTION_MATRIX * vec4(center_cam, 1.0);
	clip_pos.xy  += ndc_offset * clip_pos.w;

	vec2 ndc_pos   = clip_pos.xy / clip_pos.w;
	vec2 aspect_uv = ndc_pos * 0.5 + 0.5;
	aspect_uv.x   *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;

	vec2 aspect_gaze = (VIEW_INDEX == 0) ? fovea_gaze_left : fovea_gaze_right;
	aspect_gaze.x   *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;

	float dist_to_gaze = distance(aspect_uv, aspect_gaze);
	float rand_val = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);

	if (rand_val > lod_ratio) {
		POSITION = vec4(0.0);
	} else if (dist_to_gaze > fovea_outer_radius && rand_val > 0.25) {
		POSITION = vec4(0.0);
	} else if (dist_to_gaze > fovea_inner_radius && rand_val > 0.50) {
		POSITION = vec4(0.0);
	} else if (length(ndc_pos) > 1.25) {
		POSITION = vec4(0.0);
	} else {
		POSITION    = clip_pos;
		v_uv        = local_pos * 0.5 + 0.5;
		v_local_pos = vec3(rotated, 0.0);
	}
}

// ── Fonctions utilitaires artistiques ────────────────────────────────────────

/// Postérisation : réduit le nombre de niveaux de couleur par canal
vec3 posterize(vec3 col, float levels) {
	return floor(col * levels + 0.5) / levels;
}

/// Boost de saturation centré sur la luminance
vec3 boost_saturation(vec3 col, float factor) {
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	return clamp(mix(vec3(lum), col, 1.0 + factor), 0.0, 1.0);
}

/// Hash pseudo-aléatoire 2D → 1D pour le bruit de texture
float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

// ── Fragment Shader ───────────────────────────────────────────────────────────
void fragment() {
	// Alpha gaussien réel (identique au shader standard)
	vec2  d     = v_local_pos.xy;
	float power = -0.5 * (v_conic.x * d.x * d.x
	                    + 2.0 * v_conic.y * d.x * d.y
	                    + v_conic.z * d.y * d.y);
	if (power > 0.0) discard;

	float gauss = exp(power);   // 1.0 au centre, décroît vers 0 aux bords
	vec3  color = v_color;
	float alpha = min(0.99, v_opacity * gauss);

	// ── Mode 1 : Oil Painting ────────────────────────────────────────────────
	if (art_mode == 1) {
		// Postérisation des couleurs (effets aplats, pop-art)
		color = posterize(color, max(posterize_levels, 2.0));

		// Bord coup-de-pinceau : assombrir les bords du splat
		float edge_shadow = brushstroke_edge * (1.0 - gauss * gauss);
		color *= (1.0 - edge_shadow);

		// Bruit de texture de peinture : variation colorée aléatoire par fragment
		float noise = (hash21(FRAGCOORD.xy * 0.07 + float(INSTANCE_ID) * 0.013) * 2.0 - 1.0);
		color = clamp(color + noise * paint_noise, 0.0, 1.0);

	// ── Mode 2 : Watercolor ─────────────────────────────────────────────────
	} else if (art_mode == 2) {
		// Alpha plus doux sur les bords (l'aquarelle "s'étale")
		float soft_gauss = pow(gauss, wc_edge_softness);
		alpha = min(0.99, v_opacity * soft_gauss);

		// Boost de saturation centré : le cœur du splat est plus vif
		float sat_center  = gauss * wc_saturation_boost;
		color = boost_saturation(color, sat_center);

		// Granulation aquarelle : bruit de pigment
		float grain = (hash21(FRAGCOORD.xy * 0.12 + float(INSTANCE_ID) * 0.031) * 2.0 - 1.0);
		color = clamp(color + grain * wc_granulation * (1.0 - gauss), 0.0, 1.0);

	// ── Mode 3 : Crosshatch ─────────────────────────────────────────────────
	} else if (art_mode == 3) {
		// Hachures primaires (diagonale principale)
		float h1 = FRAGCOORD.x * cos(hatch_angle) + FRAGCOORD.y * sin(hatch_angle);
		float t1 = fract(h1 / hatch_spacing);
		float line1 = smoothstep(hatch_width_ratio - 0.05, hatch_width_ratio, t1)
		            * (1.0 - smoothstep(1.0 - hatch_width_ratio, 1.0 - hatch_width_ratio + 0.05, t1));

		// Hachures secondaires (perpendiculaires) pour les zones sombres
		float lum = dot(color, vec3(0.299, 0.587, 0.114));
		float h2  = FRAGCOORD.x * cos(hatch_angle + 1.5708) + FRAGCOORD.y * sin(hatch_angle + 1.5708);
		float t2  = fract(h2 / hatch_spacing);
		float line2 = (lum < 0.4) ? (smoothstep(hatch_width_ratio - 0.05, hatch_width_ratio, t2)
		            * (1.0 - smoothstep(1.0 - hatch_width_ratio, 1.0 - hatch_width_ratio + 0.05, t2))) : 0.0;

		// Combiner hachures : zones claires = hachures espacées, sombres = croisées
		float hatch_mask = max(line1, line2);
		color = mix(color * 0.1, color, hatch_mask);  // Fond presque blanc entre hachures
	}

	if (alpha < 0.004) discard;

	ALBEDO   = color;
	ALPHA    = alpha;
	EMISSION = color * 0.04;
}
