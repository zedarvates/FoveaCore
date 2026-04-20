// GPU Culling - Compute shader pour le culling parallèle de frustum
// Exécute le test AABB vs frustum sur GPU pour libérer le CPU

// Entrées
layout(std430, binding = 0) buffer AABBBuffer {
    vec4 aabb_data[]; // (center_x, center_y, center_z, extent)
};

layout(std430, binding = 1) buffer FrustumBuffer {
    vec4 frustum_planes[6]; // (normal_x, normal_y, normal_z, distance)
};

// Sorties
layout(std430, binding = 2) buffer VisibilityBuffer {
    uint visible_flags[]; // 1 = visible, 0 = culled
};

// Uniforms
layout(binding = 3) uniform Uniforms {
    uint object_count;
};

void main() {
    uint idx = gl_GlobalInvocationID.x;
    
    if (idx >= object_count) {
        return;
    }
    
    // Lire l'AABB
    vec4 aabb = aabb_data[idx];
    vec3 center = aabb.xyz;
    float extent = aabb.w;
    
    // Tester contre les 6 plans du frustum
    bool visible = true;
    
    for (int i = 0; i < 6; i++) {
        vec3 normal = frustum_planes[i].xyz;
        float distance = frustum_planes[i].w;
        
        // Calculer le rayon projeté
        float radius = extent * (abs(normal.x) + abs(normal.y) + abs(normal.z));
        
        // Distance du centre au plan
        float dist = dot(normal, center) + distance;
        
        // Si centre + rayon < 0, l'objet est dehors
        if (dist + radius < 0.0) {
            visible = false;
            break;
        }
    }
    
    visible_flags[idx] = visible ? 1u : 0u;
}
