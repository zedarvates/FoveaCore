# 🛡️ FoveaEngine : Technical Debt & Bottleneck Fix Plan

Cet "Implementation Plan" fait suite à l'audit critique identifiant les murs techniques bloquant le passage d'une maquette conceptuelle à un moteur de production VR fonctionnel.

---

## 🔴 Priorité 1 : Sortir du GDScript pour le Traitement d'Image (CPU -> GPU)
**Cible :** `studio_processor.gd` -> `mask_background`
**Problème :** Boucle double pixel-par-pixel (O(n*m)) gelant l'éditeur.
**Action :**
- [x] Créer un `Compute Shader` (`masking_compute.glsl`) utilisant le `RenderingDevice` de Godot 4.
- [x] Implémenter la logique HSV/Smart-Studio directement sur GPU.
- [x] Réduire le temps de traitement de ~2s par frame à < 5ms.

## 🔴 Priorité 2 : Un Backend Réel (Fin de la Simulation)
**Cible :** `reconstruction_backend.gd` & `reconstruction_manager.gd`
**Problème :** Utilisation de timers simulés pour COLMAP/3DGS.
**Action :**
- [x] Remplacer les simulations par des appels réels via `OS.execute_with_pipe`.
- [x] Capturer `stdout` et `stderr` en temps réel pour mettre à jour la logbox du panneau.
- [ ] Gérer les erreurs CUDA/OOM (Out Of Memory) et les rapporter à l'UI.

## 🔴 Priorité 3 : Lecture des Assets Gaussian Splatting (.PLY)
**Cible :** Nouveau format `.fovea` et `FoveaAssetLoader` (Rust)
**Problème :** Aucun moyen de charger les résultats denses de 3DGS sans saturer le CPU.
**Action :**
- [x] Implémenter le parseur binaire en GDExtension Rust (`godot-rust`) pour garantir la sécurité mémoire.
- [x] "Cuire" (Bake) les Harmoniques Sphériques (SH) en RGB via le `GameReadyOptimizer`.
- [x] Assurer un alignement strict à 16 octets des structures de données envoyées à la VRAM.

## 🟠 Priorité 4 : Performance VR (GPU Sorting & MultiMesh)
**Cible :** `splat_renderer.gd` & `splat_sorter.gd`
**Problème :** `ImmediateMesh` et tri CPU inutilisables à 90 FPS.
**Action :**
- [x] Migrer vers `MultiMeshInstance3D` pour le rendu massif via `FoveaSplatRenderer`.
- [x] Implémenter le `Bitonic Sort` en Compute Shader pour le tri in-place sur GPU.
- [x] Implémenter l'Occlusion Culling (Hi-Z) via un `CompositorEffect`.

## 🟠 Priorité 5 : Robustesse & UX Système
**Cible :** `reconstruction_manager.gd`
**Problème :** Chemins codés en dur et détection fragile.
**Action :**
- [ ] Utiliser `where` (Windows) ou `which` (Linux/Mac) pour l'auto-détection des binaires dans le PATH.
- [ ] Ajouter une validation de version (ex: `ffmpeg -version`) avant de commencer.
- [ ] Permettre la sauvegarde des chemins d'outils dans les `Settings` persistants de l'utilisateur.

---

## 📈 Roadmap de Résolution Immédiate (Semaine 1)

1. **Jour 1 :** Compute Shader pour le Masking (Stop the Freezes).
2. **Jour 2 :** Rust Fast-Path Loader (Bypass the CPU).
3. **Jour 3 :** Real Backend calls + Pipe Capture (Trust the Process).
4. **Jour 4 :** MultiMesh Renderer (Smooth the VR).

*"L'architecture est solide, passons maintenant à la puissance brute."*
