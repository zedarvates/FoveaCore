#[compute]
#version 450

// ============================================================================
// FoveaEngine: sort_bitonic_keyed.glsl
// Phase 3 — Tri bitonique avec clés de profondeur pré-calculées
//
// Différences vs sort_bitonic_splats.glsl (legacy) :
//
//   LEGACY : chaque comparaison décode 3 × uint16 de position + 10 ALU ops
//            pour calculer la distance caméra → ~12 ops × O(N·log²N) comparaisons
//
//   KEYED  : chaque comparaison lit 2 floats depuis le buffer depths[]
//            → O(N) calculs de distance en amont (depth_precompute.glsl)
//               + O(N·log²N) × 1 load float pendant le tri
//            Réduction ~4-6x de la bande passante de lecture pour les non-swaps
//            (qui représentent la majorité des comparaisons en phases finales)
//
// Quand un swap est nécessaire : les deux buffers (splats[] + depths[])
// sont permutés de façon synchrone pour maintenir la cohérence.
//
// Support Temporal Interleaved : identique à sort_bitonic_splats.glsl.
// ============================================================================

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0;
    uint data1;
    uint data2;
    uint data3;
};

// Les deux buffers sont permutés ensemble (cohérence splat ↔ depth)
layout(set = 0, binding = 0, std430) buffer SplatBuffer {
    PackedSplat splats[];
};
layout(set = 0, binding = 1, std430) buffer DepthBuffer {
    float depths[];
};

// Push constants : 32 bytes (pas d'AABB nécessaire – depths[] précalculées)
layout(push_constant, std430) uniform SortParams {
    uint  total_count;   // Gardé pour la compatibilité d'alignement push constants
    uint  padded_count;  // Puissance de 2
    uint  step_size;     // Étape courante du bitonic (j dans l'algo classique)
    uint  stage;         // Bloc courant (k dans l'algo classique)
    uint  frame_mask;    // Masque temporel interleaved (0/1/3 pour 1/2/4 frames)
    uint  frame_id;      // Index du frame courant & frame_mask
    uint  pad0;
    uint  pad1;
} pc;

void main() {
    uint gid = gl_GlobalInvocationID.x;
    if (gid >= pc.padded_count) return;

    // Temporal Interleaved Sorting : ne traiter que le bucket de ce frame
    if (pc.frame_mask != 0u && (gid & pc.frame_mask) != pc.frame_id) return;

    uint ixj = gid ^ pc.step_size;
    // Ne comparer que si ixj > gid (évite les doublons)
    if (ixj <= gid) return;

    // LECTURE ULTRA-RAPIDE SANS BRANCHES : depths[] est pré-rempli jusqu'à padded_count
    float dist_gid = depths[gid];
    float dist_ixj = depths[ixj];

    // Direction du tri bitonique : descendant (back-to-front pour le blending alpha 3DGS)
    bool descending = ((gid & pc.stage) != 0u);
    bool need_swap  = descending ? (dist_gid < dist_ixj) : (dist_gid > dist_ixj);

    if (need_swap) {
        // Permuter les splats (16 bytes chacun)
        PackedSplat tmp_splat = splats[gid];
        splats[gid] = splats[ixj];
        splats[ixj] = tmp_splat;

        // Permuter les clés de profondeur (garder la cohérence splat ↔ depth)
        depths[gid] = dist_ixj;
        depths[ixj] = dist_gid;
    }
}
