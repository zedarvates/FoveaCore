#[compute]
#version 450
#extension GL_KHR_shader_subgroup_ballot : enable

// ============================================================================
// FoveaEngine: gpu_culling_multi.glsl
// Phase 3 — Vectorized Splat Dispatcher: Multi-Asset GPU Culling
//
// Différences vs gpu_culling_compute.glsl (single-asset) :
//   - Jusqu'à 256 assets dans UN SEUL dispatch (asset_id dans le byte layer_id)
//   - AABB par-asset via un SSBO AssetData (pas de push-constant limité à 1 asset)
//   - Subgroup Ballot : 1 atomicAdd par warp au lieu de 1 par thread (~32x moins
//     de contention atomique sur les compteurs globaux)
//   - Fallback scalaire si GL_KHR_shader_subgroup_ballot est indisponible
//
// Format PackedSplat 16 bytes :
//   data0 : pos_x (16b) | pos_y (16b)
//   data1 : pos_z (16b) | norm_u (8b) | norm_v (8b)
//   data2 : color_rgb565 (16b) | covar_index (16b)
//   data3 : opacity (8b) | asset_id (8b) | padding (16b)   ← asset_id utilisé ici
// ============================================================================

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0;
    uint data1;
    uint data2;
    uint data3;
};

// AABB par asset : 2 x vec4 pour alignement std430
// [aabb_min_xyz + pad0] [aabb_max_xyz + pad1]  → 32 bytes par entrée
struct AssetData {
    float aabb_min_x; float aabb_min_y; float aabb_min_z; float pad0;
    float aabb_max_x; float aabb_max_y; float aabb_max_z; float pad1;
};

// Set 0 : Buffers splats + compteur + assets
layout(set = 0, binding = 0, std430) restrict readonly buffer InputSplats {
    PackedSplat input_data[];
};
layout(set = 0, binding = 1, std430) restrict writeonly buffer OutputSplats {
    PackedSplat output_data[];
};
layout(set = 0, binding = 2, std430) restrict buffer CounterBuffer {
    uint valid_splat_count;
};
// Tableau d'AABB par asset (jusqu'à MAX_ASSETS = 256)
layout(set = 0, binding = 3, std430) restrict readonly buffer AssetDataBuffer {
    AssetData assets[];
};

// Set 1 : Texture de profondeur + matrices caméra stéréo
layout(set = 1, binding = 0) uniform sampler2D depth_map;
layout(set = 1, binding = 1, std430) readonly buffer CameraData {
    mat4 view_proj_left;
    mat4 view_proj_right;
} camera;

// Push constants : 32 bytes
layout(push_constant, std430) uniform Params {
    float cam_x;
    float cam_y;
    float cam_z;
    uint  total_splats;
    float backface_threshold;
    uint  num_assets;       // Nombre d'assets valides dans AssetDataBuffer
    uint  pad0;
    uint  pad1;
} params;

void main() {
    uint index = gl_GlobalInvocationID.x;

    // Les threads hors-bornes doivent quand même participer au vote subgroup
    bool in_range = (index < params.total_splats);
    bool valid = false;

    if (in_range) {
        PackedSplat splat = input_data[index];

        // ── 1. DÉCODAGE POSITION MULTI-ASSET ──────────────────────────────────
        // Lire asset_id depuis le byte layer_id (bits [8..15] de data3)
        uint asset_id = (splat.data3 >> 8u) & 0xFFu;
        asset_id = min(asset_id, params.num_assets - 1u);
        AssetData asset = assets[asset_id];

        uint qx = splat.data0 & 0xFFFFu;
        uint qy = (splat.data0 >> 16u) & 0xFFFFu;
        uint qz = splat.data1 & 0xFFFFu;

        vec3 q_norm = vec3(float(qx), float(qy), float(qz)) / 65535.0;
        vec3 aabb_min = vec3(asset.aabb_min_x, asset.aabb_min_y, asset.aabb_min_z);
        vec3 aabb_max = vec3(asset.aabb_max_x, asset.aabb_max_y, asset.aabb_max_z);
        vec3 world_pos = aabb_min + q_norm * (aabb_max - aabb_min);

        // ── 2. DÉCODAGE NORMALE (Octahedral 8-bit) ────────────────────────────
        uint nu = (splat.data1 >> 16u) & 0xFFu;
        uint nv = (splat.data1 >> 24u) & 0xFFu;
        float u = float(nu) / 255.0 * 2.0 - 1.0;
        float v = float(nv) / 255.0 * 2.0 - 1.0;
        float nz = 1.0 - abs(u) - abs(v);
        float nx = u, ny = v;
        if (nz < 0.0) {
            float ox = nx;
            nx = (1.0 - abs(ny)) * sign(nx);
            ny = (1.0 - abs(ox))  * sign(ny);
        }
        vec3 normal = normalize(vec3(nx, ny, nz));

        // ── 3. BACKFACE CULLING ────────────────────────────────────────────────
        vec3 view_dir = normalize(world_pos - vec3(params.cam_x, params.cam_y, params.cam_z));
        float NdotV = dot(normal, view_dir);
        valid = (NdotV <= params.backface_threshold);

        // ── 4. FRUSTUM STÉRÉO + HI-Z ──────────────────────────────────────────
        if (valid) {
            vec4 cl = camera.view_proj_left  * vec4(world_pos, 1.0);
            vec4 cr = camera.view_proj_right * vec4(world_pos, 1.0);
            vec3 nl = cl.xyz / cl.w;
            vec3 nr = cr.xyz / cr.w;

            bool vis_l = (abs(nl.x) < 1.0 && abs(nl.y) < 1.0 && nl.z > 0.0 && nl.z < 1.0);
            bool vis_r = (abs(nr.x) < 1.0 && abs(nr.y) < 1.0 && nr.z > 0.0 && nr.z < 1.0);
            valid = (vis_l || vis_r);

            // Hi-Z : test sur l'œil gauche (œil dominant en VR)
            if (valid && vis_l) {
                vec2 uv = nl.xy * 0.5 + 0.5;
                float scene_depth = textureLod(depth_map, vec2(uv.x * 0.5, uv.y), 0.0).r;
                valid = (nl.z <= scene_depth + 0.001);
            }
        }
    }

    // ── 5. ÉCRITURE VECTORISÉE (Subgroup Ballot) ──────────────────────────────
    // Au lieu d'un atomicAdd par thread (pression atomique x256/group),
    // on vote en warp pour ne faire QU'UN atomicAdd par warp (~32x moins cher).
#ifdef GL_KHR_shader_subgroup_ballot
    uvec4 ballot     = subgroupBallot(valid);
    uint  lane_count = subgroupBallotBitCount(ballot);
    uint  base_idx   = 0u;
    if (subgroupElect()) {
        base_idx = atomicAdd(valid_splat_count, lane_count);
    }
    base_idx = subgroupBroadcastFirst(base_idx);
    uint local_lane  = subgroupBallotExclusiveBitCount(ballot);
    if (valid && in_range) {
        output_data[base_idx + local_lane] = input_data[index];
    }
#else
    // Fallback scalaire (compatible tous GPU)
    if (valid && in_range) {
        uint out_idx = atomicAdd(valid_splat_count, 1u);
        output_data[out_idx] = input_data[index];
    }
#endif
}
