# 📄 Spécification canonique du Format d'Asset .fovea v2

Ce document décrit la structure binaire du format d'asset propriétaire `.fovea` utilisé par **FoveaEngine**. Ce format est conçu pour stocker de manière compacte et optimisée pour le GPU des Gaussian Splats, des paramètres de style visuels, des maillages polygonaux associés (pour le rendu hybride) ainsi que des métadonnées personnalisées.

> **Statut : contrat implémenté.** Les lecteurs et écrivains actifs utilisent `FOVEA_3D`, version `2`, un en-tête little-endian de 72 octets et des enregistrements de 16 octets par splat. Toute évolution incompatible doit recevoir une nouvelle version et une nouvelle identité de format.

---

## 📐 Structure Globale du Fichier

Le fichier est composé d'une en-tête de taille fixe suivie de sections de données contiguës. Certaines sections sont à accès direct (comme les splats pour injection directe dans les buffers GPU), tandis que d'autres (comme le style ou le maillage) sont référencées par des offsets absolus définis dans l'en-tête.

```
+-------------------------------------------------------+
| En-tête (FoveaAssetHeader) - 72 octets                |
+-------------------------------------------------------+
| Palette de Couleurs (RGB32F)                          |
+-------------------------------------------------------+
| Codebook de Covariance (32 octets par cluster std140) |
+-------------------------------------------------------+
| Splats Compactés (FoveaPackedSplat) - 16 octets/splat  |
+-------------------------------------------------------+
| [Optionnel] Style Visuel (JSON UTF-8)                 |
+-------------------------------------------------------+
| [Optionnel] Maillage Polygonal (Données Binaires)     |
+-------------------------------------------------------+
| [Optionnel] Métadonnées (JSON UTF-8)                  |
+-------------------------------------------------------+
```

---

## 1. En-tête du Fichier (`FoveaAssetHeader`)

L'en-tête fait exactement **72 octets** et est sérialisé en little-endian selon l'alignement suivant :

| Offset | Type | Nom | Description |
|---|---|---|---|
| 0 | `char[8]` | `magic` | Doit correspondre à `"FOVEA_3D"` |
| 8 | `uint32` | `version` | Version du format (actuellement `2`) |
| 12 | `uint32` | `splat_count` | Nombre de splats stockés dans le fichier |
| 16 | `uint32` | `color_codebook_size` | Nombre de couleurs dans la palette (max 256) |
| 20 | `uint32` | `covar_codebook_size` | Nombre de covariances dans le codebook (max 1024) |
| 24 | `float[3]` | `aabb_min` | Coordonnées minimales de la bounding box [x, y, z] |
| 36 | `float[3]` | `aabb_max` | Coordonnées maximales de la bounding box [x, y, z] |
| 48 | `uint32` | `style_offset` | Offset absolu en octets vers la section Style (0 si absent) |
| 52 | `uint32` | `style_size` | Taille en octets de la section Style (0 si absent) |
| 56 | `uint32` | `mesh_offset` | Offset absolu en octets vers la section Maillage (0 si absent) |
| 60 | `uint32` | `mesh_size` | Taille en octets de la section Maillage (0 si absent) |
| 64 | `uint32` | `meta_offset` | Offset absolu en octets vers la section Métadonnées (0 si absent) |
| 68 | `uint32` | `meta_size` | Taille en octets de la section Métadonnées (0 si absent) |

---

## 2. Palette de Couleurs (RGB32F)

Située immédiatement après l'en-tête (offset 72).
- **Taille** : `color_codebook_size * 12` octets.
- **Format** : Tableau plat de triplets float32 `[R, G, B]`.

---

## 3. Codebook de Covariance

Situé après la palette de couleurs.
- **Taille** : `covar_codebook_size * 32` octets.
- **Format** : Alignement strict sur 32 octets par cluster (compatible `std140` GLSL). Chaque cluster contient :
  - `scale` : `float[3]` (12 octets)
  - `rotation` : `float[4]` (quaternion normalisé, 16 octets)
  - `padding` : `float` (4 octets inutilisés)

---

## 4. Section des Splats Compactés (`FoveaPackedSplat`)

