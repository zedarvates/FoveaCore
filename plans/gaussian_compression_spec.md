# 📦 Gaussian Compression Format Specification (.fovea v2) — FoveaEngine

> **Date :** 2026-06-22 | **Auteurs :** Antigravity & FoveaEngine Team
>
> Ce document définit les spécifications techniques du format de fichier propriétaire compressé **`.fovea` v2**. L'objectif est de réduire de 80% à 90% la taille des données 3DGS originales (fichiers PLY bruts) pour permettre le streaming temps réel dans les casques VR (ex: Meta Quest) sans saturer la bande passante réseau ni le bus PCIe/VRAM.

---

## 1. COMPARAISON DES FORMATS

| Format | Taille par Splat (Octets) | Temps de Chargement (CPU) | Rendu Direct sur GPU | Streaming Progressif |
|---|---|---|---|---|
| **PLY Standard** | ~64 - 128 B | Lent (parsing texte/binaire CPU) | Non (requiert conversion) | Non |
| **.fovea v1** | 16 B | Rapide | Partiel | Non |
| **.fovea v2** | **8 B** (quantifié + entropy) | Instantané (Direct memory upload) | **Oui** (Decompress Compute Shader) | **Oui (par Chunks Morton)** |

---

## 2. ARCHITECTURE DES DONNÉES & QUANTIFICATION

Chaque splat est encodé de manière agressive à l'aide de techniques de quantification spécialisées. La structure finale d'un splat en mémoire compressée est de **8 octets (64 bits)** :

```
 0                    1                    2                    3
┌────────────────────┬────────────────────┬────────────────────┬────────────────────┐
│   Morton Delta X   │   Morton Delta Y   │   Morton Delta Z   │  Octahedral Norm X │
│      (10 bits)     │      (10 bits)     │      (10 bits)     │      (8 bits)      │
├────────────────────┼────────────────────┼────────────────────┼────────────────────┤
│  Octahedral Norm Y │    Color Index     │  Covariance Index  │      Opacity       │
│      (8 bits)      │      (8 bits)      │     (10 bits)      │      (10 bits)     │
└────────────────────┴────────────────────┴────────────────────┴────────────────────┘
```

### A. Positionnement Spatial Relatif (30 bits)
1. **Division spatiale** : La scène est découpée en blocs (AABB) de $4096$ splats triés selon leurs codes de Morton 30 bits.
2. **Quantification Fixed-Point** : Dans chaque bloc, les positions absolues $(X, Y, Z)$ sont converties en offsets locaux normalisés dans l'AABB du bloc, mappés sur une grille entière de 10 bits ($2^{10} = 1024$ divisions par axe).
   $$X_{\text{quant}} = \text{round}\left(\frac{X - X_{\text{min}}}{X_{\text{max}} - X_{\text{min}}} \cdot 1023\right)$$

### B. Normales Octaédriques (16 bits)
Pour économiser de l'espace sur les normales d'orientation, le vecteur normal normalisé $\vec{n} = (x, y, z)$ est projeté sur un octaèdre, puis plié sous forme de coordonnées 2D $(u, v)$ sur un carré $[-1, 1]^2$, encodées sur $8 \text{ bits } \times 2 = 16 \text{ bits}$ :
$$f(x, y, z) = \frac{(x, y)}{\|x\|_1 + \|y\|_1 + \|z\|_1}$$

### C. Quantification Vectorielle des Couleurs (8 bits)
Au lieu de stocker les couleurs RGB en direct (3 octets ou 12 octets en float), nous utilisons un algorithme **K-Means++** appliqué sur l'espace colorimétrique CIELAB (pour préserver la perception humaine) :
- Génération d'une palette de 256 couleurs représentatives par asset (stockée dans l'en-tête du fichier).
- Chaque splat stocke uniquement un index de couleur sur 8 bits.
- Application de la diffusion d'erreur de **Floyd-Steinberg** lors de la quantification pour éviter le "banding" visuel.

### D. Codebook de Covariance (10 bits)
Les paramètres d'échelle (3 floats) et de rotation (quaternion à 4 floats) forment la covariance du splat.
- Entraînement d'un codebook de 1024 clusters représentatifs combinant échelle + rotation.
- Chaque splat stocke un index de 10 bits pointant vers ce codebook de covariance.

### E. Quantification de l'Opacité (10 bits)
L'opacité $\alpha \in [0, 1]$ est encodée directement via une quantification linéaire simple sur 10 bits (plage de 0 à 1023).

---

## 3. LAYOUT DU FICHIER `.fovea` v2

