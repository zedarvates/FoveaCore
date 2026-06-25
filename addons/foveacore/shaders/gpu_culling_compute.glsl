#[compute]
#version 450

// FoveaEngine: Splat Pre-Culling Compute Shader (VRAM Out-of-Core Version)
// Exécuté avant le tri (Sorting) pour éliminer le travail inutile.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0; // pos_x (16 bits), pos_y (16 bits)
    uint data1; // pos_z (16 bits), norm_u (8 bits), norm_v (8 bits)
    uint data2; // color_index (10 bits), covar_index (10 bits), opacity (8b), flags (4b) (compatible format)
    uint data3; // opacity (8 bits), layer_id (8 bits), dither_seed (8 bits), brush_type (8 bits)
};

struct ChunkMetadata {
    vec4 aabb_min;      // xyz = min, w = slot_id (float)
    vec4 aabb_max;      // xyz = max, w = fade_opacity (float)
    uint splat_count;   // Nombre de splats réels dans ce chunk
    uint pad0;
    uint pad1;
    uint pad2;
};

// 1. Le Buffer d'entrée (Le VRAM Pool contenant tous les chunks chargés)
layout(set = 0, binding = 0, std430) restrict readonly buffer InputSplats {
    PackedSplat input_data[];
};

// 2. Le Buffer de sortie (Seulement les splats qui survivent)
layout(set = 0, binding = 1, std430) restrict writeonly buffer OutputSplats {
    PackedSplat output_data[];
};

// 3. Compteur atomique pour savoir combien ont survécu
layout(set = 0, binding = 2, std430) restrict buffer CounterBuffer {
    uint valid_splat_count;
};

// 4. Les Métadonnées des Chunks Actifs
layout(set = 0, binding = 3, std430) restrict readonly buffer ActiveChunks {
    ChunkMetadata active_chunks[];
};

// 5. Texture de profondeur de la scène (Hi-Z ou Depth Buffer standard)
layout(set = 1, binding = 0) uniform sampler2D depth_map;

// 6. Buffer de Matrices et de Plans Stéréoscopiques (UBO)
layout(set = 1, binding = 1, std140) uniform CameraData {
    mat4 view_proj_left;
    mat4 view_proj_right;
    vec4 planes_left[6];  // Plan = vec4(normal.xyz, distance)
    vec4 planes_right[6];
} camera;

layout(push_constant, std430) uniform Params {
    vec3 camera_position;
    uint total_splats; // Total de threads potentiels
    float backface_threshold; // ex: 0.0 pour 90 degrés stricts
    uint num_active_chunks; // Nombre de chunks actifs ce frame
    
    // Nouveaux paramètres pour décoder la Quantisation Spatiale de l'asset
    vec3 aabb_min;
    float pad1;
    vec3 aabb_max;
    float pad2;
} params;

// Vérifie si une sphère intersecte ou se trouve à l'intérieur du frustum défini par ses 6 plans
bool is_sphere_in_frustum(vec3 p, float radius, vec4 planes[6]) {
    for (int i = 0; i < 6; i++) {
        if (dot(planes[i].xyz, p) + planes[i].w < -radius) {
            return false; // Entièrement à l'extérieur
        }
    }
    return true; // Visible ou coupe le frustum
}

