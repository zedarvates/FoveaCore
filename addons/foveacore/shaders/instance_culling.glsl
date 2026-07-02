#[compute]
#version 450

// FoveaEngine : instance_culling.glsl
// Culler de frustum d'instances sur le GPU (Task 253)

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// 1. Liste des transformations globales de chaque instance
layout(set = 0, binding = 0, std430) restrict readonly buffer Transforms {
    mat4 transforms[];
};

// 2. Liste des indices d'instances visibles (sortie)
layout(set = 0, binding = 1, std430) restrict writeonly buffer VisibleIndices {
    uint visible_indices[];
};

// 3. Compteur atomique d'instances visibles
layout(set = 0, binding = 2, std430) restrict buffer VisibleCounter {
    uint visible_count;
};

layout(push_constant, std430) uniform Params {
    vec4 planes[6];       // Plans du frustum (normal.xyz, distance)
    vec3 aabb_min;        // Bounding box locale de base (min)
    uint total_instances;
    vec3 aabb_max;        // Bounding box locale de base (max)
    uint padding;
} params;

bool is_aabb_in_frustum(mat4 xf, vec3 amin, vec3 amax) {
    // Calculer les 8 coins de l'AABB locale transformée dans le monde
    vec3 corners[8] = vec3[](
        vec3(amin.x, amin.y, amin.z),
        vec3(amax.x, amin.y, amin.z),
        vec3(amin.x, amax.y, amin.z),
        vec3(amax.x, amax.y, amin.z),
        vec3(amin.x, amin.y, amax.z),
        vec3(amax.x, amin.y, amax.z),
        vec3(amin.x, amax.y, amax.z),
        vec3(amax.x, amax.y, amax.z)
    );
    
    vec3 wmin = vec3(1e9);
    vec3 wmax = vec3(-1e9);
    
    for (int i = 0; i < 8; i++) {
        vec3 wp = (xf * vec4(corners[i], 1.0)).xyz;
        wmin = min(wmin, wp);
        wmax = max(wmax, wp);
    }
    
    vec3 center = (wmin + wmax) * 0.5;
    vec3 half_extents = (wmax - wmin) * 0.5;
    
    // Test AABB vs 6 plans du frustum
    for (int i = 0; i < 6; i++) {
        vec4 plane = params.planes[i];
        float dist = dot(plane.xyz, center) + plane.w;
        float radius = dot(abs(plane.xyz), half_extents);
        if (dist + radius < 0.0) {
            return false; // Totalement à l'extérieur
        }
    }
    return true; // Visible ou intersecte
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= params.total_instances) return;
    
    mat4 xf = transforms[idx];
    if (is_aabb_in_frustum(xf, params.aabb_min, params.aabb_max)) {
        uint out_idx = atomicAdd(visible_count, 1);
        visible_indices[out_idx] = idx;
    }
}
