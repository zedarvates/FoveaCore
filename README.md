# 👁️ FoveaEngine — Advanced 3DGS & Neural Reconstruction Engine

Welcome to **FoveaEngine**, a cutting-edge reconstruction and rendering pipeline for Godot 4.6+, specifically designed for high-fidelity VR experiences and artistic "Digital Painting" aesthetics.

---

> [!TIP]
> **Performance & Temps de calcul** : Le pipeline de reconstruction (SfM & 3DGS Training) est extrêmement intensif.
> - **Phase 2 (COLMAP)** : Peut durer de 2 à 15 minutes selon la vidéo. L'interface peut sembler figée.
> - **Phase 3 (3DGS)** : Peut durer de 15 à 30 minutes. 
> - **GPU** : Une carte NVIDIA avec CUDA est fortement recommandée pour des performances acceptables.

---

> [!IMPORTANT]
> **Dépendances requises** : Le pipeline StudioTo3D nécessite **FFmpeg** et **COLMAP**.
> Veuillez consulter le guide **[DEPENDENCIES.md](./DEPENDENCIES.md)** pour configurer votre environnement.

---

## 🚀 État Actuel & Fonctionnalités

> ⚠️ **Note importante**: Ce moteur est en **Phase Développement Pré-Alpha**. Certaines fonctionnalités sont prototypées mais pas entièrement branchées ou testées.

### ✅ Implémenté & Fonctionnel
- **Rendu Core Gaussian Splatting**: Chargement, tri et affichage de splats via MultiMesh
- **Fast-Path Rust**: Chargeur binaire `.fovea` implémenté et fonctionnel
- **GPU Compute Culling**: Backface Culling + Hi-Z Occlusion Culling sur Compute Shader
- **Bitonic Sort GPU**: Tri des profondeurs 100% sur GPU (0 CPU overhead)
- **StudioTo3D UI**: Panel interface complet avec masquage Chroma/Luma
- **Génération procédurale**: Génération de splats depuis les meshes Godot
- **Style Engine**: 5 matériaux procéduraux + FBM/Worley noise

### 🚧 En cours / Prototypé (Non finalisé)
- **StudioTo3D Pipeline**: Interface existe mais backend FFmpeg/COLMAP simulé
- **Eye Tracking**: API OpenXR implémentée mais non testée sur hardware réel
- **Layered Splatting**: Structure existe mais rendu par couche non branché
- **SplatBrush**: Architecture présente mais collision/interaction non implémentée
- **Dynamic Lighting**: Calculs présents mais non connecté aux lumières Godot
- **Hybrid Renderer**: Instancié mais pas intégré au pipeline principal

### 📅 Roadmap / A venir
- Support des splats anisotropiques (ellipses)
- Format binaire `.fovea` complet avec sérialisation
- Mise en cache LOD / MIP-Splatting
- Bridge ComfyUI pour génération IA
- Synchronisation Multiplayer VR

---

## 📂 Project Structure

- `addons/foveacore/`: The core plugin and scripts.
- `addons/foveacore/scenes/`: Ready-to-use scenes (VR Rig, Playground, Workspace).
- `plans/`: Detailed architecture, [Roadmap](ROADMAP.md), and [reconstruction_prompts.md](plans/reconstruction_prompts.md).
- `tutorials/`: [Get Started Guide](tutorials/get_started.md).
- `scripts/reconstruction/`: The StudioTo3D backend and UI.
- `scripts/advanced/`: High-end rendering and interaction controllers.

---

## 🛠️ Usage

1. **Install Plugin**: Enable `FoveaCore` in Godot project settings.
2. **Reconstruction**: Open the `StudioTo3D` panel or run `studio_workspace.tscn`.
3. **Optimized Masking**: Use **Smart Studio** mode and **Draw ROI Mask** to isolate your objects from complex backgrounds (black edges, shadows).
4. **Rendering**: Use the `FoveaSplattable` node. It automatically captures your mesh and can hide it to show splats.
5. **Testing**: Run `splat_brush_playground.tscn` to test VR interactions.

---

## 📈 État d'Avancement

✅ **Phase 1 : Rendu Core** - COMPLÉTÉ  
✅ **Phase 2 : Pipeline GPU** - COMPLÉTÉ  
✅ **Phase 3 : Rust Fast-Path** - COMPLÉTÉ  
🔄 **Phase 4 : StudioTo3D** - EN COURS  
🔄 **Phase 5 : VR & Eye Tracking** - EN COURS  

### ✅ Réalisé
- Chargement binaire ultra-rapide en Rust
- Compute Shaders: Backface & Hi-Z Culling
- Tri Bitonic 100% GPU
- Architecture complète Manager/Renderer
- Interface StudioTo3D

### 🔄 En cours de développement
- [ ] Connexion réelle FFmpeg / COLMAP
- [ ] Test et validation matériel VR
- [ ] Implémentation complète SplatBrush
- [ ] Rendu couches artistiques
- [ ] Lumière dynamique

### ❌ Non implémenté
- Multiplayer Sync
- Splat Decals
- MIP-Splatting
- Bridge IA

---

## 🛡️ License

FoveaEngine is released under the **MIT License**. Created by the FoveaEngine Team for the next generation of VR developers.
