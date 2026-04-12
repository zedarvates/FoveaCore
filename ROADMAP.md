# 🗺️ FoveaEngine Roadmap : Future Vision

Ce document trace la route pour transformer FoveaCore en un moteur de rendu hybride (Mesh/3DGS) de classe mondiale, optimisé pour la VR.

---

## 🟢 Phase 1 : UX & Workflow (En cours)
*Objectif : Rendre le pipeline StudioTo3D accessible et robuste.*

- [x] **Smart Studio Masking** : Gestion intelligente des fonds blancs et noirs.
- [x] **ROI (Region of Interest)** : Système de Lasso pour isoler l'objet.
- [ ] **Visual ROI Tool** : Interface de dessin direct sur la première image de la vidéo.
- [ ] **Real-time Mask Preview** : Feedback instantané des réglages de détourage.
- [ ] **Reset & Session Management** : Facilitation des tests itératifs.

## 🟠 Phase 2 : Performance & Native Power (Le saut RUST 🦀)
*Objectif : Atteindre 90 FPS stables en VR avec des millions de points.*

- [ ] **Rust GDExtension** : Migration de `SplatSorter.gd` et `SurfaceExtractor.gd` vers Rust pour un gain de performance x10.
- [ ] **GPU Bitonic Sorting** : Déplacer le tri des profondeurs vers un Compute Shader.
- [ ] **Multithreading** : Paralléliser l'extraction des surfaces sur tous les cœurs CPU.
- [ ] **Optimization Hi-Z** : Finaliser le branchement natif de l'Occlusion Culler.

## 🔵 Phase 3 : Fidélité Visuelle & Stylisation
*Objectif : Créer une esthétique unique "Digital Painting".*

- [ ] **Anisotropic Splats** : Passer des cercles aux ellipses pour une fidélité photographique.
- [ ] **Parallax Proxy Rendering** : Technique inspirée de *Crimson Desert* pour simuler une profondeur extrême sur des surfaces simplifiées via POM (Parallax Occlusion Mapping).
- [ ] **Vectorized Splat Dispatcher** : Traitement par lots (Batching SIMD) pour une saturation maximale du GPU.
- [ ] **Spatial Chunking & Streaming** : Division des modèles en chunks spatiaux pour un chargement progressif (Priorité à la "première ligne" devant la caméra).
- [ ] **Splat Pattern Compression** : Optimisation algorithmique par reconnaissance de formes pour fusionner les splats redondants (Batching intelligent).
- [ ] **Artistic Shaders** : Effets de peinture à l'huile, aquarelle et hachures sur les splats.
- [ ] **MIP-Splatting & HLOD** : Système de LOD dynamique (Mesh à distance, Macro-splats à mi-distance, Micro-splats de près).
- [ ] **Custom `.fovea` Asset Format** : Container binaire propriétaire regroupant Mesh, Splats et Style pour une gestion propre des assets.
- [ ] **Dynamic Lighting** : Ombres portées dynamiques qui s'adaptent aux lumières Godot.

## 🟣 Phase 4 : Intelligence Artificielle & Cloud
*Objectif : Automatiser la création d'assets.*

- [ ] **ComfyUI Bridge** : Connexion directe via API pour générer des sources depuis Godot.
- [ ] **Auto-ROI** : Détection automatique de l'objet principal par IA.
- [ ] **Gaussian Compression** : Format de fichier ultra-léger pour le streaming VR.

---

*"Le futur du rendu ne consiste pas seulement à afficher des triangles, mais à peindre avec des volumes de lumière."*
