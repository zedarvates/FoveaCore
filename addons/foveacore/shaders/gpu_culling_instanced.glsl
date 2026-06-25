#[compute]
#version 450

// FoveaEngine: gpu_culling_instanced.glsl
// Phase 3 — Global Splat Instancing: Instanced GPU Culling
//
// Performs culling for all instances of a single asset on the GPU.
// Single VRAM copy of asset splats, transformed on-the-fly.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0;
    uint data1;
    uint data2;
    uint data3;
};

struct OutputSplat {
    uint data0;
    uint data1;
    uint data2;
    uint data3;
    uint local_idx;
};

struct DeltaEntry {
    uint local_idx;
    uint pos_xy;
    uint pos_z;
    uint color;
};

struct InstanceParams {
    uint morph_type;
    float morph_weight;
    float morph_frequency;
    float morph_amplitude;
};

// 1. Unique asset splats buffer (size N)
layout(set = 0, binding = 0, std430) restrict readonly buffer InputSplats {
    PackedSplat input_data[];
};

// 2. Active instance transforms buffer (size M)
layout(set = 0, binding = 1, std430) restrict readonly buffer InstanceTransforms {
    mat4 transforms[];
};

// 3. Output buffer for surviving splats (size M * N)
layout(set = 0, binding = 2, std430) restrict writeonly buffer OutputSplats {
    OutputSplat output_data[];
};

// 4. Atomic counter
layout(set = 0, binding = 3, std430) restrict buffer CounterBuffer {
    uint valid_splat_count;
};

// 4. Instance deltas buffer (sparse overrides)
layout(set = 0, binding = 4, std430) restrict readonly buffer InstanceDeltas {
    DeltaEntry deltas[];
};

// 5. Delta offsets buffer (offsets to start of deltas for each instance)
layout(set = 0, binding = 5, std430) restrict readonly buffer DeltaOffsets {
    uint delta_offsets[];
};

// 6. Instance params buffer (morphing parameters)
layout(set = 0, binding = 6, std430) restrict readonly buffer InstanceParamsBuffer {
    InstanceParams instance_params[];
};

// 7. Visible instance indices buffer (size M)
layout(set = 0, binding = 7, std430) restrict readonly buffer VisibleInstanceIndices {
    uint visible_indices[];
};

// 8. Visible instance counter
layout(set = 0, binding = 8, std430) restrict readonly buffer VisibleInstanceCounter {
    uint visible_instances_count;
};

// 5. Scene depth map for Hi-Z
layout(set = 1, binding = 0) uniform sampler2D depth_map;

// 6. Camera matrices
layout(set = 1, binding = 1, std140) uniform CameraData {
    mat4 view_proj_left;
    mat4 view_proj_right;
} camera;

layout(push_constant, std430) uniform Params {
    vec3 camera_position;
    uint asset_splat_count;
    uint active_instances;
    float backface_threshold;
    vec3 aabb_min;
    uint use_gpu_instance_culling;
    vec3 aabb_max;
    float pad1;
} params;

float decode_half(uint half_bits) {
    uint sign = (half_bits >> 15) & 1u;
    uint exponent = (half_bits >> 10) & 0x1Fu;
    uint mantissa = half_bits & 0x3FFu;
    if (exponent == 0) {
        return 0.0;
    } else if (exponent == 31) {
        return sign == 1u ? -65504.0 : 65504.0; // clamp half infinity
    }
    float val = (1.0 + float(mantissa) / 1024.0) * pow(2.0, float(exponent) - 15.0);
    return sign == 1u ? -val : val;
}

