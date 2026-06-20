#[compute]
#version 450

// FoveaEngine: GPU-Driven Publish Shader
// Copies culled/sorted storage buffer data to textures for gdshader usage.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0;
    uint data1;
    uint data2;
    uint data3;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer SourceSplats {
    PackedSplat source_data[];
};

layout(set = 0, binding = 1, std430) restrict readonly buffer CounterBuffer {
    uint valid_splat_count;
};

layout(set = 0, binding = 2, rgba32ui) uniform writeonly uimage2D dest_texture;
layout(set = 0, binding = 3, r32ui) uniform writeonly uimage2D dest_counter_texture;

void main() {
    uint index = gl_GlobalInvocationID.x;
    
    // Thread 0 writes the counter
    if (index == 0) {
        imageStore(dest_counter_texture, ivec2(0, 0), uvec4(valid_splat_count, 0, 0, 0));
    }
    
    if (index >= valid_splat_count) return;
    
    PackedSplat splat = source_data[index];
    ivec2 tex_coord = ivec2(int(index % 1024), int(index / 1024));
    imageStore(dest_texture, tex_coord, uvec4(splat.data0, splat.data1, splat.data2, splat.data3));
}
