#[compute]
#version 450

layout(local_size_x = 256) in;

// Storage buffers : depths et indices
layout(binding = 0) buffer DepthBuffer {
    float depths[];
};

layout(binding = 1) buffer IndexBuffer {
    uint indices[];
};

// Push constants
layout(push_constant) uniform PushConsts {
    uint total_count;  // Nombre d'éléments (puissance de 2)
    uint sequence_length; // k: longueur de la séquence bitonique courante
    uint compare_distance; // j: distance du compare-exchange courant
    uint pad1;
} pc;

void main() {
    uint gid = gl_GlobalInvocationID.x;
    if (gid >= pc.total_count) return;

    // Each dispatch performs exactly one compare-exchange pass. The caller
    // inserts a device barrier between passes; a shader-side loop cannot
    // synchronize different 256-thread workgroups and produced corrupt
    // permutations for real assets larger than one workgroup.
    uint ixj = gid ^ pc.compare_distance;
    if (ixj <= gid || ixj >= pc.total_count) return;

    bool ascending = ((gid & pc.sequence_length) == 0u);
    float d_i = depths[gid];
    float d_j = depths[ixj];
    bool need_swap = ascending ? (d_i > d_j) : (d_i < d_j);

    if (need_swap) {
        depths[gid] = d_j;
        depths[ixj] = d_i;

        uint tmp_i = indices[gid];
        indices[gid] = indices[ixj];
        indices[ixj] = tmp_i;
    }
}
