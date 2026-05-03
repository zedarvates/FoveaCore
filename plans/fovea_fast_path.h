#pragma once
#include <cstdint>

namespace fovea {

// En-tête du fichier .fovea natif
struct FoveaAssetHeader {
    char magic[8]; // "FOVEA_3D"
    uint32_t version;
    uint32_t splat_count;
    uint32_t color_codebook_size;
    uint32_t covar_codebook_size;
    
    // Bounding box pour décoder la Quantisation Spatiale
    float aabb_min[3];
    float aabb_max[3];
};

// Structure GPU ultra-optimisée : EXACTEMENT 16 octets par splat !
// Réduction de 66% de l'utilisation de la VRAM par rapport au 3DGS classique.
struct alignas(16) FoveaPackedSplat {
    // 1. Spatial Quantization : Grille locale (16-bits par axe) -> 6 octets
    uint16_t pos_x, pos_y, pos_z; 
    
    // 2. Normale encodée pour le Backface Culling rapide (8-bits) -> 2 octets
    int8_t norm_u, norm_v; 
    
    // 3. Vector Quantization : Index vers les Palettes partagées -> 4 octets
    uint16_t color_index; // Pointe vers un tableau de couleurs RGB
    uint16_t covar_index; // Pointe vers un tableau de covariances/échelles
    
    // 4. Données locales -> 2 octets
    uint8_t opacity;  // Opacité quantisée (0-255)
    uint8_t layer_id; // Fovea Layer (BASE, SATURATION, LIGHT, SHADOW)
    
    uint16_t padding; // Rembourrage pour alignement GPU parfait de 16 octets
};

} // namespace fovea