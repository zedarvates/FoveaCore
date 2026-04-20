shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform sampler2D roughness_map : hint_white, filter_linear_mipmap;

uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wet_amount : hint_range(0.0, 1.0) = 0.0;

uniform vec3 snow_color : source_color = vec3(0.95, 0.95, 0.98);
uniform vec3 moss_color : source_color = vec3(0.15, 0.35, 0.1);
uniform vec3 wet_color : source_color = vec3(0.3, 0.35, 0.4);

uniform float top_facing_threshold : hint_range(0.0, 1.0) = 0.7;
uniform float edge_threshold : hint_range(0.0, 1.0) = 0.3;
uniform float height_offset : hint_range(-2.0, 2.0) = 0.0;

uniform sampler2D height_map : hint_white, filter_linear_mipmap;
uniform float height_scale : hint_range(0.0, 1.0) = 0.1;

uniform vec3 light_direction : hint_vector3 = vec3(0.5, 1.0, 0.3);

varying vec3 world_normal;
varying vec3 world_pos;
varying vec2 uv_global;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	uv_global = UV;
}

void fragment() {
	vec3 albedo = texture(albedo_map, UV).rgb;
	float roughness = texture(roughness_map, UV).r;
	vec3 normal = texture(normal_map, UV).rgb * 2.0 - 1.0;
	
	vec3 N = normalize(mix(world_normal, normal, 0.5));
	vec3 L = normalize(light_direction);
	float NdotL = max(dot(N, L), 0.0);
	
	float top_mask = smoothstep(top_facing_threshold - 0.1, top_facing_threshold, N.y);
	
	float height = texture(height_map, UV).r;
	height += height_offset;
	float height_mask = smoothstep(0.5 - edge_threshold, 0.5 + edge_threshold, height);
	
	float edge_mask = 1.0 - abs(N.y);
	edge_mask = pow(edge_mask, 2.0);
	
	vec3 final_albedo = albedo;
	float final_roughness = roughness;
	vec3 final_emission = vec3(0.0);
	
	if (snow_amount > 0.0) {
		float snow_mask = top_mask * height_mask;
		snow_mask = clamp(snow_mask + edge_mask * 0.3, 0.0, 1.0);
		snow_mask *= snow_amount;
		
		final_albedo = mix(final_albedo, snow_color, snow_mask);
		final_roughness = mix(final_roughness, 0.9, snow_mask);
		
		float sparkle = fract(sin(dot(UV * 100.0, vec2(12.9898, 78.233))) * 0.5;
		final_emission += vec3(sparkle) * snow_mask * snow_amount;
	}
	
	if (moss_amount > 0.0) {
		float moss_noise = fract(sin(dot(UV * 50.0, vec2(12.9898, 78.233))) * 43758.5453);
		moss_noise = smoothstep(0.3, 0.7, moss_noise);
		
		float moss_mask = (1.0 - top_mask) * moss_noise * 0.5;
		moss_mask += top_mask * moss_amount * 0.3;
		moss_mask *= moss_amount;
		
		final_albedo = mix(final_albedo, moss_color, moss_mask);
		final_roughness = mix(final_roughness, 0.8, moss_mask);
	}
	
	if (wet_amount > 0.0) {
		float wet_mask = wet_amount;
		
		final_albedo = mix(final_albedo, wet_color, wet_mask * 0.5);
		final_roughness = mix(final_roughness, 0.1, wet_mask);
		
		float fresnel = pow(1.0 - max(dot(N, VIEW), 0.0), 3.0);
		final_emission += wet_color * fresnel * wet_mask * 0.3;
	}
	
	ALBEDO = final_albedo;
	ROUGHNESS = final_roughness;
	NORMAL = N * 0.5 + 0.5;
	EMISSION = final_emission;
}