void main() {
    uint index = gl_GlobalInvocationID.x;
    uint total_threads = params.asset_splat_count * params.active_instances;
    if (index >= total_threads) return;

    uint instance_id = index / params.asset_splat_count;
    uint local_idx = index % params.asset_splat_count;

    uint actual_instance_id = instance_id;
    if (params.use_gpu_instance_culling == 1u) {
        if (instance_id >= visible_instances_count) return;
        actual_instance_id = visible_indices[instance_id];
    }

    PackedSplat splat = input_data[local_idx];
    mat4 transform = transforms[actual_instance_id];

    // --- 1. DEQUANTIZE LOCAL POSITION ---
    uint qx = splat.data0 & 0xFFFFu;
    uint qy = (splat.data0 >> 16u) & 0xFFFFu;
    uint qz = splat.data1 & 0xFFFFu;
    
    vec3 q_pos = vec3(float(qx), float(qy), float(qz)) / 65535.0;
    vec3 local_pos = params.aabb_min + q_pos * (params.aabb_max - params.aabb_min);

    // --- 2. DEQUANTIZE & DECODE NORMAL ---
    uint norm_u_bits = (splat.data1 >> 16u) & 0xFFu;
    uint norm_v_bits = (splat.data1 >> 24u) & 0xFFu;
    float u = float(norm_u_bits) / 255.0 * 2.0 - 1.0;
    float v = float(norm_v_bits) / 255.0 * 2.0 - 1.0;
    float z_coord = 1.0 - abs(u) - abs(v);
    float x = u, y = v;
    if (z_coord < 0.0) {
        float old_x = x;
        x = (1.0 - abs(y)) * sign(x);
        y = (1.0 - abs(old_x)) * sign(y);
    }
    vec3 local_normal = normalize(vec3(x, y, z_coord));

    // --- 3. APPLY SPARSE DELTA POSITION & COLOR OVERRIDES ---
    uint start_offset = delta_offsets[actual_instance_id];
    uint end_offset = delta_offsets[actual_instance_id + 1];
    vec3 pos_delta = vec3(0.0);
    uint color_delta_packed = 0xFFFFFFFFu;
    bool has_color_delta = false;

    for (uint j = start_offset; j < end_offset; ++j) {
        if (deltas[j].local_idx == local_idx) {
            uint pos_xy = deltas[j].pos_xy;
            uint pos_z = deltas[j].pos_z;
            pos_delta.x = decode_half(pos_xy & 0xFFFFu);
            pos_delta.y = decode_half((pos_xy >> 16u) & 0xFFFFu);
            pos_delta.z = decode_half(pos_z & 0xFFFFu);
            
            color_delta_packed = deltas[j].color;
            has_color_delta = true;
            break;
        }
    }
    local_pos += pos_delta;

    // --- 4. APPLY INSTANCE MORPH ANIMATION ---
    InstanceParams ip = instance_params[actual_instance_id];
    uint morph_type = ip.morph_type;
    float morph_weight = ip.morph_weight;
    float morph_frequency = ip.morph_frequency;
    float morph_amplitude = ip.morph_amplitude;

    if (morph_type > 0u && morph_weight > 0.0) {
        if (morph_type == 1u) { // Bend
            float offset_x = sin(local_pos.y * morph_frequency) * morph_amplitude * morph_weight;
            local_pos.x += offset_x;
            float angle = cos(local_pos.y * morph_frequency) * morph_amplitude * morph_weight * morph_frequency;
            float cos_a = cos(angle);
            float sin_a = sin(angle);
            local_normal = vec3(
                local_normal.x * cos_a - local_normal.y * sin_a,
                local_normal.x * sin_a + local_normal.y * cos_a,
                local_normal.z
            );
        }
        else if (morph_type == 2u) { // Twist
            float angle = local_pos.y * morph_frequency * morph_weight * morph_amplitude;
            float cos_a = cos(angle);
            float sin_a = sin(angle);
            local_pos = vec3(
                local_pos.x * cos_a - local_pos.z * sin_a,
                local_pos.y,
                local_pos.x * sin_a + local_pos.z * cos_a
            );
            local_normal = vec3(
                local_normal.x * cos_a - local_normal.z * sin_a,
                local_normal.y,
                local_normal.x * sin_a + local_normal.z * cos_a
            );
        }
        else if (morph_type == 3u) { // Squish
            float factor_y = 1.0 - (morph_weight * morph_amplitude);
            float factor_xz = 1.0 + (morph_weight * morph_amplitude * 0.5);
            local_pos.y *= factor_y;
            local_pos.x *= factor_xz;
            local_pos.z *= factor_xz;
            local_normal = normalize(vec3(local_normal.x / factor_xz, local_normal.y / factor_y, local_normal.z / factor_xz));
        }
        else if (morph_type == 4u) { // Wave
            float wave_angle = (local_pos.x + local_pos.z) * morph_frequency;
            local_pos.y += sin(wave_angle) * morph_amplitude * morph_weight;
            float deriv_x = cos(wave_angle) * morph_frequency * morph_amplitude * morph_weight;
            local_normal = normalize(local_normal - vec3(deriv_x, 0.0, deriv_x));
        }
    }

    // --- 5. APPLY INSTANCE TRANSFORM ---
    vec4 world_pos_4 = transform * vec4(local_pos, 1.0);
    vec3 world_pos = world_pos_4.xyz;
    vec3 world_normal = normalize(mat3(transform) * local_normal);

    // --- 6. BACKFACE CULLING ---
    vec3 view_dir = normalize(world_pos - params.camera_position);
    float NdotV = dot(world_normal, view_dir);
    if (NdotV > params.backface_threshold) return;

    // --- 7. STEREOSCOPIC FRUSTUM CULLING ---
    vec4 clip_left = camera.view_proj_left * vec4(world_pos, 1.0);
    vec3 ndc_left = clip_left.xyz / clip_left.w;
    
    vec4 clip_right = camera.view_proj_right * vec4(world_pos, 1.0);
    vec3 ndc_right = clip_right.xyz / clip_right.w;
    
    bool visible_left = (abs(ndc_left.x) < 1.0 && abs(ndc_left.y) < 1.0 && ndc_left.z > 0.0 && ndc_left.z < 1.0);
    bool visible_right = (abs(ndc_right.x) < 1.0 && abs(ndc_right.y) < 1.0 && ndc_right.z > 0.0 && ndc_right.z < 1.0);

    if (!visible_left && !visible_right) return;

    // --- 8. HI-Z OCCLUSION CULLING ---
    if (visible_left) {
        vec2 screen_uv = ndc_left.xy * 0.5 + 0.5;
        float scene_depth = textureLod(depth_map, vec2(screen_uv.x * 0.5, screen_uv.y), 0.0).r;
        if (ndc_left.z > scene_depth + 0.001) return;
    }

    // --- 9. WRITE TO OUTPUT WITH INSTANCE ID TAGGED ---
    uint out_index = atomicAdd(valid_splat_count, 1);
    
    OutputSplat out_splat;
    out_splat.data0 = splat.data0;
    out_splat.data1 = splat.data1;
    out_splat.data2 = splat.data2;
    
    // Apply sparse color override on GPU output if present
    if (has_color_delta) {
        // Extract color RGB565 from data2 and multiply by delta color
        uint color_index = splat.data2 & 0xFFFFu;
        float r_val = float((color_index >> 11u) & 0x1Fu) / 31.0;
        float g_val = float((color_index >> 5u) & 0x3Fu) / 63.0;
        float b_val = float(color_index & 0x1Fu) / 31.0;
        
        float delta_r = float((color_delta_packed >> 24u) & 0xFFu) / 255.0;
        float delta_g = float((color_delta_packed >> 16u) & 0xFFu) / 255.0;
        float delta_b = float((color_delta_packed >> 8u) & 0xFFu) / 255.0;
        
        uint r5 = uint(clamp(r_val * delta_r * 31.0, 0.0, 31.0));
        uint g6 = uint(clamp(g_val * delta_g * 63.0, 0.0, 63.0));
        uint b5 = uint(clamp(b_val * delta_b * 31.0, 0.0, 31.0));
        uint new_rgb565 = (r5 << 11u) | (g6 << 5u) | b5;
        
        out_splat.data2 = (splat.data2 & 0xFFFF0000u) | new_rgb565;
    }
    
    out_splat.data3 = (splat.data3 & 0x0000FFFFu) | (actual_instance_id << 16u);
    out_splat.local_idx = local_idx;
    
    output_data[out_index] = out_splat;
}
