# 🗺️ FoveaEngine Roadmap : Future Vision

Ce document trace la route pour transformer FoveaCore en un moteur de rendu hybride (Mesh/3DGS) de classe mondiale, optimisé pour la VR.

---

## 🟢 Phase 1 : UX & Workflow (En cours)
*Objectif : Rendre le pipeline StudioTo3D accessible et robuste.*

- [x] **Smart Studio Masking** : Gestion intelligente des fonds blancs et noirs.
- [x] **ROI (Region of Interest)** : Système de Lasso pour isoler l'objet.
- [x] **Visual ROI Tool** : Interface de dessin direct (Pinceau/Gomme) sur l'aperçu.
- [x] **STAR Integration** : Pipeline rapide (DA3 Depth) inspiré d'InSpatio-World.
- [x] **WorldMirror 2.0 Integration** : Backend feed-forward SOTA remplaçant STAR simulé + COLMAP lent. [Plan détaillé →](plans/integration_worldmirror2.md)
  - [x] **Bridge Python WorldMirror** : `worldmirror_bridge.py` (~60 lignes) avec API diffusers-like
  - [x] **Backend GDScript** : Nouvelle méthode `_run_worldmirror_path()` dans le backend
  - [x] **Format compatibility** : Vérification sorties PLY/depth/cameras → pipeline FoveaEngine
  - [ ] **Installation script** : Script setup + dependency checker CUDA 12.4
  - [ ] **UI Mode sélecteur** : Radio COLMAP vs WorldMirror 2.0 dans le panel
- [ ] **Real-time Mask Preview** : Feedback instantané des réglages de détourage.
- [ ] **Reset & Session Management** : Facilitation des tests itératifs.

## 🟠 Phase 2 : Performance & Native Power (Le saut RUST 🦀)
*Objectif : Atteindre 90 FPS stables en VR avec des millions de points.*

- [x] **Rust GDExtension** : Pipeline Fast-Path implémenté (chargement ultra-rapide sans parsing CPU).
- [x] **GPU Bitonic Sorting** : Tri des profondeurs déporté vers un Compute Shader in-place.
- [ ] **Multithreading** : Paralléliser l'extraction des surfaces sur tous les cœurs CPU.
- [x] **Optimization Hi-Z** : Branchement natif de l'Occlusion Culler via `CompositorEffect`.

## 🔵 Phase 3 : Fidélité Visuelle & Stylisation
*Objectif : Créer une esthétique unique "Digital Painting".*

- [ ] **Anisotropic Splats** : Passer des cercles aux ellipses pour une fidélité photographique.
- [x] **Parallax Proxy Rendering** : (Prototype STAR implémenté) Simulation de profondeur sur surfaces simplifiées.
- [ ] **Vectorized Splat Dispatcher** : Traitement par lots (Batching SIMD) pour une saturation maximale du GPU.
- [ ] **Spatial Chunking & Streaming** : Division des modèles en chunks spatiaux pour un chargement progressif (Priorité à la "première ligne" devant la caméra).
- [ ] **Splat Pattern Compression (Vector Quantization)** : Utilisation de Codebooks (K-means) pour regrouper les couleurs, rotations et échelles redondantes en patterns indexés.
- [ ] **Spatial Quantization (Fixed-Point Math)** : Mappage des positions XYZ sur une grille 16-bits locale pour réduire drastiquement la bande passante mémoire.
- [ ] **Coplanar Splat Merging & Quad Simplification** : Fusion algorithmique des splats partageant la même profondeur/surface pour générer des quads unifiés et éliminer l'overdraw GPU.
- [ ] **Spherical Harmonics (SH) Baking** : Cuisson des reflets view-dependent complexes en couleurs diffuses pour les matériaux mats (réduction de 80% du poids des couleurs).
- [x] **Splat Backface Culling** : Compute Shader implémenté (`gpu_culling_compute.glsl`) pour éliminer instantanément les splats de dos.
- [ ] **Temporal & Interleaved Sorting** : Tri asynchrone des splats lointains étalé sur plusieurs frames pour garantir un temps d'exécution GPU strict de 11ms en VR.
- [ ] **Tile-Based Rasterization** : Division de l'écran en tuiles (16x16) dans le Compute Shader pour limiter le tri et le blending aux splats purement locaux (approche standard 3DGS).
- [x] **Two-Pass Hi-Z Occlusion Culling** : Lecture de la Depth Texture de Godot injectée dans le shader de culling pour éliminer les splats cachés.
- [ ] **FP16 Compute Pipeline** : Migration des buffers de calcul de float32 vers float16 pour doubler la bande passante VRAM et saturer les ALUs modernes.
- [ ] **Global Splat Instancing (Mega-Buffer)** : Rendu de milliers de copies du même asset (ex: forêts, foules) avec une seule copie en VRAM, via un Compute Shader multi-transform.
- [ ] **Delta-Splat Variants (Morphs & Overrides)** : Création de variantes légères d'objets instanciés (teintes de couleur, déformations locales) en ne stockant et calculant que la "différence" (Delta).
- [ ] **GPU-Driven Indirect Draw** : Élimination des synchronisations CPU-GPU (`rd.sync`) en laissant le Compute Shader écrire ses propres commandes de rendu (Draw indirect buffer).
- [ ] **Out-of-Core VRAM Streaming** : Chargement des chunks spatiaux directement du SSD vers la VRAM (DirectStorage style) pour des mondes ouverts infinis sans saturer la RAM.
- [ ] **Motion-Adaptive Splatting (Kinematic LOD)** : Étirement directionnel et réduction de densité des splats lors des mouvements rapides (flou de mouvement natif) pour économiser du fillrate.
- [ ] **Artistic Shaders** : Effets de peinture à l'huile, aquarelle et hachures sur les splats.
- [ ] **MIP-Splatting & HLOD** : Système de LOD dynamique (Mesh à distance, Macro-splats à mi-distance, Micro-splats de près).
- [x] **Fast-Path Binary Asset Format (`.fovea`)** : Container natif prêt pour le GPU (Direct Memory Upload) sans parsing CPU, implémenté en Rust.
- [ ] **Dynamic Lighting** : Ombres portées dynamiques qui s'adaptent aux lumières Godot.
- [ ] **Static vs Dynamic Splat Separation** : Traitement différencié (Baking/Octree pour le décor statique, Compute Skinning & Déformation pour les entités mobiles).

## 🟣 Phase 4 : Intelligence Artificielle & Cloud
*Objectif : Automatiser la création d'assets.*

- [ ] **ComfyUI Bridge** : Connexion directe via API pour générer des sources depuis Godot.
- [ ] **Auto-ROI** : Détection automatique de l'objet principal par IA.
- [ ] **Gaussian Compression** : Format de fichier ultra-léger pour le streaming VR.

---

*"Le futur du rendu ne consiste pas seulement à afficher des triangles, mais à peindre avec des volumes de lumière."*