```
┌────────────────────────────────────────────────────────┐
│ EN-TÊTE DU FICHIER (Header)                            │
│  - Magic Bytes (8 octets) : 'FOVEA_V2'                 │
│  - Nombre total de splats (4 octets)                   │
│  - Nombre de blocs Morton (4 octets)                   │
│  - Palette de couleurs RGB (256 x 3 octets = 768 B)    │
│  - Codebook de Covariance (1024 x 7 floats = 28.6 KB)  │
└────────────────────────────────────────────────────────┘
│ METADONNÉES DES BLOCS (Block Registry)                  │
│  - Pour chaque bloc (AABB : center (3x float), size)   │
└────────────────────────────────────────────────────────┘
│ FLUX DE SPLATS QUANTIFIÉS (Quantized Splat Stream)     │
│  - Blocs consécutifs de 4096 splats compressés         │
│  - Encodage entropique optionnel LZW par bloc          │
└────────────────────────────────────────────────────────┘
```

---

## 4. DÉCOMPRESSION COMPUTE SHADER SUR GPU

Pour éviter tout goulot d'étranglement CPU, le fichier compressé `.fovea` est téléversé brut en VRAM sous forme de Storage Buffer (`StructuredBuffer<uint2>`). 

Un **Compute Shader de Décompression** (`decompress_splats_compute.glsl`) est exécuté au démarrage de l'asset pour convertir à la volée ces 64 bits en attributs bruts exploitables par le trieur et le rasterizer.

```glsl
#version 450
layout(local_size_x = 256) in;

struct DecompressedSplat {
    vec4 position_scale;
    vec4 rotation_opacity;
    vec4 color_SH;
};

// Buffers GPU
layout(binding = 0, std430) readonly buffer CompressedBuffer { uvec2 compressed_data[]; };
layout(binding = 1, std430) readonly buffer ColorPalette { vec3 palette[256]; };
layout(binding = 2, std430) readonly buffer CovarianceCodebook { vec4 codebook[1024]; }; // vec4 scale_rot
layout(binding = 3, std430) writeonly buffer OutputBuffer { DecompressedSplat splats[]; };

uniform vec3 block_min;
uniform vec3 block_size;

// Helper de décodage des normales octaédriques
vec3 decode_octahedral(vec2 e) {
    vec3 v = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
    if (v.z < 0.0) {
        v.xy = (1.0 - abs(v.yx)) * vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
    }
    return normalize(v);
}

void main() {
    uint idx = gl_GlobalInvocationID.x;
    uvec2 data = compressed_data[idx];

    // 1. Extraire les coordonnées Morton Delta (3 x 10 bits)
    uint x_quant = (data.x >> 22) & 0x3FFu;
    uint y_quant = (data.x >> 12) & 0x3FFu;
    uint z_quant = (data.x >> 2) & 0x3FFu;
    
    vec3 local_pos = vec3(x_quant, y_quant, z_quant) / 1023.0;
    vec3 world_pos = block_min + local_pos * block_size;

    // 2. Décoder la couleur
    uint color_idx = (data.y >> 24) & 0xFFu;
    vec3 color = palette[color_idx];

    // 3. Décoder la normale octaédrique
    uint norm_x = (data.x & 0x3u) << 6 | (data.y >> 26) & 0x3Fu; // 8 bits combinés
    uint norm_y = (data.y >> 18) & 0xFFu;
    vec2 oct_coord = vec2(norm_x, norm_y) / 255.0 * 2.0 - 1.0;
    vec3 normal = decode_octahedral(oct_coord);

    // 4. Décoder la covariance (codebook) et l'opacité
    uint cov_idx = (data.y >> 8) & 0x3FFu;
    uint op_quant = data.y & 0xFFu;
    float opacity = float(op_quant) / 255.0;

    // Enregistrer les données décompressées pour le rendu
    splats[idx].position_scale = vec4(world_pos, 1.0);
    splats[idx].rotation_opacity = vec4(normal, opacity); // Simplifié pour démo
    splats[idx].color_SH = vec4(color, 1.0);
}
```

---

## 5. MÉTHODE D'ÉVALUATION DU PSNR ET PERTE VISUELLE

La compression avec perte introduit des dégradations géométriques et photométriques. Nous mesurons la qualité avec deux métriques clés lancées par notre pipeline de validation automatique :
1. **PSNR Géométrique (Peak Signal-to-Noise Ratio)** : Comparaison de la distance de Hausdorff entre le nuage original et compressé. Cible : $> 45\text{ dB}$.
2. **SSIM de Rendu (Structural Similarity Index)** : Comparaison d'images rendues sous 12 angles de caméra. Cible : SSIM $> 0.96$ par rapport au rendu PLY standard.

---

*Spécification adoptée le 2026-06-22 pour guider l'implémentation de la compression dynamique.*
