#[compute]
#version 450

// Experimental Fovea4D position-only motion pass. File records are repacked
// from three int16 values (6 bytes) to one std430-safe uvec2 (8 bytes).
layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) readonly buffer BaseSplats {
    uvec4 base_splats[];
};

layout(set = 0, binding = 1, std430) writeonly buffer AnimatedSplats {
    uvec4 animated_splats[];
};

layout(set = 0, binding = 2, std430) readonly buffer MotionField {
    uvec2 motion_cells[];
};

layout(set = 0, binding = 3, std430) readonly buffer MotionParams {
    // x=splat count, y/z/w=grid dimensions.
    uvec4 counts;
    // w fields carry keyframe count, sample rate, loop flag, and padding.
    vec4 base_min;
    vec4 base_max;
    vec4 animated_min;
    vec4 animated_max;
    // xyz=displacement scale, w=playback time in seconds.
    vec4 scale_time;
    vec4 field_min;
    vec4 field_max;
} params;


int decode_i16(uint value) {
    return int(value << 16u) >> 16;
}


vec3 decode_motion(uint cell_index) {
    uvec2 packed = motion_cells[cell_index];
    return vec3(
        float(decode_i16(packed.x & 0xffffu)),
        float(decode_i16((packed.x >> 16u) & 0xffffu)),
        float(decode_i16(packed.y & 0xffffu))
    ) * params.scale_time.xyz;
}


uint motion_index(uvec3 cell, uint keyframe) {
    uvec3 dims = params.counts.yzw;
    uint cells_per_frame = dims.x * dims.y * dims.z;
    // X-fastest spatial order: x + dims.x * (y + dims.y * z).
    // Keyframe-major order: keyframe * cells_per_frame + spatial index.
    return keyframe * cells_per_frame + cell.x + dims.x * (cell.y + dims.y * cell.z);
}


vec3 sample_frame(uvec3 lower, vec3 weight, uint keyframe) {
    vec3 c000 = decode_motion(motion_index(lower, keyframe));
    vec3 c100 = decode_motion(motion_index(lower + uvec3(1u, 0u, 0u), keyframe));
    vec3 c010 = decode_motion(motion_index(lower + uvec3(0u, 1u, 0u), keyframe));
    vec3 c110 = decode_motion(motion_index(lower + uvec3(1u, 1u, 0u), keyframe));
    vec3 c001 = decode_motion(motion_index(lower + uvec3(0u, 0u, 1u), keyframe));
    vec3 c101 = decode_motion(motion_index(lower + uvec3(1u, 0u, 1u), keyframe));
    vec3 c011 = decode_motion(motion_index(lower + uvec3(0u, 1u, 1u), keyframe));
    vec3 c111 = decode_motion(motion_index(lower + uvec3(1u, 1u, 1u), keyframe));
    vec3 c00 = mix(c000, c100, weight.x);
    vec3 c10 = mix(c010, c110, weight.x);
    vec3 c01 = mix(c001, c101, weight.x);
    vec3 c11 = mix(c011, c111, weight.x);
    return mix(mix(c00, c10, weight.y), mix(c01, c11, weight.y), weight.z);
}


void main() {
    uint splat_index = gl_GlobalInvocationID.x;
    if (splat_index >= params.counts.x) {
        return;
    }

    uvec4 splat = base_splats[splat_index];
    vec3 base_extent = params.base_max.xyz - params.base_min.xyz;
    vec3 quantized = vec3(
        float(splat.x & 0xffffu),
        float((splat.x >> 16u) & 0xffffu),
        float(splat.y & 0xffffu)
    ) / 65535.0;
    vec3 base_position = params.base_min.xyz + quantized * base_extent;

    vec3 field_extent = params.field_max.xyz - params.field_min.xyz;
    vec3 safe_field_extent = max(abs(field_extent), vec3(1e-8));
    vec3 normalized = clamp((base_position - params.field_min.xyz) / safe_field_extent, 0.0, 1.0);
    normalized = mix(normalized, vec3(0.0), lessThanEqual(abs(field_extent), vec3(1e-8)));
    uvec3 dims = params.counts.yzw;
    vec3 coordinate = normalized * vec3(dims - uvec3(1u));
    uvec3 lower = min(uvec3(floor(coordinate)), dims - uvec3(2u));
    vec3 spatial_weight = coordinate - vec3(lower);

    uint keyframe_count = uint(params.base_min.w);
    float frame_coordinate = params.scale_time.w * params.base_max.w;
    bool loop = params.animated_min.w > 0.5;
    if (loop) {
        frame_coordinate = mod(frame_coordinate, float(keyframe_count));
    } else {
        frame_coordinate = clamp(frame_coordinate, 0.0, float(keyframe_count - 1u));
    }
    uint first_frame = uint(floor(frame_coordinate));
    uint second_frame = loop
        ? (first_frame + 1u) % keyframe_count
        : min(first_frame + 1u, keyframe_count - 1u);
    float temporal_weight = frame_coordinate - float(first_frame);
    vec3 offset0 = sample_frame(lower, spatial_weight, first_frame);
    vec3 offset1 = sample_frame(lower, spatial_weight, second_frame);
    vec3 animated_position = base_position + mix(offset0, offset1, temporal_weight);

    vec3 animated_extent = params.animated_max.xyz - params.animated_min.xyz;
    vec3 safe_animated_extent = max(abs(animated_extent), vec3(1e-8));
    vec3 animated_quantized = clamp(
        (animated_position - params.animated_min.xyz) / safe_animated_extent,
        0.0,
        1.0
    );
    animated_quantized = mix(animated_quantized, vec3(0.0), lessThanEqual(abs(animated_extent), vec3(1e-8)));
    uvec3 encoded = uvec3(animated_quantized * 65535.0 + 0.5);
    splat.x = encoded.x | (encoded.y << 16u);
    splat.y = encoded.z | (splat.y & 0xffff0000u);
    animated_splats[splat_index] = splat;
}
