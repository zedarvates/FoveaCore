# 🔬 FoveaEngine — Analyse R&D 3DGS Ecosystem 2026

> Basé sur : `About Gaussian Splats — They Just Became Playable.txt`,  
> `github.com/playcanvas/splat-transform`, `github.com/Atehortuajf/clay-transforms`  
> Date d'analyse : 2026-05-25

---

## 📋 RÉSUMÉ DE L'ÉCOSYSTÈME 3DGS EN 2026

### Ce qui a changé

Le document R&D identifie un **changement de paradigme** : les splats Gaussian sont passés de simples viewers statiques à des assets jouables et interactifs. Les avancées clés :

| Innovation | Impact sur FoveaEngine |
|---|---|
| **Mesh-inclusive 3DGS** (Kiri Engine v3) | Collision automatique depuis splats → débloque gameplay réel |
| **Format SPZ** (Niantic) | Fichiers 10× plus petits, compression 5× plus rapide |
| **Format SOG** (PlayCanvas) | Streaming LOD adaptatif, mobile 60 FPS |
| **Format GLB/KHR_gaussian_splatting** | Standard glTF = interop Unity/Unreal/Web |
| **Voxel collision export** | Physique 3D depuis données de scan |
| **LOD natif GPU** (Nano GS, Unreal) | Grandes scènes sans overhead mémoire |
| **4 GB VRAM suffisants** | Training accessible sur hardware grand public |

---

## 🔍 ANALYSE REPO 1 : `playcanvas/splat-transform`

**Nature :** CLI tool + bibliothèque JavaScript open source de PlayCanvas  
**Maturité :** Production (NPM publié, Docker backend, docs complètes)

### Formats supportés

**Lecture :** PLY, Compressed PLY, SOG, SPZ, SPLAT, KSPLAT, LCC  
**Écriture :** PLY, Compressed PLY, SOG, SPZ, **GLB**, CSV, HTML Viewer, LOD bundle, **Voxel JSON**, WebP

### Fonctionnalités clés analysées

```
-t, --translate         Translate Gaussians par (x, y, z)
-r, --rotate            Rotate par angles Euler
-s, --scale             Scale uniforme
-H, --filter-harmonics  Réduire les bandes SH (0-3) → LOD qualité
-N, --filter-nan        Nettoyer splats invalides
-B, --filter-box        Filtrer par boîte AABB
-S, --filter-sphere     Filtrer par sphère
-V, --filter-value      Filtrer par propriété (opacity, scale, couleur)
-F, --decimate          Réduire N% de splats via merging progressif
-G, --filter-floaters   Supprimer splats "fantômes" isolés (via voxel GPU)
-D, --filter-cluster    Garder seulement le cluster connecté principal
-l, --lod               Tagger splats par niveau LOD
-M, --morton-order      Réordonner par Morton code (Z-order curve) → cache GPU
--voxel.json output     Octree voxel sparse pour collision
```

### Ce que ça révèle sur notre gap architectural

Le format **SOG** (super-compressed, streaming) est ce qui permet le FPS browser en environnement scanné. C'est différent de notre pipeline `.fovea` actuel :
- SOG = streaming par chunks → **LOD géographique**
- `.fovea` actuel = chargement monolithique

**Morton ordering** est exactement ce que notre `SplatSorter` devrait faire : réordonner spatialement pour maximiser la cohérence de cache GPU.

**Voxel JSON output** génère un **sparse voxel octree** pour la collision → c'est la pièce manquante de notre pipeline physique.

---

## 🔍 ANALYSE REPO 2 : `Atehortuajf/clay-transforms`

**Nature :** Projet de recherche académique en cours, Python  
**Maturité :** Work in progress (3 commits, README placeholder)  
**Concept :** "Clay transforms for dynamic gaussian splatting"

### Architecture déduite (depuis train.py, loss.py, environment.yml)

```python
# Concept central :
# Pour chaque objet Gaussian Splat, optimiser N transformations "clay" 
# à chaque timestep. Chaque transform a un centre learnable.
```

**Stack :** PyTorch + Hydra (config) + einops + trimesh + Gradio  
**Nom de l'env conda :** `dynamic_gaussians`

### Ce que le concept "Clay Transform" signifie

Une **clay transform** est une transformation locale apprise par ML :
- Chaque splat appartient à une région d'influence d'un "centre"
- Le centre se déplace dans le temps (keyframe learning)
- Le splat est déformé proportionnellement à sa distance au centre
- C'est l'équivalent d'un **blend shape** mais pour des Gaussians

**Analogie :** comme de l'argile (clay) qu'on malaxe = déformation douce et continue.

