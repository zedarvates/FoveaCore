// ============================================================================
// FoveaEngine - 3DGS Mathematics Library
// Basé sur l'implémentation de référence 3D Gaussian Splatting
// ============================================================================

// 1. ÉVALUATION DES HARMONIQUES SPHÉRIQUES (Degré 0)
// Convertit la couleur de base f_dc (Harmonique Sphérique de degré 0) en couleur RGB standard.
// La constante magique 0.28209479177387814 est SH_C0.
vec3 compute_sh_degree_0(vec3 f_dc) {
    const float SH_C0 = 0.28209479177387814;
    vec3 color = f_dc * SH_C0 + 0.5;
    return clamp(color, 0.0, 1.0);
}

// 2. CALCUL DE LA COVARIANCE 3D
// Convertit l'échelle (scale) et la rotation (quaternion) en une matrice de covariance 3D.
mat3 compute_cov3d(vec3 scale, vec4 rot) {
    // Matrice de scale
    mat3 S = mat3(1.0);
    S[0][0] = exp(scale.x);
    S[1][1] = exp(scale.y);
    S[2][2] = exp(scale.z);
    
    // Matrice de rotation depuis quaternion (r, x, y, z)
    float r = rot.x, x = rot.y, y = rot.z, z = rot.w;
    mat3 R;
    R[0] = vec3(1.0 - 2.0 * (y*y + z*z), 2.0 * (x*y - r*z),       2.0 * (x*z + r*y));
    R[1] = vec3(2.0 * (x*y + r*z),       1.0 - 2.0 * (x*x + z*z), 2.0 * (y*z - r*x));
    R[2] = vec3(2.0 * (x*z - r*y),       2.0 * (y*z + r*x),       1.0 - 2.0 * (x*x + y*y));
    
    mat3 M = R * S;
    return M * transpose(M);
}

// Native .fovea v2 covariance codebooks store already-decoded linear scale.
// Keep this separate from compute_cov3d(), which consumes log-space PLY scale.
mat3 compute_cov3d_linear(vec3 scale, vec4 rot) {
    mat3 S = mat3(1.0);
    S[0][0] = max(scale.x, 0.000001);
    S[1][1] = max(scale.y, 0.000001);
    S[2][2] = max(scale.z, 0.000001);

    float r = rot.x, x = rot.y, y = rot.z, z = rot.w;
    mat3 R;
    R[0] = vec3(1.0 - 2.0 * (y*y + z*z), 2.0 * (x*y - r*z),       2.0 * (x*z + r*y));
    R[1] = vec3(2.0 * (x*y + r*z),       1.0 - 2.0 * (x*x + z*z), 2.0 * (y*z - r*x));
    R[2] = vec3(2.0 * (x*z - r*y),       2.0 * (y*z + r*x),       1.0 - 2.0 * (x*x + y*y));

    mat3 M = R * S;
    return M * transpose(M);
}

// 3. PROJECTION DE LA COVARIANCE 3D EN 2D (ANISOTROPIE)
// Projette la matrice 3D sur l'écran pour obtenir les axes majeur/mineur de l'ellipse (Splat anisotropique).
vec3 compute_cov2d_unblurred(vec3 center_cam, mat3 cov3d, mat4 proj_matrix, vec2 viewport_size) {
    // Godot cameras look down -Z. Express the perspective Jacobian explicitly
    // in pixel space to avoid row/column ambiguity in column-major GLSL.
    float depth = max(-center_cam.z, 0.1);
    float focal_x = proj_matrix[0][0] * viewport_size.x * 0.5;
    float focal_y = proj_matrix[1][1] * viewport_size.y * 0.5;
    float inv_depth = 1.0 / depth;
    float inv_depth2 = inv_depth * inv_depth;
    vec3 du = vec3(
        focal_x * inv_depth,
        0.0,
        focal_x * center_cam.x * inv_depth2
    );
    vec3 dv = vec3(
        0.0,
        focal_y * inv_depth,
        focal_y * center_cam.y * inv_depth2
    );
    float cov11 = dot(du, cov3d * du);
    float cov12 = dot(du, cov3d * dv);
    float cov22 = dot(dv, cov3d * dv);
    return vec3(cov11, cov12, cov22);
}

vec3 compute_cov2d(vec3 center_cam, mat3 cov3d, mat4 proj_matrix, vec2 viewport_size) {
    vec3 cov2d = compute_cov2d_unblurred(center_cam, cov3d, proj_matrix, viewport_size);
    cov2d.x += 0.3;
    cov2d.z += 0.3;
    return cov2d;
}
