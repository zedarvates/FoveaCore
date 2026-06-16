shader_type spatial;

// ============================================================================
// FoveaEngine : splat_render_artistic.gdshader
// Phase 3 — Artistic Shaders : Digital Painting aesthetic
//
// Trois modes de rendu artistique sélectionnables via `art_mode` :
//   0 = Standard (identique à splat_render_triangle.gdshader)
//   1 = Oil Painting  – postérisation + bords coup-de-pinceau + bruit de peinture + impasto 3D
//   2 = Watercolor    – transparence douce + saturation centrée + granulation + déformation wet-in-wet + cerne
//   3 = Crosshatch    – hachures orientables + variation de densité par NdotV
//
// Basé sur le même vertex shader que splat_render_triangle.gdshader
// (maillage triangle, covariance anisotrope, alpha gaussien réel).
// ============================================================================

render_mode cull_disabled, blend_mix, depth_draw_never, depth_prepass_alpha;

#include "res://addons/foveacore/shaders/splat_math.gdshaderinc"

// ── Paramètres hérités du renderer standard ──────────────────────────────────
uniform vec3 aabb_min;
uniform vec3 aabb_max;
uniform sampler2D covar_texture;
uniform sampler2D palette_texture;
uniform sampler2D sponge_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D drybrush_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D stipple_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_palette = false;
uniform int palette_size = 16;

global uniform vec2 fovea_gaze_left;
global uniform vec2 fovea_gaze_right;
uniform float fovea_inner_radius = 0.3;
uniform float fovea_outer_radius = 0.6;
uniform int splat_subdivisions = 16;
uniform float lod_ratio = 1.0;

// Layered Splatting toggle
uniform bool enable_layered_splatting = true;

// ── Paramètres Motion-Adaptive LOD (partagés avec le renderer) ───────────────
uniform vec2  motion_dir_screen   = vec2(0.0);
uniform float motion_stretch_factor = 0.0;

// Surface Waves (Dynamic, Repeating & Looping)
uniform bool  enable_waves          = false;
uniform float wave_speed            = 1.0;
uniform float wave_amplitude        = 0.2;
uniform float wave_frequency        = 0.5;
uniform float wave_tiling_size      = 10.0;
uniform float wave_loop_period      = 4.0;

// ── Paramètres Artistiques ───────────────────────────────────────────────────
/// Mode de rendu : 0=standard, 1=oil, 2=watercolor, 3=crosshatch
uniform int   art_mode            = 1;

/// [Oil] Niveaux de postérisation des couleurs (2..16, basse valeur = style aplats pop-art)
uniform float posterize_levels    = 6.0;
/// [Oil] Intensité de l'assombrissement des bords (coup de pinceau), 0 = désactivé
uniform float brushstroke_edge    = 0.25;
/// [Oil] Force du bruit de texture de peinture (0 = lisse, 0.15 = visible)
uniform float paint_noise         = 0.08;
/// [Oil] Intensité du relief de la peinture à l'huile (impasto normal mapping)
uniform float impasto_strength      = 8.0;
/// [Oil] Rugosité de la peinture à l'huile (reflet de peinture fraîche vernie)
uniform float oil_roughness         = 0.25;

/// [Watercolor] Exposant de l'alpha aux bords (> 1.0 = bords plus transparents)
uniform float wc_edge_softness    = 2.5;
/// [Watercolor] Boost de saturation au centre du splat (0.0 = aucun, 1.0 = max)
uniform float wc_saturation_boost = 0.4;
/// [Watercolor] Granulation (bruit de granulé de papier aquarelle)
uniform float wc_granulation      = 0.06;
/// [Watercolor] Force du cerne sombre aux bords (accumulation de pigments)
uniform float wc_fringe_strength    = 0.35;
/// [Watercolor] Distorsion organique pour le saignement de l'eau (wet-in-wet)
uniform float wc_bleed_distortion   = 12.0;

