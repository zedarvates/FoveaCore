#[compute]
#version 450

// ============================================================================
// FoveaEngine : sort_bitonic_splats.glsl
// Tri bitonique GPU operant DIRECTEMENT sur PackedSplat.
//
// DIFFERENCES vs sort_compute.glsl (legacy) :
//   - Opere sur PackedSplat (16 bytes chacun) plutot que sur depth[]+indices[]
//   - Calcule la distance camera au vol depuis la position quantisee
//   - Toutes les passes (stage/step) sont dispatchiees dans UNE SEULE compute list
//     (pas de submit/sync inter-passe) => elimination des stalls CPU<->GPU
//   - Support Temporal Interleaved : un masque de bits 'frame_mask' permet de
//     ne trier que le bucket [splat_index & frame_mask == frame_id] ce frame,
//     repartissant le tri sur N frames (N=1,2,4,8).
// ============================================================================

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// Structure identique a PackedSplat du culler
struct PackedSplat {
    uint data0; // pos_x (16 bits), pos_y (16 bits)
    uint data1; // pos_z (16 bits), norm_u (8 bits), norm_v (8 bits)
    uint data2; // color_index RGB565 (16 bits), covar_index (16 bits)
    uint data3; // opacity (8 bits), layer_id (8 bits), padding (16 bits)
};

layout(set = 0, binding = 0, std430) buffer SplatBuffer {
    PackedSplat splats[];
};

layout(push_constant, std430) uniform SortParams {
    uint  total_count;    // Nombre de splats valides (pas forcement puissance de 2)
    uint  padded_count;   // Puissance de 2 >= total_count
    uint  step_size;      // Etape courante du bitonic (j dans l'algo classique)
    uint  stage;          // Bloc courant (k dans l'algo classique)
    float cam_x;          // Position camera X (pour calcul distance a la volee)
    float cam_y;
    float cam_z;
    float aabb_range;     // Plage AABB pour dequantisation (ex: 10.0)
    // --- Temporal Interleaved Sorting ---
    uint  frame_mask;     // Masque de bits (0=tout, 1=pair/impair, 3=quarts)
    uint  frame_id;       // ID du frame courant & frame_mask
    float aabb_min_x;     // AABB minimum X
    float aabb_min_y;
    float aabb_min_z;
    float pad0;
    float pad1;
    float pad2;
} pc;

// Calcule la distance camera^2 depuis un PackedSplat (sans sqrt = plus rapide)
float splat_dist_sq(PackedSplat s) {
    float px = float(s.data0 & 0xFFFFu) / 65535.0 * pc.aabb_range + pc.aabb_min_x;
    float py = float((s.data0 >> 16) & 0xFFFFu) / 65535.0 * pc.aabb_range + pc.aabb_min_y;
    float pz = float(s.data1 & 0xFFFFu) / 65535.0 * pc.aabb_range + pc.aabb_min_z;
    float dx = px - pc.cam_x;
    float dy = py - pc.cam_y;
    float dz = pz - pc.cam_z;
    return dx*dx + dy*dy + dz*dz;
}

void main() {
    uint gid = gl_GlobalInvocationID.x;
    if (gid >= pc.padded_count) return;

    // --- Temporal Interleaved Sorting ---
    // Si frame_mask != 0, on ne traite que les splats dont l'index appartient
    // au bucket courant. Les autres frames ont deja trie les autres buckets.
    // Exemple frame_mask=3, frame_id=1 : seuls les splats dont gid&3==1 sont traites.
    if (pc.frame_mask != 0u && (gid & pc.frame_mask) != pc.frame_id) return;

    uint ixj = gid ^ pc.step_size;

    // Comparaison uniquement si ixj > gid et dans les bornes
    if (ixj <= gid) return;

    // Splats hors bornes reelles : distance infinie (seront en fin de liste)
    bool gid_valid = (gid < pc.total_count);
    bool ixj_valid = (ixj < pc.total_count);

    float dist_gid = gid_valid ? splat_dist_sq(splats[gid]) : 1.0e38;
    float dist_ixj = ixj_valid ? splat_dist_sq(splats[ixj]) : 1.0e38;

    // Direction : tri descendant (back-to-front pour le blending alpha 3DGS)
    // Les blocs de taille 'stage' alternent direction selon le bit de l'index
    bool descending = ((gid & pc.stage) != 0u);

    // Swap si necessite
    bool need_swap = descending ? (dist_gid < dist_ixj) : (dist_gid > dist_ixj);

    if (need_swap) {
        PackedSplat tmp = splats[gid];
        splats[gid]     = splats[ixj];
        splats[ixj]     = tmp;
    }
}
