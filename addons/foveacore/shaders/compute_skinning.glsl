#[compute]
#version 450

// FoveaEngine : compute_skinning.glsl (Task 265)
// Applique le skinning d'armature (skeletal deformation) sur les splats d'entités mobiles
// en utilisant des indices d'os et des poids stockés par splat.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0; // pos_x (16 bits), pos_y (16 bits)
    uint data1; // pos_z (16 bits), norm_u (8 bits), norm_v (8 bits)
    uint data2; // color_index RGB565 (16 bits), covar_index (16 bits)
    uint data3; // opacity (8 bits), layer_id (8 bits), padding (16 bits)
};

struct BoneInfluence {
    uint bone_indices; // 4 indices d'os (8 bits chacun)
    uint bone_weights; // 4 poids d'os (8 bits chacun, normalisés à 255)
};

// 1. Splats d'entrée (au repos)
layout(set = 0, binding = 0, std430) restrict readonly buffer InputSplats {
    PackedSplat input_splats[];
};

// 2. Buffer d'influence des os (1 par splat)
layout(set = 0, binding = 1, std430) restrict readonly buffer InfluenceBuffer {
    BoneInfluence influences[];
};

// 3. Matrices d'os animées (de l'armature)
layout(set = 0, binding = 2, std430) restrict readonly buffer BoneMatrices {
    mat4 bone_transforms[];
};

// 4. Splats déformés de sortie
layout(set = 0, binding = 3, std430) restrict writeonly buffer OutputSplats {
    PackedSplat output_splats[];
};

layout(push_constant, std430) uniform Params {
    uint total_splats;
    uint use_dqs;
    vec3 aabb_min;
    float pad1;
    vec3 aabb_max;
    float pad2;
} params;

// Convert 3x3 rotation matrix to quaternion
vec4 mat3_to_quat(mat3 m) {
    float tr = m[0][0] + m[1][1] + m[2][2];
    vec4 q;
    if (tr > 0.0) {
        float s = sqrt(tr + 1.0) * 2.0; // S=4*qw
        q.w = 0.25 * s;
        q.x = (m[1][2] - m[2][1]) / s;
        q.y = (m[2][0] - m[0][2]) / s;
        q.z = (m[0][1] - m[1][0]) / s;
    } else if ((m[0][0] > m[1][1]) && (m[0][0] > m[2][2])) {
        float s = sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2.0; // S=4*qx
        q.w = (m[1][2] - m[2][1]) / s;
        q.x = 0.25 * s;
        q.y = (m[0][1] + m[1][0]) / s;
        q.z = (m[2][0] + m[0][2]) / s;
    } else if (m[1][1] > m[2][2]) {
        float s = sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2.0; // S=4*qy
        q.w = (m[2][0] - m[0][2]) / s;
        q.x = (m[0][1] + m[1][0]) / s;
        q.y = 0.25 * s;
        q.z = (m[1][2] + m[2][1]) / s;
    } else {
        float s = sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2.0; // S=4*qz
        q.w = (m[0][1] - m[1][0]) / s;
        q.x = (m[2][0] + m[0][2]) / s;
        q.y = (m[1][2] + m[2][1]) / s;
        q.z = 0.25 * s;
    }
    return normalize(q);
}

