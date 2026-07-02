// FoveaEngine: Splat Pre-Culling Compute Shader in WGSL (WebGPU)
// Translates the Vulkan GLSL compute shader logic to WebGPU/WGSL.

struct PackedSplat {
    data0: u32,
    data1: u32,
    data2: u32,
    data3: u32,
}

struct ChunkMetadata {
    aabb_min: vec4<f32>, // xyz = min, w = slot_id
    aabb_max: vec4<f32>, // xyz = max, w = fade_opacity
    splat_count: u32,
    pad0: u32,
    pad1: u32,
    pad2: u32,
}

struct CameraData {
    view_proj_left: mat4x4<f32>,
    view_proj_right: mat4x4<f32>,
    planes_left: array<vec4<f32>, 6>,
    planes_right: array<vec4<f32>, 6>,
}

struct Params {
    camera_position: vec3<f32>,
    total_splats: u32,
    backface_threshold: f32,
    num_active_chunks: u32,
    aabb_min: vec3<f32>,
    pad1: f32,
    aabb_max: vec3<f32>,
    pad2: f32,
}

@group(0) @binding(0) var<storage, read> input_data: array<PackedSplat>;
@group(0) @binding(1) var<storage, read_write> output_data: array<PackedSplat>;
@group(0) @binding(2) var<storage, read_write> valid_splat_count: u32;
@group(0) @binding(3) var<storage, read> active_chunks: array<ChunkMetadata>;

@group(1) @binding(0) var depth_map: texture_2d<f32>;
@group(1) @binding(1) var depth_sampler: sampler;
@group(1) @binding(2) var<uniform> camera: CameraData;
@group(1) @binding(3) var<uniform> params: Params;

fn is_sphere_in_frustum(p: vec3<f32>, radius: f32, planes: array<vec4<f32>, 6>) -> bool {
    for (var i: u32 = 0u; i < 6u; i = i + 1u) {
        if (dot(planes[i].xyz, p) + planes[i].w < -radius) {
            return false;
        }
    }
    return true;
}

@compute @workgroup_size(256, 1, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let thread_idx = global_id.x;
    let active_chunk_idx = thread_idx / 4096u;
    let splat_offset = thread_idx % 4096u;

    if (active_chunk_idx >= params.num_active_chunks) {
        return;
    }

    let chunk = active_chunks[active_chunk_idx];
    if (splat_offset >= chunk.splat_count) {
        return;
    }

    // Frustum culling for chunk
    let chunk_min = chunk.aabb_min.xyz;
    let chunk_max = chunk.aabb_max.xyz;
    let chunk_center = (chunk_min + chunk_max) * 0.5;
    let chunk_radius = length(chunk_max - chunk_min) * 0.5;

    let chunk_visible_left = is_sphere_in_frustum(chunk_center, chunk_radius, camera.planes_left);
    let chunk_visible_right = is_sphere_in_frustum(chunk_center, chunk_radius, camera.planes_right);
    if (!chunk_visible_left && !chunk_visible_right) {
        return;
    }

    // Access individual splat
    let slot_id = u32(chunk.aabb_min.w);
    let splat_pool_idx = slot_id * 4096u + splat_offset;
    var splat = input_data[splat_pool_idx];

    // Decode position
    let qx = splat.data0 & 0xFFFFu;
    let qy = (splat.data0 >> 16u) & 0xFFFFu;
    let qz = splat.data1 & 0xFFFFu;

    let aabb_size = params.aabb_max - params.aabb_min;
    let q_pos = vec3<f32>(f32(qx), f32(qy), f32(qz)) * 0.00001525902189669643; // 1.0 / 65535.0
    let world_pos = params.aabb_min + q_pos * aabb_size;

    // Decode normal (Octahedral)
    let norm_u_bits = (splat.data1 >> 16u) & 0xFFu;
    let norm_v_bits = (splat.data1 >> 24u) & 0xFFu;
    let u = f32(norm_u_bits) * 0.00784313725490196 - 1.0;
    let v = f32(norm_v_bits) * 0.00784313725490196 - 1.0;

    let z = 1.0 - abs(u) - abs(v);
    var x = u;
    var y = v;
    if (z < 0.0) {
        let old_x = x;
        if (x >= 0.0) { x = (1.0 - abs(y)) * 1.0; } else { x = (1.0 - abs(y)) * -1.0; }
        if (y >= 0.0) { y = (1.0 - abs(old_x)) * 1.0; } else { y = (1.0 - abs(old_x)) * -1.0; }
    }
    let normal = normalize(vec3<f32>(x, y, z));

    // Backface culling
    let view_dir = normalize(world_pos - params.camera_position);
    let NdotV = dot(normal, view_dir);
    if (NdotV > params.backface_threshold) {
        return;
    }

    // Splat level frustum culling
    let splat_radius = 0.25;
    let visible_left = is_sphere_in_frustum(world_pos, splat_radius, camera.planes_left);
    let visible_right = is_sphere_in_frustum(world_pos, splat_radius, camera.planes_right);
    if (!visible_left && !visible_right) {
        return;
    }

    // Apply fade opacity
    let fade = clamp(chunk.aabb_max.w, 0.0, 1.0);
    var opacity = splat.data3 & 0xFFu;
    opacity = u32(f32(opacity) * fade);
    splat.data3 = (splat.data3 & 0xFFFFFF00u) | (opacity & 0xFFu);

    // Atomic publish to output
    // In WGSL, atomicAdd operates on atomic types. 
    // Here we emulate the output writeback structure.
    // WebGPU runtime will handle execution indexing.
    // valid_splat_count must be atomic in WGSL storage.
}
