#[compute]
#version 450

// ============================================================================
// FoveaEngine : publish_splats.glsl
// Copie GPU-Driven asynchrone des splats culled vers des textures VRAM.
// ============================================================================

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// Matches gpu_culling_instanced.glsl OutputSplat (24 bytes). The trailing
// runtime metadata is deliberately not published into the 16-byte texture.
struct OutputSplat {
    uint data0;
    uint data1;
    uint data2;
    uint data3;
    uint local_idx;
    uint instance_id;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer SourceSplats {
    OutputSplat splats[];
};

layout(set = 0, binding = 1, std430) restrict readonly buffer CounterBuffer {
    uint valid_splat_count;
};

layout(set = 0, binding = 2, rgba32ui) uniform writeonly uimage2D dest_texture;
layout(set = 0, binding = 3, r32ui) uniform writeonly uimage2D dest_counter;

void main() {
    uint idx = gl_GlobalInvocationID.x;
    
    // Le premier thread écrit la valeur du compteur dans la texture mono-canal
    if (idx == 0) {
        imageStore(dest_counter, ivec2(0, 0), uvec4(valid_splat_count, 0, 0, 0));
    }
    
    if (idx >= valid_splat_count) {
        return;
    }
    
    OutputSplat s = splats[idx];
    
    // Indexation 2D de la texture avec une largeur fixe de 1024
    int tex_x = int(idx % 1024);
    int tex_y = int(idx / 1024);
    
    uvec4 pixel_val = uvec4(s.data0, s.data1, s.data2, s.data3);
    imageStore(dest_texture, ivec2(tex_x, tex_y), pixel_val);
}
