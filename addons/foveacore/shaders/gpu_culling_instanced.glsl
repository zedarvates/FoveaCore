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
    float pad0;
    vec3 aabb_max;
    float pad1;
} params;

void main() {
    uint index = gl_GlobalInvocationID.x;
    uint total_threads = params.asset_splat_count * params.active_instances;
    if (index >= total_threads) return;

    uint instance_id = index / params.asset_splat_count;
    uint local_idx = index % params.asset_splat_count;

    PackedSplat splat = input_data[local_idx];
    mat4 transform = transforms[instance_id];

    // --- 1. DEQUANTIZE LOCAL POSITION ---
    uint qx = splat.data0 & 0xFFFFu;
    uint qy = (splat.data0 >> 16u) & 0xFFFFu;
    uint qz = splat.data1 & 0xFFFFu;
    
    vec3 q_pos = vec3(float(qx), float(qy), float(qz)) / 65535.0;
    vec3 local_pos = params.aabb_min + q_pos * (params.aabb_max - params.aabb_min);

    // --- 2. APPLY INSTANCE TRANSFORM ---
    vec4 world_pos_4 = transform * vec4(local_pos, 1.0);
    vec3 world_pos = world_pos_4.xyz;

    // --- 3. DEQUANTIZE & ROTATE NORMAL ---
    uint norm_u_bits = (splat.data1 >> 16u) & 0xFFu;
    uint norm_v_bits = (splat.data1 >> 24u) & 0xFFu;
    float u = float(norm_u_bits) / 255.0 * 2.0 - 1.0;
    float v = float(norm_v_bits) / 255.0 * 2.0 - 1.0;
    float z = 1.0 - abs(u) - abs(v);
    float x = u, y = v;
    if (z < 0.0) {
        float old_x = x;
        x = (1.0 - abs(y)) * sign(x);
        y = (1.0 - abs(old_x)) * sign(y);
    }
    vec3 local_normal = normalize(vec3(x, y, z));
    // Rotate normal using the instance transform (upper 3x3)
    vec3 world_normal = normalize(mat3(transform) * local_normal);

    // --- 4. BACKFACE CULLING ---
    vec3 view_dir = normalize(world_pos - params.camera_position);
    float NdotV = dot(world_normal, view_dir);
    if (NdotV > params.backface_threshold) return;

    // --- 5. STEREOSCOPIC FRUSTUM CULLING ---
    vec4 clip_left = camera.view_proj_left * vec4(world_pos, 1.0);
    vec3 ndc_left = clip_left.xyz / clip_left.w;
    
    vec4 clip_right = camera.view_proj_right * vec4(world_pos, 1.0);
    vec3 ndc_right = clip_right.xyz / clip_right.w;
    
    bool visible_left = (abs(ndc_left.x) < 1.0 && abs(ndc_left.y) < 1.0 && ndc_left.z > 0.0 && ndc_left.z < 1.0);
    bool visible_right = (abs(ndc_right.x) < 1.0 && abs(ndc_right.y) < 1.0 && ndc_right.z > 0.0 && ndc_right.z < 1.0);

    if (!visible_left && !visible_right) return;

    // --- 6. HI-Z OCCLUSION CULLING ---
    if (visible_left) {
        vec2 screen_uv = ndc_left.xy * 0.5 + 0.5;
        float scene_depth = textureLod(depth_map, vec2(screen_uv.x * 0.5, screen_uv.y), 0.0).r;
        if (ndc_left.z > scene_depth + 0.001) return;
    }

    // --- 7. WRITE TO OUTPUT WITH INSTANCE ID TAGGED ---
    uint out_index = atomicAdd(valid_splat_count, 1);
    
    OutputSplat out_splat;
    out_splat.data0 = splat.data0;
    out_splat.data1 = splat.data1;
    out_splat.data2 = splat.data2;
    out_splat.data3 = (splat.data3 & 0x0000FFFFu) | (instance_id << 16u);
    out_splat.local_idx = local_idx;
    
    output_data[out_index] = out_splat;
}
}
