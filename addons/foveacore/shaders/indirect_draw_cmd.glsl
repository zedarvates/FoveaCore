#[compute]
#version 450

// FoveaEngine : indirect_draw_cmd.glsl
// Coder la génération de commande d'Indirect Draw sur GPU (Task 250)

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// 1. Le compteur atomique du culling
layout(set = 0, binding = 0, std430) restrict readonly buffer CounterBuffer {
    uint valid_splat_count;
};

// 2. Le buffer de commande d'argument indirect de Godot
// Structure correspondante à VkDrawIndexedIndirectCommand (20 octets)
// ou VkDrawIndirectCommand (16 octets)
layout(set = 0, binding = 1, std430) restrict writeonly buffer IndirectArgsBuffer {
    uint data[];
};

layout(push_constant, std430) uniform Params {
    uint count_per_splat; // Nombre d'indices ou de sommets par splat
    uint is_indexed;      // 1 = indexé, 0 = non indexé
} params;

void main() {
    // Exécuté sur un seul thread
    uint splat_count = valid_splat_count;
    
    if (params.is_indexed == 1u) {
        // VkDrawIndexedIndirectCommand:
        // uint indexCount;
        // uint instanceCount;
        // uint firstIndex;
        // int  vertexOffset;
        // uint firstInstance;
        data[0] = splat_count * params.count_per_splat; // total indices à dessiner
        data[1] = 1u;                                   // 1 instance (dessin global)
        data[2] = 0u;                                   // firstIndex
        data[3] = 0u;                                   // vertexOffset
        data[4] = 0u;                                   // firstInstance
    } else {
        // VkDrawIndirectCommand:
        // uint vertexCount;
        // uint instanceCount;
        // uint firstVertex;
        // uint firstInstance;
        data[0] = splat_count * params.count_per_splat;
        data[1] = 1u;
        data[2] = 0u;
        data[3] = 0u;
    }
}