La loss function combine plusieurs termes (pondérables via Hydra config) :
- Reprojection loss (rendu différentiable)
- Regularisation spatiale (cohérence entre splats voisins)

---

## 🎯 CE QUE NOUS DEVRIONS AJOUTER À FOVEAENGINE

### 🔴 PRIORITÉ 1 — Format & Pipeline (Critique)

#### 1.1 Support du format SPZ en lecture
Le format SPZ de Niantic est le plus compact pour production.  
**Action :** Implémenter `fovea_spz_loader.gd` ou l'intégrer dans le Fast-Path Rust.

```gdscript
# Interface cible dans notre pipeline
class_name FoveaSPZLoader extends RefCounted
func load_spz(path: String) -> Array[GaussianSplat]:
    # Décompression via Rust (zstd) → format interne
```

#### 1.2 Support du format SOG en lecture
SOG est le format streaming de PlayCanvas. C'est ce qui permet le LOD géographique adaptatif.  
**Action :** Implémenter un parser SOG (basé sur les `.webp` de textures + `meta.json`)

#### 1.3 Export GLB / KHR_gaussian_splatting
La spec KHR_gaussian_splatting est maintenant Release Candidate glTF.  
**Action :** Pipeline export `.fovea` → `.glb` pour interop Unity/Blender.

#### 1.4 Morton Order dans notre SplatSorter
Le tri par Morton code (Z-order curve) améliore la cohérence de cache GPU pour le rendu.  
**Action :** Remplacer/compléter `SplatSorter` avec Morton reordering au chargement.

```glsl
// Dans splat_sort_compute.glsl — ajouter pass Morton
uint morton_encode_3d(uvec3 pos) {
    // Bit interleaving X, Y, Z
}
```

---

### 🟠 PRIORITÉ 2 — Collision & Gameplay (Important)

#### 2.1 Voxel Octree pour collision
La fonctionnalité `--filter-floaters` de splat-transform utilise une voxelisation GPU pour identifier les splats "solides". On peut adapter ce concept pour générer notre propre CollisionShape.

**Action :** `fovea_voxelizer.gd` — Compute Shader qui voxelize les splats → génère un `VoxelGrid` → converti en `ConcavePolygonShape3D` ou `HeightMapShape3D`.

```gdscript
class_name FoveaVoxelizer extends Node
@export var voxel_resolution: float = 0.05  # 5cm par voxel
@export var opacity_threshold: float = 0.1

func generate_collision_shape(splats: Array[GaussianSplat]) -> Shape3D:
    # 1. Compute Shader → voxel grid 3D
    # 2. Marching cubes léger → mesh
    # 3. CollisionShape3D
```

#### 2.2 Filter Floaters (nettoyage automatique)
Les splats "fantômes" isolés dégradent le rendu et perturbent la collision.  
**Action :** Port du `--filter-floaters` de splat-transform dans notre Compute Shader de culling.

```glsl
// Ajout dans gpu_culler_pipeline.gd — pass nettoyage
// Voxeliser la scène à basse résolution
// Supprimer splats dans voxels sans voisins
```

#### 2.3 Filter Box / Sphere en éditeur
Permettre de découper un splat dans l'éditeur Godot (comme Photoshop pour la 3D).  
**Action :** Outil éditeur `FoveaSplatCropper` avec gizmo AABB/Sphere.

---

### 🟠 PRIORITÉ 3 — LOD Système (Important)

#### 3.1 LOD par bandes de Spherical Harmonics
L'action `--filter-harmonics <0|1|2|3>` de splat-transform révèle une approche de LOD qualitative :
- Bande 0 = couleur diffuse uniquement (très cheap)
- Bande 1 = + effets directionnels basiques
- Bande 2-3 = réflexions complètes (expensive)

**Action :** Dans notre shader de rendu, passer la bande SH max comme uniform selon la distance.

```glsl
// Dans splat_render.gdshader
uniform int sh_band_max = 3; // Passé par LOD system

vec3 eval_sh(vec3 dir, float sh[48]) {
    vec3 color = sh_band0(sh);
    if (sh_band_max >= 1) color += sh_band1(sh, dir);
    if (sh_band_max >= 2) color += sh_band2(sh, dir);
    if (sh_band_max >= 3) color += sh_band3(sh, dir);
    return color;
}
```

#### 3.2 LOD Géographique (SOG-inspired)
Diviser la scène en chunks streamables, chargés/déchargés selon la caméra.  
**Action :** `FoveaStreamingManager` — divise l'espace en cellules 16×16m, charge/décharge les `.fovea` chunks.

---

### 🟡 PRIORITÉ 4 — Dynamic Gaussian Splatting (R&D)

