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
    uint stage;       // Étape actuelle (0 .. log2(N)-1)
    uint pad0;
    uint pad1;
} pc;

void main() {
    uint gid = gl_GlobalInvocationID.x;
    if (gid >= pc.total_count) return;

    // k = 2^(stage+1)
    uint k = 1u << (pc.stage + 1u);
    // j = moitié de k, puis décale
    uint j = k >> 1;

    while (j > 0u) {
        uint ixj = gid ^ j;
        if (ixj > gid && ixj < pc.total_count) {
            // Direction : les blocs de taille k alternent asc/desc
            bool ascending = ((gid & k) == 0u);

            float d_i = depths[gid];
            float d_j = depths[ixj];

            // Pour tri ascendant : on veut d_i <= d_j
            // Si ascending, swap si d_i > d_j
            // Si descending, swap si d_i < d_j
            bool need_swap = ascending ? (d_i > d_j) : (d_i < d_j);

            if (need_swap) {
                // Swap depths
                float tmp_d = d_i;
                depths[gid] = d_j;
                depths[ixj] = tmp_d;

                // Swap indices
                uint tmp_i = indices[gid];
                indices[gid] = indices[ixj];
                indices[ixj] = tmp_i;
            }
        }
        j >>= 1;
    }
}
