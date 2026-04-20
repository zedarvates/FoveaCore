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
    mat3 S = mat3(
        exp(scale.x), 0.0, 0.0,
        0.0, exp(scale.y), 0.0,
        0.0, 0.0, exp(scale.z)
    );
    
    // Matrice de rotation depuis quaternion (r, x, y, z)
    float r = rot.x, x = rot.y, y = rot.z, z = rot.w;
    mat3 R = mat3(
        1.0 - 2.0 * (y*y + z*z), 2.0 * (x*y - r*z),       2.0 * (x*z + r*y),
        2.0 * (x*y + r*z),       1.0 - 2.0 * (x*x + z*z), 2.0 * (y*z - r*x),
        2.0 * (x*z - r*y),       2.0 * (y*z + r*x),       1.0 - 2.0 * (x*x + y*y)
    );
    
    mat3 M = R * S;
    return M * transpose(M);
}

// 3. PROJECTION DE LA COVARIANCE 3D EN 2D (ANISOTROPIE)
// Projette la matrice 3D sur l'écran pour obtenir les axes majeur/mineur de l'ellipse (Splat anisotropique).
vec3 compute_cov2d(vec3 center_cam, mat3 cov3d, mat4 proj_matrix, vec2 viewport_size) {
    // Limiter la profondeur pour éviter les artefacts derrière la caméra
    float t = clamp(center_cam.z, -1000.0, -0.1); // Godot est en Forward -Z
    
    // Calcul du Jacobien de la projection perspective
    float focal_x = proj_matrix[0][0] * viewport_size.x * 0.5;
    float focal_y = proj_matrix[1][1] * viewport_size.y * 0.5;
    
    mat3 J = mat3(
        focal_x / t, 0.0,         -(focal_x * center_cam.x) / (t * t),
        0.0,         -focal_y / t, (focal_y * center_cam.y) / (t * t),
        0.0,         0.0,         0.0
    );
    
    mat3 W = mat3(1.0); // Vue vers Caméra (déjà fait si cov3d est en espace vue)
    mat3 T = W * J;
    
    mat3 cov2d_mat = transpose(T) * cov3d * T;
    
    // Ajouter un filtre passe-bas (0.3) pour l'anti-aliasing de base
    float cov11 = cov2d_mat[0][0] + 0.3;
    float cov12 = cov2d_mat[0][1];
    float cov22 = cov2d_mat[1][1] + 0.3;
    
    return vec3(cov11, cov12, cov22);
}