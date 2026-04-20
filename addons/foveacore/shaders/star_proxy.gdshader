shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D depth_map : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D albedo_map : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float depth_scale = 0.5;
uniform float radius = 0.5;
uniform float falloff = 4.0;
uniform vec4 base_color : source_color = vec4(1.0);

uniform int debug_mode = 0;
uniform float debug_scale = 1.0;
uniform vec4 debug_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);

varying vec3 view_dir_local;
varying vec3 world_pos;
varying vec2 uv_interp;

void vertex() {
    view_dir_local = normalize(inverse(MODEL_MATRIX) * vec4(VIEW, 0.0)).xyz;
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    uv_interp = UV;
}

void fragment() {
    vec2 centered_uv = UV - vec2(0.5);
    float dist = length(centered_uv) / radius;
    
    float d = texture(depth_map, UV).r;
    vec2 parallax_offset = (VIEW * inverse(MODELVIEW_MATRIX)).xy * d * depth_scale;
    vec2 shifted_uv = UV + parallax_offset;
    
    vec4 tex = texture(albedo_map, shifted_uv);
    
    float alpha = exp(-dist * dist * falloff);
    
    if (debug_mode == 1) {
        vec3 normal_sample = texture(depth_map, UV).rgb;
        float ring_dist = fract(dist * 8.0);
        float ring = smoothstep(0.0, 0.1, ring_dist) - smoothstep(0.1, 0.2, ring_dist);
        ALBEDO = mix(vec3(0.0), debug_color.rgb, ring * debug_scale);
        ALPHA = ring * base_color.a;
    } else if (debug_mode == 2) {
        vec3 center_color = debug_color.rgb;
        float center_dot = 1.0 - smoothstep(0.0, 0.05, dist);
        ALBEDO = mix(vec3(0.2), center_color, center_dot);
        ALPHA = base_color.a;
    } else if (debug_mode == 3) {
        float heatmap = d * 3.0;
        vec3 cold = vec3(0.0, 0.0, 1.0);
        vec3 mid = vec3(0.0, 1.0, 0.0);
        vec3 hot = vec3(1.0, 0.0, 0.0);
        if (heatmap < 0.5) {
            ALBEDO = mix(cold, mid, heatmap * 2.0);
        } else {
            ALBEDO = mix(mid, hot, (heatmap - 0.5) * 2.0);
        }
        ALPHA = base_color.a;
    } else if (debug_mode == 4) {
        float depth_viz = smoothstep(0.0, 1.0, d);
        ALBEDO = vec3(depth_viz);
        ALPHA = base_color.a;
    } else if (debug_mode == 5) {
        float top_facing = NORMAL.y;
        vec3 top_color = debug_color.rgb;
        vec3 side_color = vec3(0.5, 0.5, 0.5);
        ALBEDO = mix(side_color, top_color, smoothstep(0.7, 1.0, top_facing));
        ALPHA = base_color.a;
        ROUGHNESS = 1.0 - smoothstep(0.7, 1.0, top_facing);
    } else {
        ALBEDO = tex.rgb * base_color.rgb;
        ALPHA = alpha * tex.a * base_color.a;
    }

    if (dist > 1.0 && debug_mode == 0) {
        discard;
    }
}
