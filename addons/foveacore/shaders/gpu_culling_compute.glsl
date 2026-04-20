#[compute]
#version 450

// FoveaEngine: Splat Pre-Culling Compute Shader
// Exécuté avant le tri (Sorting) pour éliminer le travail inutile.

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

struct PackedSplat {
    uint data0; // pos_x (16 bits), pos_y (16 bits)
    uint data1; // pos_z (16 bits), norm_u (8 bits), norm_v (8 bits)
    uint data2; // color_index RGB565 (16 bits), covar_index (16 bits)
    uint data3; // opacity (8 bits), layer_id (8 bits), padding (16 bits)
};

// 1. Le Buffer d'entrée (Tous les splats de l'objet)
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

// 4. Texture de profondeur de la scène (Hi-Z ou Depth Buffer standard)
layout(set = 1, binding = 0) uniform sampler2D depth_map;

// 5. Buffer de Matrices Stéréoscopiques (UBO)
// Permet de dépasser la limite de 128 octets des Push Constants pour le Multiview
layout(set = 1, binding = 1, std140) uniform CameraData {
    mat4 view_proj_left;
    mat4 view_proj_right;
} camera;

layout(push_constant, std430) uniform Params {
    vec3 camera_position;
    uint total_splats;
    float backface_threshold; // ex: 0.0 pour 90 degrés stricts
    float padding; // Alignement std140
    
    // Nouveaux paramètres pour décoder la Quantisation Spatiale
    vec3 aabb_min;
    float pad1;
    vec3 aabb_max;
    float pad2;
} params;

void main() {
    uint index = gl_GlobalInvocationID.x;
    if (index >= params.total_splats) return;

    PackedSplat splat = input_data[index];
    
    // --- 1. DÉCODAGE DES POSITIONS (Spatial Quantization) ---
    // Extraction des 16-bits (Endianness standard CPU/GPU)
    uint qx = splat.data0 & 0xFFFFu;
    uint qy = (splat.data0 >> 16) & 0xFFFFu;
    uint qz = splat.data1 & 0xFFFFu;
    
    // Remappage de 0..65535 vers la vraie taille via l'AABB
    vec3 q_pos = vec3(float(qx), float(qy), float(qz)) / 65535.0;
    vec3 world_pos = params.aabb_min + q_pos * (params.aabb_max - params.aabb_min);

    // --- 2. DÉCODAGE DE LA COULEUR ET OPACITÉ ---
    // (Sera surtout utile à copier-coller dans votre splat_render.glsl !)
    uint color_index = splat.data2 & 0xFFFFu;
    float r = float((color_index >> 11) & 0x1Fu) / 31.0;
    float g = float((color_index >> 5) & 0x3Fu)  / 63.0;
    float b = float(color_index & 0x1Fu)         / 31.0;
    vec3 color = vec3(r, g, b); // Couleur RGB restaurée
    
    float opacity = float(splat.data3 & 0xFFu) / 255.0; // Opacité restaurée

    // 1. BACKFACE CULLING : Si la normale pointe à l'opposé de la caméra, on tue le thread !
    // (Désactivé temporairement tant que les normales compressées ne sont pas implémentées)
    // vec3 view_dir = normalize(world_pos - params.camera_position);
    // float NdotV = dot(normal, view_dir);
    // if (NdotV > params.backface_threshold) return;
    
    // 2. OCCLUSION CULLING : Test de profondeur
    // CULLING STÉRÉOSCOPIQUE (Combined Frustum VR)
    vec4 clip_left = camera.view_proj_left * vec4(world_pos, 1.0);
    vec3 ndc_left = clip_left.xyz / clip_left.w;
    
    vec4 clip_right = camera.view_proj_right * vec4(world_pos, 1.0);
    vec3 ndc_right = clip_right.xyz / clip_right.w;
    
    bool visible_left = (abs(ndc_left.x) < 1.0 && abs(ndc_left.y) < 1.0 && ndc_left.z > 0.0 && ndc_left.z < 1.0);
    bool visible_right = (abs(ndc_right.x) < 1.0 && abs(ndc_right.y) < 1.0 && ndc_right.z > 0.0 && ndc_right.z < 1.0);

    // Si le splat est en dehors des DEUX yeux en même temps, on l'élimine du rendu !
    if (!visible_left && !visible_right) return;
    
    // 3. HI-Z OCCLUSION
    // Par soucis de performance, on teste l'occlusion sur la vue combinée ou l'œil dominant
    if (visible_left) {
        vec2 screen_uv = ndc_left.xy * 0.5 + 0.5;
        // En OpenXR Multiview, la texture de profondeur contient souvent les 2 yeux côte-à-côte
        float scene_depth = textureLod(depth_map, vec2(screen_uv.x * 0.5, screen_uv.y), 0.0).r;
        
        // Si le splat est plus loin que la géométrie enregistrée (+ un petit biais pour éviter l'acné)
        if (ndc_left.z > scene_depth + 0.001) return;
    }

    // Le splat est valide, on l'ajoute au buffer de rendu via un ajout atomique
    uint out_index = atomicAdd(valid_splat_count, 1);
    output_data[out_index] = splat;
}