#[compute]
#version 450

// FoveaEngine : Compute Shader d'Animation Delta (Task 244 & 246 & 247)
// Décompresse les deltas FP16, applique l'interpolation temporelle et met à jour les splats.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0; // pos_x (16 bits), pos_y (16 bits)
    uint data1; // pos_z (16 bits), norm_u (8 bits), norm_v (8 bits)
    uint data2; // color_index RGB565 (16 bits), covar_index (16 bits)
    uint data3; // opacity (8 bits), layer_id (8 bits), padding (16 bits)
};

struct PackedDelta {
    uint pos_xy;      // FP16 X, Y packed
    uint pos_z_pad;   // FP16 Z (lower 16 bits), padding (upper 16)
    uint col_rg;      // FP16 R, G packed
    uint col_ba;      // FP16 B, A packed
    uint norm_uv;     // FP16 U, V packed
    uint padding;     // Align 24 bytes
};

// 1. Splats de base
layout(set = 0, binding = 0, std430) restrict readonly buffer InputSplats {
    PackedSplat input_splats[];
};

// 2. Buffer Delta de l'instance
layout(set = 0, binding = 1, std430) restrict readonly buffer DeltaBuffer {
    PackedDelta delta_splats[];
};

// 3. Splats animés de sortie
layout(set = 0, binding = 2, std430) restrict writeonly buffer OutputSplats {
    PackedSplat output_splats[];
};

layout(push_constant, std430) uniform Params {
    float delta_weight;
    uint total_splats;
    vec3 aabb_min;
    float pad1;
    vec3 aabb_max;
    float pad2;
} params;

// Utilitaires de conversion FP16 (en utilisant unpackHalf2x16 matériel)
vec2 unpack_half_2(uint packed_val) {
    return unpackHalf2x16(packed_val);
}

float unpack_half_1(uint packed_val) {
    return unpackHalf2x16(packed_val & 0xFFFFu).x;
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= params.total_splats) return;
    
    PackedSplat splat = input_splats[idx];
    PackedDelta delta = delta_splats[idx];
    
    // Décompresser les positions de base
    uint qx = splat.data0 & 0xFFFFu;
    uint qy = (splat.data0 >> 16) & 0xFFFFu;
    uint qz = splat.data1 & 0xFFFFu;
    
    vec3 aabb_size = params.aabb_max - params.aabb_min;
    vec3 base_pos = params.aabb_min + vec3(float(qx), float(qy), float(qz)) * 0.00001525902189669643 * aabb_size;
    
    // Décompresser les deltas de positions
    vec2 pos_xy = unpack_half_2(delta.pos_xy);
    float pos_z = unpack_half_1(delta.pos_z_pad);
    vec3 delta_pos = vec3(pos_xy, pos_z);
    
    // Appliquer le delta de position
    vec3 final_pos = base_pos + delta_pos * params.delta_weight;
    
    // Re-quantiser la position finale dans l'AABB
    vec3 q_new = clamp((final_pos - params.aabb_min) / aabb_size, 0.0, 1.0) * 65535.0 + 0.5;
    
    uint nqx = uint(q_new.x);
    uint nqy = uint(q_new.y);
    uint nqz = uint(q_new.z);
    
    splat.data0 = nqx | (nqy << 16);
    splat.data1 = nqz | (splat.data1 & 0xFFFF0000u); // Conserver normales
    
    // Décompresser et appliquer les deltas de couleur
    vec2 col_rg = unpack_half_2(delta.col_rg);
    vec2 col_ba = unpack_half_2(delta.col_ba);
    vec4 delta_col = vec4(col_rg, col_ba);
    
    if (length(delta_col) > 0.0001) {
        // Décoder couleur RGB565 de base
        uint r5 = (splat.data2 >> 11) & 0x1Fu;
        uint g6 = (splat.data2 >> 5) & 0x3Fu;
        uint b5 = splat.data2 & 0x1Fu;
        
        vec3 base_col = vec3(float(r5) / 31.0, float(g6) / 63.0, float(b5) / 31.0);
        vec3 final_col = clamp(base_col + delta_col.rgb * params.delta_weight, 0.0, 1.0);
        
        uint nr5 = uint(final_col.r * 31.0 + 0.5);
        uint ng6 = uint(final_col.g * 63.0 + 0.5);
        uint nb5 = uint(final_col.b * 31.0 + 0.5);
        
        splat.data2 = nb5 | (ng6 << 5) | (nr5 << 11) | (splat.data2 & 0xFFFF0000u); // Conserver covar
        
        // Opacité (data3 octet de poids faible)
        float base_opac = float(splat.data3 & 0xFFu) / 255.0;
        float final_opac = clamp(base_opac + delta_col.a * params.delta_weight, 0.0, 1.0);
        splat.data3 = uint(final_opac * 255.0 + 0.5) | (splat.data3 & 0xFFFFFF00u);
    }
    
    output_splats[idx] = splat;
}