/// [Crosshatch] Angle des hachures primaires en radians (0.785 = 45°)
uniform float hatch_angle         = 0.785;
/// [Crosshatch] Espacements entre hachures (en fragments)
uniform float hatch_spacing       = 6.0;
/// [Crosshatch] Largeur relative des lignes (0.1 = fines, 0.4 = épaisses)
uniform float hatch_width_ratio   = 0.25;

// ── Paramètres de Vent et de Forme ───────────────────────────────────────────
uniform bool  enable_wind         = false;
uniform float wind_speed          = 1.0;
uniform float wind_strength       = 0.1;

/// [Cartoon] Niveaux de bandes d'ombrage (Toon shading)
uniform float cartoon_bands       = 3.0;
/// [Cartoon] Force du contour noir (Outline)
uniform float cartoon_outline     = 0.3;

/// [Pixelated] Taille du pixel de grille (en pixels d'écran)
uniform float pixel_size          = 4.0;

// ── Varyings ─────────────────────────────────────────────────────────────────
varying flat vec3  v_color;
varying flat float v_opacity;
varying vec2  v_uv;
varying vec3  v_local_pos;
varying flat vec3  v_conic;
varying flat uint  v_layer_type;
varying flat uint  v_brush_type;
varying flat int   v_instance_id;

// ── Vertex Shader (identique à splat_render_triangle + motion stretch) ────────
void vertex() {
	// 1. Décodage 16 octets
	uint data0 = floatBitsToUint(INSTANCE_CUSTOM.x);
	uint data1 = floatBitsToUint(INSTANCE_CUSTOM.y);
	uint data2 = floatBitsToUint(INSTANCE_CUSTOM.z);
	uint data3 = floatBitsToUint(INSTANCE_CUSTOM.w);

	// Position de l'instance/splat dans le monde via MODEL_MATRIX
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// Couleur
	uint color_index = data2 & 0xFFFFu;
	if (use_palette) {
		uint palette_idx = data2 & 0xFFu;
		float tex_v = (float(palette_idx) + 0.5) / float(max(palette_size, 1));
		v_color = textureLod(palette_texture, vec2(0.5, tex_v), 0.0).rgb;
	} else {
		float r = float((color_index >> 11u) & 0x1Fu) / 31.0;
		float g = float((color_index >> 5u)  & 0x3Fu) / 63.0;
		float b = float(color_index & 0x1Fu)         / 31.0;
		v_color = vec3(r, g, b);
	}
	v_opacity = float(data3 & 0xFFu) / 255.0;
	uint layer_type = (data3 >> 8u) & 0xFFu;
	uint brush_type = (data3 >> 24u) & 0xFFu;
	v_layer_type = layer_type;
	v_brush_type = brush_type;

	// 2. Covariance / Ellipse
	uint covar_index = (data2 >> 16u) & 0xFFFFu;
	ivec2 tex_size = textureSize(covar_texture, 0);
	float tex_v    = (float(covar_index) + 0.5) / float(max(tex_size.y, 1));
	vec4 tex0 = textureLod(covar_texture, vec2(0.25, tex_v), 0.0);
	vec4 tex1 = textureLod(covar_texture, vec2(0.75, tex_v), 0.0);
	vec3 scale = tex0.xyz;
	vec4 rot   = vec4(tex0.w, tex1.x, tex1.y, tex1.z);

	mat3 cov3d    = compute_cov3d(scale, rot);
	
	// Transformer la covariance de l'espace local à l'espace vue (inclut rotation/échelle d'instance)
	mat3 MV = mat3(MODELVIEW_MATRIX);
	cov3d = MV * cov3d * transpose(MV);
	
	// Déplacement de vent si tag Leaves (5) actif + Vagues de Surface
	vec3 displacement_offset = vec3(0.0);
	if (enable_wind && layer_type == 5u) {
		float wave = sin(TIME * wind_speed + world_pos.x * 2.0 + world_pos.y * 3.0) * wind_strength;
		float cos_wave = cos(TIME * wind_speed * 0.8 + world_pos.z * 1.5) * wind_strength * 0.7;
		displacement_offset = vec3(wave, wave * 0.3, cos_wave);
	}
	
	if (enable_waves) {
		float looped_time = mod(TIME, wave_loop_period);
		float tiled_x = mod(world_pos.x, wave_tiling_size);
		float tiled_z = mod(world_pos.z, wave_tiling_size);
		float wave_angle = (tiled_x + tiled_z) * wave_frequency + (looped_time * wave_speed * (2.0 * PI / wave_loop_period));
		displacement_offset.y += sin(wave_angle) * wave_amplitude;
	}
	
	vec3 center_cam = (MODELVIEW_MATRIX * vec4(displacement_offset, 1.0)).xyz;
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
		} else {
			layer_weight = is_in_focus ? 0.8 : 0.3;
		}
		
		v_opacity *= layer_weight;
		
		// Étirement du rayon pour masquer les trous
		float scale_factor = 1.0 + (dist_to_gaze / fovea_inner_radius);
		radius1 *= scale_factor;
		radius2 *= scale_factor;
	}

	vec2 local_pos  = VERTEX.xy;
	vec2 scaled     = vec2(local_pos.x * radius1, local_pos.y * radius2);
	vec2 rotated    = vec2(
		scaled.x * cos_t - scaled.y * sin_t,
		scaled.x * sin_t + scaled.y * cos_t
	);

	// 4. Motion Stretch
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
	float rand_val = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);

	if (layer_weight <= 0.01) {
		POSITION = vec4(0.0);
	} else if (rand_val > lod_ratio) {
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
		
		vec3 splat_normal = vec3(
			2.0 * (rot.y * rot.w + rot.x * rot.z),
			2.0 * (rot.z * rot.w - rot.x * rot.y),
			1.0 - 2.0 * (rot.y * rot.y + rot.z * rot.z)
		);
		NORMAL = (VIEW_MATRIX * vec4(normalize(splat_normal), 0.0)).xyz;
	}
	v_instance_id = INSTANCE_ID;
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

