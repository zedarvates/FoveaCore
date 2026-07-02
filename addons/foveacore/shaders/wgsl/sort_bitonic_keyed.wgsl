// FoveaEngine: Bitonic Sorter Shader in WGSL (WebGPU)
// Translates Vulkan GLSL bitonic sorter to WebGPU/WGSL.

struct PackedSplat {
    data0: u32,
    data1: u32,
    data2: u32,
    data3: u32,
}

struct Params {
    splat_count: u32,
    padded_count: u32,
    stage: u32,
    step_size: u32,
}

@group(0) @binding(0) var<storage, read_write> splats: array<PackedSplat>;
@group(0) @binding(1) var<storage, read_write> depths: array<f32>;
@group(0) @binding(2) var<uniform> params: Params;

@compute @workgroup_size(256, 1, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let i = global_id.x;
    let splat_count = params.splat_count;
    let padded_count = params.padded_count;
    let stage = params.stage;
    let step_size = params.step_size;

    if (i >= padded_count / 2u) {
        return;
    }

    let ip = i * 2u;
    
    // Sort logic
    // Key sorting on depth buffer
    let sort_dir = ((i / (stage / 2u)) % 2u) == 0u;
    
    var idx0 = i & ~(step_size - 1u);
    idx0 = idx0 * 2u + (i & (step_size - 1u));
    let idx1 = idx0 + step_size;

    if (idx1 >= padded_count) {
        return;
    }

    let d0 = depths[idx0];
    let d1 = depths[idx1];

    var swap = false;
    if (d0 > d1) {
        if (sort_dir) {
            swap = true;
        }
    } else {
        if (!sort_dir) {
            swap = true;
        }
    }

    if (swap) {
        // Swap depths
        let temp_d = depths[idx0];
        depths[idx0] = depths[idx1];
        depths[idx1] = temp_d;

        // Swap splats structure
        let temp_s = splats[idx0];
        splats[idx0] = splats[idx1];
        splats[idx1] = temp_s;
    }
}