// Convert transform matrix to dual quaternion (real, dual parts)
void mat4_to_dual_quat(mat4 m, out vec4 q_r, out vec4 q_d) {
    q_r = mat3_to_quat(mat3(m));
    vec3 t = m[3].xyz;
    // q_d = 0.5 * t * q_r
    q_d.w = -0.5 * (t.x * q_r.x + t.y * q_r.y + t.z * q_r.z);
    q_d.x =  0.5 * (t.x * q_r.w + t.y * q_r.z - t.z * q_r.y);
    q_d.y =  0.5 * (-t.x * q_r.z + t.y * q_r.w + t.z * q_r.x);
    q_d.z =  0.5 * (t.x * q_r.y - t.y * q_r.x + t.z * q_r.w);
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= params.total_splats) return;

    PackedSplat splat = input_splats[idx];
    BoneInfluence infl = influences[idx];

    // 1. Décoder la position locale (repos) du splat
    uint qx = splat.data0 & 0xFFFFu;
    uint qy = (splat.data0 >> 16) & 0xFFFFu;
    uint qz = splat.data1 & 0xFFFFu;

    vec3 aabb_size = params.aabb_max - params.aabb_min;
    vec3 local_pos = params.aabb_min + vec3(float(qx), float(qy), float(qz)) * 0.00001525902189669643 * aabb_size;

    // 2. Décoder les influences d'os (indices et poids)
    uint i0 = infl.bone_indices & 0xFFu;
    uint i1 = (infl.bone_indices >> 8) & 0xFFu;
    uint i2 = (infl.bone_indices >> 16) & 0xFFu;
    uint i3 = (infl.bone_indices >> 24) & 0xFFu;

    float w0 = float(infl.bone_weights & 0xFFu) / 255.0;
    float w1 = float((infl.bone_weights >> 8) & 0xFFu) / 255.0;
    float w2 = float((infl.bone_weights >> 16) & 0xFFu) / 255.0;
    float w3 = float((infl.bone_weights >> 24) & 0xFFu) / 255.0;

    vec3 final_pos;
    float total_w = w0 + w1 + w2 + w3;

    if (total_w < 0.001) {
        final_pos = local_pos;
    } else {
        // Normaliser les poids au cas où
        w0 /= total_w;
        w1 /= total_w;
        w2 /= total_w;
        w3 /= total_w;

        if (params.use_dqs != 0) {
            // --- Dual Quaternion Skinning (DQS) ---
            vec4 qr0, qd0, qr1, qd1, qr2, qd2, qr3, qd3;
            mat4_to_dual_quat(bone_transforms[i0], qr0, qd0);
            mat4_to_dual_quat(bone_transforms[i1], qr1, qd1);
            mat4_to_dual_quat(bone_transforms[i2], qr2, qd2);
            mat4_to_dual_quat(bone_transforms[i3], qr3, qd3);

            // Gérer le retournement antipodale (assurer la rotation par le chemin le plus court)
            if (dot(qr0, qr1) < 0.0) { qr1 = -qr1; qd1 = -qd1; }
            if (dot(qr0, qr2) < 0.0) { qr2 = -qr2; qd2 = -qd2; }
            if (dot(qr0, qr3) < 0.0) { qr3 = -qr3; qd3 = -qd3; }

            // Mélange des quaternions duaux
            vec4 dq_r = qr0 * w0 + qr1 * w1 + qr2 * w2 + qr3 * w3;
            vec4 dq_d = qd0 * w0 + qd1 * w1 + qd2 * w2 + qd3 * w3;

            // Normalisation
            float len = length(dq_r);
            dq_r /= len;
            dq_d /= len;

            // Appliquer la transformation DQS au point
            // Translation = 2.0 * (dq_d.w * -dq_r.xyz + dq_r.w * dq_d.xyz - cross(dq_r.xyz, dq_d.xyz))
            vec3 trans = 2.0 * (dq_d.w * -dq_r.xyz + dq_r.w * dq_d.xyz - cross(dq_r.xyz, dq_d.xyz));
            
            // Rotation = rotate vector by dq_r
            final_pos = local_pos + 2.0 * cross(dq_r.xyz, cross(dq_r.xyz, local_pos) + dq_r.w * local_pos);
            final_pos += trans;
        } else {
            // --- Linear Blend Skinning (LBS) ---
            mat4 skin_matrix = mat4(0.0);
            if (w0 > 0.0) skin_matrix += bone_transforms[i0] * w0;
            if (w1 > 0.0) skin_matrix += bone_transforms[i1] * w1;
            if (w2 > 0.0) skin_matrix += bone_transforms[i2] * w2;
            if (w3 > 0.0) skin_matrix += bone_transforms[i3] * w3;

            final_pos = (skin_matrix * vec4(local_pos, 1.0)).xyz;
        }
    }

    // 5. Re-quantiser la position déformée dans l'AABB de sortie
    vec3 q_new = clamp((final_pos - params.aabb_min) / aabb_size, 0.0, 1.0) * 65535.0 + 0.5;

    uint nqx = uint(q_new.x);
    uint nqy = uint(q_new.y);
    uint nqz = uint(q_new.z);

    splat.data0 = nqx | (nqy << 16);
    splat.data1 = nqz | (splat.data1 & 0xFFFF0000u); // Conserver les normales d'origine/padding

    // 6. Écrire le splat déformé dans le buffer de sortie
    output_splats[idx] = splat;
}
