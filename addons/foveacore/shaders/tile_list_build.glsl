#[compute]
#version 450
// FoveaEngine : tile_list_build.glsl (items 191-193)
// Builds per-tile splat lists in shared memory for tile rasterizer.

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
struct PackedSplat { uint data0, data1, data2, data3; };
layout(set = 0, binding = 0, std430) readonly buffer InputS { PackedSplat splats[]; };
layout(set = 0, binding = 1, std430) writeonly buffer TileList { uint tile_data[]; };
layout(set = 0, binding = 2, std430) readonly buffer CountBuf { uint count; };
layout(push_constant, std430) uniform P { uint total; uint tile_w; uint tile_h; float pad; } p;

shared uint local_list[256];
void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= p.total) return;
    PackedSplat s = splats[idx];
    // Tile assignment from screen-space position derived from splat position
    uint tile_x = (s.data0 & 0xFFFFu) * 16u / 65535u;
    uint tile_y = (s.data1 & 0xFFFFu) * 16u / 65535u;
    uint tile = tile_y * p.tile_w + tile_x;
    if (tile < p.tile_w * p.tile_h) {
        uint pos = atomicAdd(tile_data[tile * 256u], 1u);
        if (pos < 255u) tile_data[tile * 256u + 1u + pos] = idx;
    }
}
