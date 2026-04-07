shader_type spatial;
render_mode unshaded, depth_draw_alpha_prepass, cull_disabled, blend_mix;

// Paramètres du splat gaussien
uniform float splat_softness: hint_range(0.0, 1.0) = 0.5;
uniform float splat_falloff: hint_range(1.0, 4.0) = 2.0;

void vertex() {
	// Billboard : orienter les vertices vers la caméra
	vec4 world_pos = WORLD_MATRIX * vec4(VERTEX, 1.0);
	vec4 camera_pos = INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);

	// Direction vers la caméra
	vec3 to_camera = normalize(camera_pos.xyz - world_pos.xyz);

	// Créer une base orientée vers la caméra
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(to_camera, up));
	up = normalize(cross(right, to_camera));

	// Position du vertex en espace monde (déjà billboard dans le mesh)
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * world_pos;
}

void fragment() {
	// Coordonnées UV pour le calcul gaussien
	vec2 uv = UV * 2.0 - 1.0; // [-1, 1]

	// Distance au centre du splat
	float dist = length(uv);

	// Fonction gaussienne
	float gaussian = exp(-pow(dist * splat_falloff, 2.0));

	// Softness
	gaussian = smoothstep(splat_softness, 1.0, gaussian);

	// Couleur finale avec alpha gaussien
	ALBEDO = COLOR.rgb;
	ALPHA = gaussian * COLOR.a;

	// Depth prepass pour éviter le z-fighting
	ALPHA_SCISSOR = 0.01;
}