/// Bruit bilinéaire 2D simple basé sur hash21
float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // Lissage Hermite (smoothstep)
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Fragment Shader ───────────────────────────────────────────────────────────
void fragment() {
	// ── Discards de forme (Brush Types: 0 = STONE, 1 = SPONGE, 2 = GAUSSIAN, 3 = DRYBRUSH, 4 = STIPPLE) ──
	vec2 p = v_uv * 2.0 - vec2(1.0);
	float d_sq = dot(p, p);
	
	if (v_brush_type == 0u) {
		// STONE : Bord angulaire et dentelé (aspect éclat de roche)
		float angle = atan(p.y, p.x);
		float warp = noise2d(vec2(angle * 4.0, float(v_instance_id) * 0.17)) * 0.18;
		if (length(p) > (0.82 + warp)) {
			discard;
		}
	} else if (v_brush_type == 1u) {
		// SPONGE : Masque poreux de bruit (plus aéré sur les bords)
		if (d_sq > 1.0) {
			discard;
		}
		vec4 tex_val = texture(sponge_texture, v_uv);
		float n = tex_val.a > 0.001 ? tex_val.r * tex_val.a : noise2d(v_uv * 18.0 + vec2(float(v_instance_id) * 0.12));
		if (n < 0.38 * (1.0 - d_sq)) {
			discard;
		}
	} else if (v_brush_type == 2u) {
		// GAUSSIAN / Circle : Bordure circulaire douce standard
		if (d_sq > 1.0) {
			discard;
		}
	} else if (v_brush_type == 3u) {
		// DRYBRUSH : Masque linéaire de coups de pinceaux secs
		if (d_sq > 1.0) {
			discard;
		}
		vec4 tex_val = texture(drybrush_texture, v_uv);
		float n = tex_val.a > 0.001 ? tex_val.r * tex_val.a : noise2d(vec2(v_uv.x * 32.0, float(v_instance_id) * 0.15)) * (1.0 - abs(v_uv.y - 0.5) * 2.0);
		if (n < 0.25) {
			discard;
		}
	} else if (v_brush_type == 4u) {
		// STIPPLE : Pointillisme / points distincts
		if (d_sq > 1.0) {
			discard;
		}
		vec4 tex_val = texture(stipple_texture, v_uv);
		float n = tex_val.a > 0.001 ? tex_val.r * tex_val.a : fract(sin(dot(v_uv, vec2(12.9898, 78.233))) * 43758.5453);
		if (n < 0.5) {
			discard;
		}
	}

	// Récupération des coordonnées locales du splat (ellipse pixels)
	vec2 d = v_local_pos.xy;

	// ── Mode 2 : Watercolor - Distorsion organique avant discard (wet-in-wet) ──
	if (art_mode == 2) {
		vec2 noise_coord = d * 0.05 + FRAGCOORD.xy * 0.015 + vec2(float(v_instance_id) * 0.11);
		float noise_val = noise2d(noise_coord) + 0.5 * noise2d(noise_coord * 2.0);
		float noise_angle = noise_val * 6.2831853;
		vec2 warp = vec2(cos(noise_angle), sin(noise_angle)) * wc_bleed_distortion;
		d += warp;
	}

	// Alpha gaussien réel (décroît vers les bords de l'ellipse)
	float power = -0.5 * (v_conic.x * d.x * d.x
	                    + 2.0 * v_conic.y * d.x * d.y
	                    + v_conic.z * d.y * d.y);
	if (power > 0.0) discard;

	float gauss = exp(power);   // 1.0 au centre, décroît vers 0 aux bords
	vec3  color = v_color;
	float alpha = min(0.99, v_opacity * gauss);

	// Variables PBR par défaut
	float out_roughness = 0.5;
	float out_specular = 0.15;
	float out_metallic = 0.0;
	vec3  out_emission = vec3(0.0);

	// Layer type specific customization (BASE=0u, SATURATION=1u, LIGHT=2u, SHADOW=3u, LIQUID=4u)
	if (v_layer_type == 1u) {
		color = boost_saturation(color, 0.5);
	} else if (v_layer_type == 2u) {
		color = mix(color, vec3(1.0), 0.4);
		out_emission = color * 1.5;
		out_specular = 0.9;
		out_roughness = 0.1;
	} else if (v_layer_type == 3u) {
		color = color * 0.25;
		out_roughness = 0.9;
		out_specular = 0.05;
		out_metallic = 0.0;
	} else if (v_layer_type == 4u) {
		vec3 view_dir = vec3(0.0, 0.0, 1.0);
		float fresnel = pow(1.0 - max(dot(NORMAL, view_dir), 0.0), 3.0);
		color = mix(color, vec3(0.8, 0.9, 1.0), fresnel * 0.4);
		out_roughness = 0.05;
		out_specular = 0.95;
		alpha = clamp(alpha * 1.3, 0.0, 0.95);
	}

	// ── Mode 1 : Oil Painting ────────────────────────────────────────────────
	if (art_mode == 1) {
		// Postérisation des couleurs (effets aplats, pop-art)
		color = posterize(color, max(posterize_levels, 2.0));

		// Bord coup-de-pinceau : assombrir les bords du splat
		float edge_shadow = brushstroke_edge * (1.0 - gauss * gauss);
		color *= (1.0 - edge_shadow);

		// Bruit de texture de peinture : variation colorée aléatoire par fragment
		float noise = (hash21(FRAGCOORD.xy * 0.07 + float(v_instance_id) * 0.013) * 2.0 - 1.0);
		color = clamp(color + noise * paint_noise, 0.0, 1.0);

		// Effet Impasto en relief (3D normal mapping via dFdx/dFdy sur la hauteur)
		vec2 brush_coord = FRAGCOORD.xy * 0.06 + vec2(float(v_instance_id) * 0.05);
		float brush_noise = noise2d(brush_coord) + 0.5 * noise2d(brush_coord * 2.0);
		float height = (gauss * 0.7 + brush_noise * 0.3) * impasto_strength;

		float dx = dFdx(height);
		float dy = dFdy(height);
		NORMAL = normalize(NORMAL - vec3(dx, dy, 0.0));

		out_roughness = oil_roughness;
		out_specular = 0.6;
		out_metallic = 0.0;
		out_emission = color * 0.02; // Légère lueur d'ambiance

	// ── Mode 2 : Watercolor ─────────────────────────────────────────────────
	} else if (art_mode == 2) {
		// Alpha plus doux sur les bords (l'aquarelle "s'étale")
		float soft_gauss = pow(gauss, wc_edge_softness);
		alpha = min(0.99, v_opacity * soft_gauss);

		// Boost de saturation centré : le cœur du splat est plus vif
		float sat_center  = gauss * wc_saturation_boost;
		color = boost_saturation(color, sat_center);

		// Cerne d'accumulation de pigments aux bords (pigment fringe)
		float fringe_mask = smoothstep(0.35, 0.05, gauss) * smoothstep(0.0, 0.1, gauss);
		float fringe_effect = fringe_mask * wc_fringe_strength;
		color = mix(color, color * 0.5, fringe_effect); // Assombrissement aux bords
		color = boost_saturation(color, fringe_effect * 0.6); // Sursaturation

		// Granulation aquarelle : bruit de pigment
		float grain = (hash21(FRAGCOORD.xy * 0.12 + float(v_instance_id) * 0.031) * 2.0 - 1.0);
		color = clamp(color + grain * wc_granulation * (1.0 - gauss), 0.0, 1.0);

		out_roughness = 0.9; // Aspect mat du papier aquarelle
		out_specular = 0.05;
		out_metallic = 0.0;
		out_emission = color * 0.03;

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

		out_roughness = 1.0;
		out_specular = 0.0;
		out_metallic = 0.0;
		out_emission = color;
		color = vec3(0.0); // ALBEDO noir pour ignorer l'éclairage de la scène (rendu plat / unshaded)
	// ── Mode 4 : Cartoon / Cel-Shading ──────────────────────────────────────
	} else if (art_mode == 4) {
		// Toon Shading (quantiser NdotL)
		vec3 light_dir = vec3(0.0, 1.0, 0.5);
		float ndotl = max(dot(NORMAL, normalize(light_dir)), 0.0);
		float toon_diffuse = floor(ndotl * cartoon_bands) / max(cartoon_bands - 1.0, 1.0);
		color = color * (0.3 + 0.7 * toon_diffuse);
		
		// Outlines (NdotV)
		vec3 view_dir = vec3(0.0, 0.0, 1.0);
		float ndotv = abs(dot(NORMAL, view_dir));
		float outline_factor = smoothstep(0.0, cartoon_outline, ndotv);
		color = mix(vec3(0.0), color, outline_factor);
		
		out_roughness = 0.8;
		out_specular = 0.05;
		out_metallic = 0.0;
		out_emission = color * 0.02;

	// ── Mode 5 : Pixelated ──────────────────────────────────────────────────
	} else if (art_mode == 5) {
		// Pixelation locale par splat
		vec2 pixelated_uv = floor(v_uv * 10.0) / 10.0;
		float cell_gauss = exp(-8.0 * dot(pixelated_uv - vec2(0.5), pixelated_uv - vec2(0.5)));
		alpha = min(0.99, v_opacity * cell_gauss);
		
		// Quantification des couleurs
		color = floor(color * 5.0) / 5.0;
		out_roughness = 0.9;
		out_specular = 0.0;
		out_emission = color * 0.05;
		
	} else {
		// Mode 0 : Standard
		out_roughness = 0.5;
		out_specular = 0.15;
		out_metallic = 0.0;
		out_emission = color * 0.01;
	}

	if (alpha < 0.004) discard;

	ALBEDO   = color;
	ALPHA    = alpha;
	METALLIC  = out_metallic;
	ROUGHNESS = out_roughness;
	SPECULAR  = out_specular;
	EMISSION  = out_emission;
}