Inspiré de `clay-transforms` — c'est de la **recherche en cours** mais stratégiquement important.

#### 4.1 Concept Clay Transform dans FoveaEngine
Une clay transform permet des déformations locales et continues des splats dans le temps. C'est la base pour :
- **Personnages 3DGS animés** (sans squelette classique)
- **Végétation dynamique** (vent, collision douce)
- **Fluides splat** (amélioration du SoftMatter actuel)

**Action (long terme) :** `FoveaClayDeformer` — Compute Shader qui applique des transformations locales pondérées par distance.

```gdscript
class_name FoveaClayDeformer extends Node
## Chaque "clay handle" est un point de contrôle dans l'espace
var clay_handles: Array[ClayHandle] = []

class ClayHandle:
    var position: Vector3
    var radius: float          # Zone d'influence
    var transform: Transform3D # Déformation appliquée
    var falloff: Curve         # Atténuation selon distance

func deform(splats: Array[GaussianSplat], dt: float) -> void:
    # Pour chaque splat, somme des influences des handles voisins
    # Appliqué via Compute Shader
```

#### 4.2 Blend Shapes pour Splats
Analogue aux blend shapes de mesh, mais pour des Gaussians.  
**Action :** Stocker des "deltas" de position/rotation/couleur interpolables dans le format `.fovea`.

---

### 🟡 PRIORITÉ 5 — Outils de Nettoyage (Qualité)

#### 5.1 Filter NaN/Inf automatique
Au chargement d'un fichier PLY/SPZ, nettoyer automatiquement les splats invalides.  
**Action :** Dans `FoveaAssetLoader` (Rust), passer sur chaque splat et rejeter NaN/±Inf sur position/scale.

#### 5.2 Decimate (réduction de splats)
splat-transform propose un `--decimate` via merging progressif pairwise.  
**Action :** `FoveaSplatDecimator` — fusion des splats les plus proches spatialement (à distance < threshold).

```gdscript
func decimate_to(splats: Array, target_count: int) -> Array:
    # Tri spatial par Morton code
    # Fusion progressive des paires les plus proches
    # Merge = moyenne pondérée par opacité
```

---

## 🗺️ PLAN D'INTÉGRATION RECOMMANDÉ

| Sprint | Feature | Effort | Impact |
|---|---|---|---|
| Sprint 1 | Format SPZ reader (Rust) | M | 🔴 Critique |
| Sprint 1 | Morton order dans SplatSorter | S | 🔴 Critique |
| Sprint 1 | Filter NaN/Inf au chargement | S | 🟠 Important |
| Sprint 2 | Filter Floaters (Compute Shader) | L | 🟠 Important |
| Sprint 2 | LOD par bandes SH dans shader | M | 🟠 Important |
| Sprint 2 | Voxel Octree → CollisionShape | L | 🟠 Important |
| Sprint 3 | Filter Box/Sphere (outil éditeur) | M | 🟡 Normal |
| Sprint 3 | LOD Géographique / Streaming | XL | 🟡 Normal |
| Sprint 3 | Format SOG reader | L | 🟡 Normal |
| Sprint 4 | Export GLB KHR_gaussian_splatting | M | 🟡 Normal |
| Sprint 4 | FoveaClayDeformer (R&D) | XL | 🟡 R&D |
| Sprint 4 | Blend Shapes Splats | XL | 🟡 R&D |

---

## 💡 INSIGHTS STRATÉGIQUES

### Ce que PlayCanvas a compris (et qu'on doit reproduire)
1. **La chaîne complète est clé :** scan → nettoyage → compression → streaming → rendu → collision
2. **SOG + LOD = le futur du rendu splat temps réel** sur mobile et web
3. **Morton ordering** est trivial à implémenter mais critique pour les performances GPU

### Ce que clay-transforms préfigure
Les "dynamic gaussian splatting" vont devenir le standard pour les personnages et les scènes animées. Notre `SoftMatter` actuel est une proto-version de ce concept. **C'est une direction R&D à prendre sérieusement.**

### Écart FoveaEngine vs état de l'art
| Aspect | FoveaEngine Actuel | État de l'Art 2026 |
|---|---|---|
| Formats supportés | `.fovea` (binaire custom) | PLY, SPZ, SOG, GLB, KSPLAT |
| Compression | Aucune | SPZ (10×), SOG (streaming) |
| LOD | Hiérarchique basique | SH bands + Géographique streaming |
| Collision | Absente | Voxel Octree GPU |
| Dynamisme | SoftMatter proto | Clay Transforms (ML) |
| Nettoyage | Absent | Filter NaN, Floaters, Cluster |

---

*Document généré le 2026-05-25 — FoveaEngine R&D*
