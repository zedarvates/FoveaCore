shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, transparency_alpha_prepass;

// Artistic Painterly Shader for Gaussian Splats
// Simulates brush strokes and canvas texture

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float brush_strength : hint_range(0.0, 1.0) = 0.3;
uniform float brush_scale : hint_range(1.0, 50.0) = 10.0;
uniform sampler2D noise_texture : hint_default_white, filter_nearest;
uniform bool enable_brush_strokes : bool = true;
uniform bool enable_canvas_texture : bool = true;
uniform vec2 canvas_tiling : vec2(5.0, 5.0);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	UV = UV; // pass through
}

void fragment() {
	vec4 src_color = base_color * COLOR;

	// Apply canvas grain
	if (enable_canvas_texture) {
		vec2 canvas_uv = world_position.xz * canvas_tiling;
		float grain = texture(noise_texture, canvas_uv).r;
		src_color.rgb += (grain - 0.5) * 0.05 * brush_strength;
	}

	// Apply brush strokes (simulated with sine wave pattern)
	if (enable_brush_strokes) {
		float stroke = sin(world_position.x * brush_scale) * sin(world_position.y * brush_scale) * sin(world_position.z * brush_scale);
		stroke = stroke * 0.5 + 0.5; // normalize to 0-1
		vec3 stroke_color = mix(src_color.rgb, src_color.rgb * 0.8, stroke * brush_strength);
		src_color.rgb = stroke_color;
	}

	ALBEDO = src_color.rgb;
	ALPHA = src_color.a;
	EMISSION = src_color.rgb * 0.1; // subtle glow for painterly effect
}