void main() {
    uint thread_idx = gl_GlobalInvocationID.x;
    uint active_chunk_idx = thread_idx / 4096;
    uint splat_offset = thread_idx % 4096;

    if (active_chunk_idx >= params.num_active_chunks) return;

    ChunkMetadata chunk = active_chunks[active_chunk_idx];
    if (splat_offset >= chunk.splat_count) return;

    // --- 1. CULLING DU CHUNK GLOBAL (GPU-Driven Optimization) ---
    vec3 chunk_min = chunk.aabb_min.xyz;
    vec3 chunk_max = chunk.aabb_max.xyz;
    vec3 chunk_center = (chunk_min + chunk_max) * 0.5;
    float chunk_radius = length(chunk_max - chunk_min) * 0.5;

    bool chunk_visible_left = is_sphere_in_frustum(chunk_center, chunk_radius, camera.planes_left);
    bool chunk_visible_right = is_sphere_in_frustum(chunk_center, chunk_radius, camera.planes_right);
    if (!chunk_visible_left && !chunk_visible_right) return;

    // --- 2. ACCÈS DYNAMIQUE AU POOL VRAM ---
    uint splat_start_idx = uint(chunk.aabb_min.w);
    uint splat_pool_idx = splat_start_idx + splat_offset;
    PackedSplat splat = input_data[splat_pool_idx];
    
    // --- 3. DÉCODAGE DES POSITIONS (AABB global de l'asset) ---
    uint qx = splat.data0 & 0xFFFFu;
    uint qy = (splat.data0 >> 16) & 0xFFFFu;
    uint qz = splat.data1 & 0xFFFFu;
    
    vec3 aabb_size = params.aabb_max - params.aabb_min;
    vec3 q_pos = vec3(float(qx), float(qy), float(qz)) * 0.00001525902189669643; // 1.0 / 65535.0
    vec3 world_pos = params.aabb_min + q_pos * aabb_size;

    // --- 4. DÉCODAGE DE LA NORMALE (Octahedral 8-bit encoding) ---
    uint norm_u_bits = (splat.data1 >> 16) & 0xFFu;
    uint norm_v_bits = (splat.data1 >> 24) & 0xFFu;
    float u = float(norm_u_bits) * 0.00784313725490196 - 1.0;
    float v = float(norm_v_bits) * 0.00784313725490196 - 1.0;
    
    float z = 1.0 - abs(u) - abs(v);
    float x = u, y = v;
    if (z < 0.0) {
        float old_x = x;
        x = (1.0 - abs(y)) * (x >= 0.0 ? 1.0 : -1.0);
        y = (1.0 - abs(old_x)) * (y >= 0.0 ? 1.0 : -1.0);
    }
    vec3 normal = normalize(vec3(x, y, z));

    // --- 5. BACKFACE CULLING ---
    vec3 view_dir = normalize(world_pos - params.camera_position);
    float NdotV = dot(normal, view_dir);
    if (NdotV > params.backface_threshold) return;

    // --- 6. FRUSTUM CULLING DU SPLAT INDIVIDUEL ---
    float splat_radius = 0.25;
    bool visible_left = is_sphere_in_frustum(world_pos, splat_radius, camera.planes_left);
    bool visible_right = is_sphere_in_frustum(world_pos, splat_radius, camera.planes_right);
    if (!visible_left && !visible_right) return;
    
    // --- 7. HI-Z OCCLUSION CULLING ---
    if (visible_left) {
        vec4 clip_left = camera.view_proj_left * vec4(world_pos, 1.0);
        vec3 ndc_left = clip_left.xyz / clip_left.w;
        
        if (abs(ndc_left.x) < 1.0 && abs(ndc_left.y) < 1.0 && ndc_left.z > 0.0 && ndc_left.z < 1.0) {
            vec2 screen_uv = ndc_left.xy * 0.5 + 0.5;
            float dist = length(world_pos - params.camera_position);
            float diameter_pixels = 250.0 / max(dist, 0.1);
            float mip = clamp(ceil(log2(diameter_pixels)), 0.0, 7.0);
            
            float scene_depth = textureLod(depth_map, vec2(screen_uv.x * 0.5, screen_uv.y), mip).r;
            if (ndc_left.z > scene_depth + 0.001) return;
        }
    }

    // --- 8. INTERPOLATION D'APPARITION (FADE-IN EFFECT) ---
    float fade = clamp(chunk.aabb_max.w, 0.0, 1.0);
    uint opacity = splat.data3 & 0xFFu;
    opacity = uint(float(opacity) * fade);
    splat.data3 = (splat.data3 & 0xFFFFFF00u) | (opacity & 0xFFu);

    // Le splat est valide, on l'ajoute au buffer de sortie
    uint out_index = atomicAdd(valid_splat_count, 1);
    output_data[out_index] = splat;
}