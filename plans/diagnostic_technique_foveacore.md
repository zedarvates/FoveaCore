# DIAGNOSTIC TECHNIQUE : Réduction de couleurs dans FoveaCore 3D Gaussian Splatting

## 1. Stockage et utilisation actuels des couleurs RGB

### Format CPU (GDScript - `GaussianSplat`)
- `color: Color` = `Color.WHITE` par défaut (RGBA, 32-bit float par canal)
- Stocké avec `opacity: float` séparé
- **Problème** : 128 bits par splat (32 bits × 4 canaux) pour la couleur seule

### Format GPU (Rust - `FoveaPackedSplat`)
- **Compression RGB565** : 16 bits (5 bits R, 6 bits G, 5 bits B)
- Stocké dans `color_index: u16`
- Conversion : `rgb565 = ((c0 * 31.0) as u16) << 11 | ((c1 * 63.0) as u16) << 5 | ((c2 * 31.0) as u16)`
- **Gain** : 128 bits → 16 bits (réduction 8×)

### Pipeline couleur
1. Entrée PLY : RGB 8-bit (0-255) ou SH coefficients (`f_dc_0/1/2`)
2. Conversion SH → RGB : `color = f_dc * 0.28209479 + 0.5` (ply_loader.gd)
3. Quantification RGB565 pour GPU
4. Décodage shader : extraction bit-shifts (splat_render_triangle.gdshader)

---

## 2. Structure de données des splats

### Structure CPU complète (~76 bytes + overhead GDScript)
```gdscript
class GaussianSplat:
  position: Vector3      # 12 bytes
  rotation: Quaternion   # 16 bytes
  scale: Vector3         # 12 bytes
  opacity: float         # 4 bytes
  color: Color           # 16 bytes
  depth: float           # 4 bytes
  radius: float          # 4 bytes
  covariance: Vector2    # 8 bytes
```

### Structure GPU optimisée (16 bytes/splat - `FoveaPackedSplat`)
```rust
#[repr(C, align(16))]
pub struct FoveaPackedSplat {
    pos_x: u16,      // 2 bytes - position quantifiée
    pos_y: u16,      // 2 bytes
    pos_z: u16,      // 2 bytes
    norm_u: i8,      // 1 byte  - normale (encodée)
    norm_v: i8,      // 1 byte
    color_index: u16,// 2 bytes - RGB565
    covar_index: u16,// 2 bytes - index VQ covariance
    opacity: u8,     // 1 byte  - 0-255
    layer_id: u8,    // 1 byte
    padding: u16,    // 2 bytes
}
// Total: 16 bytes exact
```

### Format fichier `.fovea`
- Header (48 bytes) + Codebook covariance (K × 32 bytes) + Splats (N × 16 bytes)
- **Exemple** : 100K splats = 1.6 MB (vs ~12 MB en flottant)

---

## 3. Shaders impliqués dans le rendu

### `splat_render_triangle.gdshader` (Vertex + Fragment)
- **Vertex** : Décodage 16 octets → position/couleur/covariance
- Calcul ellipse via valeurs propres (lignes 95-110)
- Foveated rendering (culling basé sur distance au regard)
- **Fragment** : `smoothstep(1.0, 0.85, dist_sq)` pour alpha doux

### `splat_math.gdshaderinc` (Librairie mathématique)
- `compute_cov3d()` : scale + rotation → matrice 3D
- `compute_cov2d()` : projection 3D→2D avec Jacobien
- `compute_sh_degree_0()` : conversion harmoniques sphériques

### `gpu_culling.gdshader` / `gpu_culling_compute.glsl`
- Compute shader Vulkan/OpenGL
- Culling frustum + Hi-Z occlusion
- Tri bitonique GPU pour tri profondeur (O(N log N) parallèle)

### `fovea_fast_path.rs` (Rust/GDExtension)
- Conversion PLY → .fovea binaire
- K-Means sur covariance (6 itérations, K=1024 max)
- Quantification spatiale 16-bit

---

## 4. Calculs d'opacité et de mélange

### Opacité CPU
- Initiale : `0.8` (gaussian_splat.gd)
- Modifiée par :
  - Profondeur : `opacity *= 1.0 / (1.0 + depth * 0.1)` (splat_generator.gd)
  - Foveation : `opacity *= weight` (gaussian_splat.gd)
  - Threshold : `if opacity < 0.05: cull` (foveacore_manager.gd)

### Opacité GPU
- Décodage : `float(data3 & 0xFFu) / 255.0` (ligne 60)
- Falloff : `smoothstep(1.0, 0.85, dist_sq) * v_opacity` (ligne 176)
- Discard : `if (alpha < 0.01) discard` (ligne 178)