Située après le codebook de covariance.
- **Taille** : `splat_count * 16` octets.
- **Format** : Chaque splat prend exactement **16 octets** structurés comme suit :
  - `pos_x` (`uint16`) : Position normalisée en X sur 16 bits par rapport à l'AABB.
  - `pos_y` (`uint16`) : Position normalisée en Y sur 16 bits par rapport à l'AABB.
  - `pos_z` (`uint16`) : Position normalisée en Z sur 16 bits par rapport à l'AABB.
  - `norm_u` (`int8`) : Normale projetée U (coordonnée sphérique compressée).
  - `norm_v` (`int8`) : Normale projetée V (coordonnée sphérique compressée).
  - `color_index` (`uint8`) : Index dans la palette de couleurs (0 à 255).
  - `padding1` (`uint8`) : Padding d'alignement (1 octet).
  - `covar_index` (`uint16`) : Index dans le codebook de covariance (0 à 1023).
  - `opacity` (`uint8`) : Opacité stockée de manière linéaire (0 à 255).
  - `layer_id` (`uint8`) : Identifiant de la couche de rendu (0 = BASE, etc.).
  - `dither_seed` (`uint8`) : Graine pseudo-aléatoire pour le dithering stochastique.
  - `brush_type` (`uint8`) : Type de brosse/forme. Correspond exactement à
    `GaussianSplat.BrushType` : 0 = Stone, 1 = Sponge, 2 = Gaussian,
    3 = Drybrush, 4 = Stipple.

---

## 5. Section Style Visuel

Située à `style_offset`.
- **Format** : Chaîne JSON encodée en UTF-8.
- **Contenu** : Propriétés sérialisées de la ressource `FoveaStyle` et de ses matériaux associés (`stone_params`, etc.) :
  ```json
  {
    "mode": "procedural",
    "detail": 1.0,
    "grain": 0.5,
    "light_coherence": 0.8,
    "color_saturation": 0.7,
    "micro_shadow": 0.5,
    "lora_path": "",
    "neural_strength": 0.0,
    "temporal_coherence": true,
    "stone_params": {
      "material_type": 0,
      "base_color": [0.5, 0.5, 0.5, 1.0],
      "roughness": 0.8,
      "metallic": 0.0,
      "bump_strength": 0.5,
      "specular_strength": 0.3
    }
  }
  ```

---

## 6. Section Maillage Polygonal

Située à `mesh_offset`. Contient le maillage 3D optionnel associé à l'asset.
- **Structure** :
  - `vertex_count` : `uint32` (4 octets)
  - `index_count` : `uint32` (4 octets)
  - `has_normals` : `uint8` (1 octet, `0` ou `1`)
  - `has_uvs` : `uint8` (1 octet, `0` ou `1`)
  - `padding` : `uint16` (2 octets)
  - **Tableau des sommets** : `vertex_count * 12` octets (triplets `float32` [x, y, z]).
  - **Tableau des indices** : `index_count * 4` octets (entiers `int32`).
  - **Tableau des normales** (si `has_normals` == 1) : `vertex_count * 12` octets (triplets `float32`).
  - **Tableau des UVs** (si `has_uvs` == 1) : `vertex_count * 8` octets (paires `float32` [u, v]).

---

## 7. Section Métadonnées

Située à `meta_offset`.
- **Format** : Dictionnaire JSON encodé en UTF-8.
- **Contenu** : Dictionnaire de métadonnées personnalisées (ex. auteur, date de création, tags de classification).

---

## ⚡ Avantages Clés du Format

1. **Zéro-Parsing GPU** : La section des splats est directement copiable en VRAM dans un *Storage Buffer* (SSBO), l'alignement sur 16 octets étant garanti par la structure de `FoveaPackedSplat`.
2. **Compression Drastique** : Grâce à la quantification vectorielle (K-Means), la mémoire nécessaire pour stocker les attributs de couleur et d'anisotropie est réduite de plus de 80%.
3. **Fichier Unique** : Regroupe le nuage de points (Splats) et la géométrie polygonale de référence (Mesh) ainsi que le style dans un seul conteneur binaire cohérent.
