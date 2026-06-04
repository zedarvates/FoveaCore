#[compute]
#version 450

// ============================================================================
// FoveaEngine: depth_precompute.glsl
// Phase 3 — FP16 Compute Pipeline : Pré-calcul des clés de profondeur
//
// Calcule la distance caméra² pour chaque splat survivant du culling,
// en UNE SEULE passe avant le tri bitonique.
//
// Avantage vs sort_bitonic_splats.glsl (legacy) :
//   - sort_bitonic_splats recalcule la distance à CHAQUE comparaison de tri
//     (3 loads uint16 + 10 ALU ops par splat par étape bitonique)
//   - Avec depth_precompute + sort_bitonic_keyed : 1 seul calcul de distance
//     en O(N), puis O(N·log²N) lectures float simples pendant le tri
//   - Réduction de bande passante de ~4x pour les comparaisons non-swap
//     (qui représentent la majorité des comparaisons dans les étapes tardives)
//
// Multi-asset : utilise l'AssetData SSBO pour connaître l'AABB de chaque splat.
// ============================================================================

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0;  // pos_x (16b) | pos_y (16b)
    uint data1;  // pos_z (16b) | norm_u (8b) | norm_v (8b)
    uint data2;  // color (16b) | covar_index (16b)
    uint data3;  // opacity (8b) | asset_id (8b) | padding (16b)
};

// AABB par asset (même layout que gpu_culling_multi.glsl)
struct AssetData {
    float aabb_min_x; float aabb_min_y; float aabb_min_z; float pad0;
    float aabb_max_x; float aabb_max_y; float aabb_max_z; float pad1;
};

// Entrée : le buffer de splats post-culling (indices compactés [0..count-1])
layout(set = 0, binding = 0, std430) restrict readonly buffer SplatBuffer {
    PackedSplat splats[];
};

// Sortie : une clé de profondeur (dist²) par splat.
// Le tri bitonique keyed lira ce buffer au lieu de recalculer.
layout(set = 0, binding = 1, std430) restrict writeonly buffer DepthBuffer {
    float depths[];
};

// AABB par asset pour la déquantification de position
layout(set = 0, binding = 2, std430) restrict readonly buffer AssetDataBuffer {
    AssetData assets[];
};

// Push constants : 32 bytes
layout(push_constant, std430) uniform Params {
    uint  total_count;   // Nombre de splats valides
    float cam_x;         // Position caméra monde
    float cam_y;
    float cam_z;
    uint  num_assets;    // Nombre d'assets valides
    uint  pad0;
    uint  pad1;
    uint  pad2;
} pc;

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= pc.total_count) return;

    PackedSplat s = splats[idx];

    // Lire l'asset_id depuis le byte layer_id (bits [8..15] de data3)
    uint asset_id = (s.data3 >> 8u) & 0xFFu;
    asset_id = min(asset_id, pc.num_assets - 1u);
    AssetData asset = assets[asset_id];

    // Déquantifier la position 16-bit → monde
    float qx = float(s.data0 & 0xFFFFu) / 65535.0;
    float qy = float((s.data0 >> 16u) & 0xFFFFu) / 65535.0;
    float qz = float(s.data1 & 0xFFFFu) / 65535.0;

    vec3 aabb_min = vec3(asset.aabb_min_x, asset.aabb_min_y, asset.aabb_min_z);
    vec3 aabb_max = vec3(asset.aabb_max_x, asset.aabb_max_y, asset.aabb_max_z);
    vec3 world_pos = aabb_min + vec3(qx, qy, qz) * (aabb_max - aabb_min);

    // Calculer la distance² caméra (pas de sqrt : même ordre de tri, moins cher)
    vec3 d = world_pos - vec3(pc.cam_x, pc.cam_y, pc.cam_z);
    depths[idx] = dot(d, d);
}