### Mélange (Blending)
- Mode : `blend_mix` (ligne 10, shader)
- Configuration : `depth_draw_never, depth_prepass_alpha`
- Tri : Painter's algorithm CPU (`SplatSorter.sort_by_depth`)
- Pas de mélange additif (alpha blending classique)

---

## 5. Zones de réduction de couleurs (Opportunités)

### Zone A : Quantification RGB (Déjà optimisée ✅)
- **Actuel** : RGB565 (16 bits) via `color_index`
- **Potentiel** : Palette 256 couleurs (8 bits) avec dithering GPU
- **Gain estimé** : 16 bits → 8 bits (2× supplémentaire)

### Zone B : Opacité (8 bits - OK ✅)
- **Actuel** : `u8` (0-255) linéaire
- **Optimisation possible** : Stockage logarithmique (4-5 bits suffisent)
- **Gain estimé** : 8 bits → 4 bits (2×)

### Zone C : Couleur procédurale (Gaspillage ❌)
- **Problème** : `base_color` stocké par splat (16 bytes) dans `StyleEngine`
- **Optimisation** : Index palette matériaux (4 bits) au lieu de RGB
- **Gain** : 16 bytes → 0.5 byte (32×)

### Zone D : Normales (Surcoût ❌)
- **Actuel** : `norm_u/v` (2 bytes) mais inutilisés dans shader triangle
- **Optimisation** : Supprimer stockage ou compresser en 2 bits
- **Gain** : 2 bytes → 0.25 byte (8×)

### Zone E : Couches (Layer ID) (Gaspillage ❌)
- **Actuel** : `layer_id: u8` (1 byte) mais seulement 4-5 types utilisés
- **Optimisation** : 2 bits suffisent (BASE, SHADOW, LIGHT, SATURATION)
- **Gain** : 1 byte → 0.25 byte (4×)

---

## 6. Plan d'optimisation recommandé

### Priorité 1 (Faible effort, fort impact)
1. **Palette couleur 256-entrées** (8 bits au lieu de 16)
   - Ajout table de conversion dans header `.fovea`
   - Modification shader décodage
   - **Gain** : 2× compression, zéro perte visuelle

2. **Suppression norm_u/v** (2 bytes)
   - Non utilisés dans rendu triangle
   - **Gain** : 12.5% réduction taille splat (16→14 bytes)

### Priorité 2 (Moyen effort)
3. **Couche matériau indexée** (4 bits)
   - Palette 16 matériaux dans header
   - Remplace `base_color` procédural
   - **Gain** : 12× sur données matériaux

4. **Opacité 4-bit logarithmique**
   - Précision perceptuelle préservée
   - **Gain** : 2× sur opacité

### Priorité 3 (Élevé effort)
5. **Compression delta-position**
   - Encodage différentiel entre splats voisins
   - 8-10 bits au lieu de 16
   - **Gain** : 30-40% supplémentaire

---

## 7. Impact visuel estimé

| Optimisation | Perte visuelle | Gain taille |
|--------------|----------------|-------------|
| RGB565 → Palette 256 | Indétectable | 2× |
| Normales supprimées | Aucune (non utilisées) | 1.125× |
| Opacité 4-bit | Légère banding | 2× |
| Palette matériaux | Dépend texture | 32× (matériaux) |
| **TOTAL** | **Minime** | **~5-8×** |

**Nouvelle taille splat** : 16 bytes → **6-8 bytes**  
**Exemple** : 100K splats = 1.6 MB → **0.6-0.8 MB**

---

## 8. Code à modifier

Fichiers clés pour implémentation :
1. `addons/foveacore/shaders/fovea_fast_path.rs` - Format packed
2. `addons/foveacore/shaders/splat_render_triangle.gdshader` - Décodage
3. `addons/foveacore/scripts/reconstruction/gaussian_splat.gd` - Structure CPU
4. `addons/foveacore/scripts/splat_generator.gd` - Génération couleurs

**Risques** : 
- Perte compatibilité fichiers `.fovea` existants (nécessite versionning)
- Artefacts banding sur gradients doux (solution : dithering GPU)

---

**CONCLUSION** : L'architecture actuelle est déjà très optimisée (RGB565, 16 bytes/splat). Des gains supplémentaires **2-4×** sont possibles via palettes couleurs et compression fine, avec perte visuelle minimale. La réduction de couleurs RGB est déjà maximisée ; l'optimisation future doit se concentrer sur **compression spatiale** et **delta-encoding**.