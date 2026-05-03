<p align="center">
  <img src="my%20icone/Earthandcheck.png" alt="FoveaEngine Icon" width="128">
</p>

# 👁️ FoveaEngine — Advanced 3DGS & Neural Reconstruction Engine

Welcome to **FoveaEngine**, a cutting-edge reconstruction and rendering pipeline for Godot 4.6+, specifically designed for high-fidelity VR experiences and artistic "Digital Painting" aesthetics.

---

> [!TIP]
> **🚀 WorldMirror 2.0 — Reconstruction en ~10 secondes**
> Le pipeline utilise désormais **WorldMirror 2.0** (Tencent Hunyuan) en backend principal : reconstruction feed-forward vidéo→3DGS+depth+caméras en un seul forward pass.
> - **Mode WorldMirror** : ~2-10s (recommandé, nécessite CUDA 12.4 + GPU 8GB+ VRAM)
> - **Mode COLMAP + 3DGS** (fallback) : 30-90 min, nécessite CUDA
> Voir [DEPENDENCIES.md](./DEPENDENCIES.md) pour la configuration.

> [!IMPORTANT]
> **Dépendances** : FFmpeg (obligatoire) + COLMAP (fallback) + WorldMirror 2.0 (recommandé).
> Consultez **[DEPENDENCIES.md](./DEPENDENCIES.md)** et exécutez `scripts/setup_worldmirror.bat` pour l'installation rapide.

---

## 🚀 État Actuel & Fonctionnalités

### ✅ Production-Ready

- **Rendu Core 3DGS**: Chargement PLY (binaire), GPU bitonic sort, MultiMeshInstance3D billboard
- **GPU Compute Culling**: Backface Culling + Hi-Z Occlusion Culling via compute shader
- **Fast-Path Rust**: Chargement binaire `.fovea` (16B/splat, VQ 1024 codebook)
- **WorldMirror 2.0 Bridge**: Reconstruction feed-forward vidéo→3DGS (~10s, SOTA)
- **StudioTo3D Pipeline**: Backend réel (FFmpeg extraction + WM2 inference ou COLMAP SfM + 3DGS)
- **GPU Background Masking**: Compute shader `mask_background_gpu.glsl` (Studio White, Chroma, Smart)
- **Style Engine**: 6 matériaux procéduraux (stone, wood, metal, skin, fabric, glass) + FBM/Worley noise
- **Gaussian Splatting**: PLY parsing, splat rendering, export, floaters detection
- **Foveated Rendering**: 3-zone VR rendering (base/saturation/light/shadow per zone)
- **SplatBrush**: VR sculpting tool functional

### 🚧 En cours

- **WM2 UI Controls**: Selecteur de mode WM2/COLMAP dans le panel (GDScript prêt, .tscn ajouté)
- **WorldMirror Camera Import**: OpenCV→Godot camera transform (code prêt, intégration partielle)
- **Eye Tracking**: API OpenXR implémentée, test hardware requis
- **Dynamic Lighting**: Calculs présents, connexion aux lumières Godot en cours
- **Hybrid Renderer**: Instancié, intégration pipeline principal en cours

### 📅 Roadmap

Voir **[ROADMAP.md](./ROADMAP.md)** pour le plan complet. Points clés à venir :
- Anisotropic Splats (ellipses)
- MIP-Splatting & HLOD
- Spatial Chunking & Streaming
- Tile-Based Rasterization
- Spherical Harmonics Baking
- ComfyUI Bridge pour génération IA
- WorldMirror 2.0 multi-GPU + prior injection

---

## 📂 Project Structure

| Dossier | Contenu |
|---|---|
| `addons/foveacore/` | Plugin cœur (scripts, shaders, Rust, GDExtension) |
| `addons/foveacore/scenes/` | Scènes préfabriquées (VR Rig, Playground, Workspace) |
| `addons/foveacore/scripts/reconstruction/` | Backend et UI StudioTo3D |
| `addons/foveacore/scripts/advanced/` | Rendu haute performance, interaction VR |
| `addons/foveacore/test/` | Tests unitaires et scènes de benchmark |
| `plans/` | Architecture détaillée, [Roadmap](ROADMAP.md), [intégration WM2](plans/integration_worldmirror2.md) |
| `scripts/` | Scripts setup (WorldMirror 2.0, dépendances) |
| `.github/workflows/` | CI/CD (lint GDScript, tests unitaires, validation Python) |

