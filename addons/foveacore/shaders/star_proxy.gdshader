shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D depth_map : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform sampler2D albedo_map : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float depth_scale = 0.5;
uniform float radius = 0.5;
uniform float falloff = 4.0;
uniform vec4 base_color : source_color = vec4(1.0);

varying vec3 view_dir_local;

void vertex() {
    // We want the view direction in local space of the quad
    view_dir_local = normalize(inverse(MODEL_MATRIX) * vec4(VIEW, 0.0)).xyz;
}

void fragment() {
    // 1. Centered UVs for the Gaussian blob
    vec2 centered_uv = UV - vec2(0.5);
    float dist = length(centered_uv) / radius;
    
    // 2. Parallax Mapping using the DA3 Depth Map
    // We offset the UV lookup based on the view direction and the depth
    float d = texture(depth_map, UV).r;
    vec2 parallax_offset = view_dir_local.xy * d * depth_scale;
    vec2 shifted_uv = UV + parallax_offset;
    
    // 3. Sampling Albedo and Depth from the shifted position
    vec4 tex = texture(albedo_map, shifted_uv);
    
    // 4. Gaussian Alpha Falloff
    float alpha = exp(-dist * dist * falloff);
    
    ALBEDO = tex.rgb * base_color.rgb;
    ALPHA = alpha * tex.a * base_color.a;

    // Discard outside radius
    if (dist > 1.0) {
        discard;
    }
}