---

## 🛠️ Usage

1. **Install Plugin**: Activez `FoveaCore` dans les paramètres du projet Godot.
2. **Setup Dependencies**: Exécutez `scripts/setup_worldmirror.bat` (Windows) ou `.sh` (Linux/macOS).
3. **Reconstruction**: Ouvrez le panel `StudioTo3D`, sélectionnez une vidéo, cochez "WorldMirror 2.0", cliquez "▶ Run".
4. **VR Rendering**: Utilisez le nœud `FoveaSplattable` pour capturer des meshes et les afficher en splats.
5. **Testing**: Lancez `test/test_style_engine_desktop.tscn` pour des tests desktop sans VR.

---

## 🤝 Remerciements

<p align="center">🤍</p>

Ce projet est profondément redevable aux équipes dont les travaux open-source ont permis de débloquer des problèmes critiques de notre pipeline :

### Tencent Hunyuan — HY-World-2.0
L'équipe **[Tencent Hunyuan](https://github.com/Tencent-Hunyuan/HY-World-2.0)** a développé **WorldMirror 2.0**, un modèle feed-forward révolutionnaire qui remplace l'intégralité du pipeline COLMAP + 3DGS par une seule inférence neuronale. Leur travail open-source a été la clé de voûte qui nous a permis de passer d'un pipeline simulé (placeholder DA3) à une reconstruction réelle en ~10 secondes. Leur approche diffusers-like, leur documentation exemplaire et leur choix de licence permissive ont rendu cette intégration possible.

- **Repo**: https://github.com/Tencent-Hunyuan/HY-World-2.0
- **Paper**: https://arxiv.org/abs/2604.14268
- **Model**: https://huggingface.co/tencent/HY-World-2.0

### 3D Gaussian Splatting (Inria / Université Côte d'Azur)
L'implémentation de référence **[3DGS](https://github.com/graphdeco-inria/gaussian-splatting)** a défini le standard que nous suivons pour le rendu et le format PLY.

### COLMAP
Le pipeline **[COLMAP](https://github.com/colmap/colmap)** Structure-from-Motion reste notre fallback fiable pour les utilisateurs sans GPU compatible WorldMirror 2.0.

### Godot Engine
La **[Godot Foundation](https://godotengine.org/)** pour son moteur open-source qui rend possible le rendu VR temps réel avec compute shaders et GDExtension.

---

## 📈 État d'Avancement

| Phase | Statut |
|---|---|
| Phase 1 : Rendu Core | ✅ Complété |
| Phase 2 : Pipeline GPU | ✅ Complété |
| Phase 3 : Rust Fast-Path | ✅ Complété |
| Phase 4 : StudioTo3D + WorldMirror 2.0 | 🔄 En cours |
| Phase 5 : VR & Eye Tracking | 🔄 En cours |

### ✅ Réalisé
- Chargement binaire `.fovea` (Rust GDExtension, 16B/splat)
- Compute Shaders: Backface, Hi-Z Culling, Bitonic Sort
- Architecture Manager/Culler/Generator/Renderer/Composite
- Interface StudioTo3D avec ROI painting et masquage GPU
- Bridge WorldMirror 2.0 (reconstruction feed-forward)
- 25+ tests unitaires StyleEngine
- CI/CD GitHub Actions (lint + tests + validation Python)

### 🔄 En cours
- Intégration caméras WorldMirror 2.0 → Godot Camera3D
- Validation matériel VR
- Lumière dynamique connectée aux sources Godot
- Rendu artistique par couches

### ❌ Non implémenté
- Multiplayer Sync
- Splat Decals / MIP-Splatting
- ComfyUI Bridge (Phase 4 roadmap)

---

## 🛡️ License

FoveaEngine is released under the **MIT License**.
