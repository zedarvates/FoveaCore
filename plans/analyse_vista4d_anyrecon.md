# 🌐 Analyse Comparative — Écosystème DiffSynth pour FoveaEngine

> **Date :** 2026-05-03 | **Auteur :** FoveaEngine Team
>
> Analyse de 3 projets SOTA partageant l'écosystème **DiffSynth-Studio + Wan 2.1**, avec inspiration directe pour FoveaEngine.

---

## 1. VUE D'ENSEMBLE

| Projet | Équipe | Conférence | Pipeline |
|---|---|---|---|
| **HY-World-2.0** | Tencent Hunyuan | ArXiv 04/2026 | Vidéo → WorldMirror 2.0 (feed-forward) → 3DGS + depth |
| **Vista4D** | Eyeline Labs / Netflix | CVPR 2026 Highlight | Vidéo → recon 4D (DA3/Pi3X) → point cloud → Wan 2.1 diffusion → novel views |
| **AnyRecon** | Shanghai AI Lab / CUHK | ArXiv 04/2026 | Vues éparses → geometry memory → Wan 2.1 diffusion → 3D intégration |

### Convergence technique

Les 3 projets partagent un socle commun :
- **DiffSynth-Studio** : framework d'inférence Python (Modelscope)
- **Wan 2.1** : modèle backbone de diffusion vidéo (Wan-AI, 14B params)
- Pipeline **depth → point cloud → diffusion → views**
- Sortie **3DGS ou point cloud** utilisable dans un moteur de rendu

```
                 ┌──────────────────────────────────────┐
                 │         DiffSynth-Studio             │
                 │  (Python inference framework)         │
                 └──────────────────────────────────────┘
                         ↑         ↑         ↑
                         │         │         │
              ┌──────────┴──┐ ┌────┴─────┐ ┌┴──────────┐
              │ WorldMirror │ │ Vista4D  │ │ AnyRecon  │
              │   2.0       │ │          │ │           │
              │ feed-fwd    │ │ 4D recon │ │ geometry  │
              │ ~10s        │ │ ~10-120s │ │ ~30-300s  │
              └──────┬──────┘ └────┬─────┘ └────┬──────┘
                     │             │             │
                     ▼             ▼             ▼
              ┌──────────────────────────────────────┐
              │     gaussians.ply / points.ply       │
              │     camera_params.json               │
              │     depth/*.npy                      │
              └──────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────────────────────┐
              │  FoveaEngine Godot Plugin            │
              │  PLYLoader → SplatRenderer → VR      │
              └──────────────────────────────────────┘
```

---

## 2. VISTA4D — Analyse détaillée

**Repo :** https://github.com/Eyeline-Labs/Vista4D
**Paper :** https://arxiv.org/abs/2604.21915
**Models :** https://huggingface.co/Eyeline-Labs/Vista4D

### Pipeline complet

```
Source Video
  │
  ├─→ DA3 / Pi3X (4D reconstruction: depth + camera)
  │     └─→ SAM3 (dynamic mask segmentation)
  │
  ├─→ Unproject to 4D point cloud (temporally persistent)
  │     └─→ [Optionnel] Point cloud editing (duplicate/remove/insert)
  │     └─→ [Optionnel] Dynamic scene expansion (fuse casual capture)
  │
  ├─→ Render point cloud in target cameras
  │     └─→ depths, alpha masks, dynamic/static masks
  │
  └─→ Wan 2.1 T2V-14B (Vista4D finetune)
        └─→ Novel viewpoint video output
```

### Fonctionnalités inspirantes

| Fonctionnalité | Description technique | Applicable à FoveaEngine |
|---|---|---|
| **Point cloud editing** | Dupliquer/supprimer/insérer des sujets dans le nuage 4D avant diffusion  | Édition VR de scènes — SplatBrush avec undo/redo + compositing |
| **Dynamic scene expansion** | Fusionner une capture casual (~30s vidéo environnement) dans la reconstruction 4D | Ajouter des prises de vue additionnelles pour enrichir la scène Godot |
| **Temporal persistence** | Points statiques persistants à travers les frames (pas de re-génération de fond) | Optimisation mémoire : ne pas regénérer les zones statiques |
| **Camera UI Viser** | Interface réactive (React + FastAPI) pour keyframes caméra avec preview 3D temps réel | Inspirer un outil de pathfinding caméra dans l'éditeur Godot |
| **Long video + memory** | Découpage en clips → inférence clip par clip → intégration incrémentale du point cloud | Streaming par chunks pour gros assets `.fovea` |
| **Double reprojection** | Rendu du point cloud source dans les caméras cibles pour éviter les artéfacts de depth | Correction géométrique post-reconstruction |

### Prérequis techniques

- CUDA 12.8, PyTorch 2.10, GPU 24GB+ VRAM (Wan 2.1 14B)
- Flash Attention 2.8.3, XFuser (USP multi-GPU)
- 4D reconstruction : Pi3X (recommandé) ou DA3
- SAM3 pour segmentation masques dynamiques
- ~50 GB espace disque (checkpoints Wan 2.1 + Vista4D)

---

## 3. ANYRECON — Analyse détaillée

**Repo :** https://github.com/OpenImagingLab/AnyRecon
**Paper :** https://arxiv.org/abs/2604.19747
**Models :** https://huggingface.co/Yutian10/AnyRecon

### Pipeline complet

```
Sparse input frames (2-50 views, unordered)
  │
  ├─→ Establish initial 3D geometry memory (COLMAP / DUSt3R)
  │
  ├─→ Geometry-Driven View Selection
  │     └─→ Identifier les keyframes optimales pour la diffusion
  │
  ├─→ Point cloud rendering of selected views
  │
  ├─→ Wan 2.1 I2V-14B (AnyRecon LoRA)
  │     └─→ Unordered Contextual Video Diffusion
  │     └─→ 4-step distillation (rapide)
  │     └─→ Context-window sparse attention (O(n) vs O(n²))
  │
  └─→ 3D Geometry Memory Update
        └─→ Intégrer les nouvelles vues dans la mémoire globale
        └─→ ✦ Boucler vers View Selection pour itération
```

### Fonctionnalités inspirantes

| Fonctionnalité | Description technique | Applicable à FoveaEngine |
|---|---|---|
| **Global scene memory** | Cache de vues préfixé conservé entre les itérations pour cohérence long-terme | Cache persistant des splats visibles pour éviter re-génération |
| **Geometry-aware conditioning** | Génération ET reconstruction couplées via mémoire 3D explicite | Boucle fermée WorldMirror → rendu → feedback → re-reconstruction |
| **4-step distillation** | Diffusion distillée à 4 steps (au lieu de 50+) | Inférence WM2 en mode "fast" avec moins d'itérations |
| **Context-window attention** | Réduction O(n²) → O(n) via fenêtrage sparse pour longues séquences | Optimisation mémoire pour scènes >100k splats |
| **200+ frames support** | Inférence stable sur très longues trajectoires | Reconstruction de longs parcours caméra sans perte |
| **Geometry-Driven View Selection** | Sélection automatique des vues les plus informatives | Auto-sélection des frames clés pour la reconstruction |

### Prérequis techniques

- CUDA 11.8+, PyTorch 2.4.1
- Wan 2.1 I2V-14B + AnyRecon LoRA (~200 MB)
- ~30 GB espace disque

---

## 4. COMPARAISON AVEC FOVEAENGINE

| Critère | HY-World-2.0 | Vista4D | AnyRecon | FoveaEngine (actuel) |
|---|---|---|---|---|
| **Input** | Vidéo / images | Vidéo mono | Vues éparses (2-50) | Vidéo |
| **Reconstruction** | Feed-forward (1 passe) | 4D point cloud + diffusion | Géométrie mémoire + diffusion | WorldMirror 2.0 (1 passe) |
| **Temps reco** | 2-10s | 10-120s | 30-300s | 2-10s (WM2) ou 30-90min (COLMAP) |
| **Sortie 3D** | 3DGS + depth + normal + caméras | Point cloud 4D + novel views | Point cloud 3D + novel views | gaussians.ply + depth + caméras |
| **Rendu temps réel** | Non (Hors ligne) | Non (Hors ligne) | Non (Hors ligne) | **Oui (VR 90 FPS)** |
| **Édition 3D** | Non | Oui (édition point cloud) | Non | SplatBrush (VR) |
| **Moteur** | DiffSynth-Studio | DiffSynth-Studio | DiffSynth-Studio | Godot 4.6+ |
| **VRAM** | 8-16 GB | 24+ GB | 24+ GB | 8-16 GB |
| **Licence** | Apache/MIT | Apache 2.0 | Non spécifiée | MIT |

### Avantage unique de FoveaEngine

FoveaEngine est le SEUL de ces 4 projets à proposer :
1. **Rendu temps réel VR** à 90 FPS (foveated rendering)
2. **Intégration directe dans un moteur de jeu** (Godot)
3. **Pipeline complet** extraction → reconstruction → rendu → interaction
4. **Compression `.fovea`** (16B/splat, VQ 1024) pour le streaming
5. **Édition VR en temps réel** via SplatBrush

Les 3 autres projets sont des pipelines hors ligne → FoveaEngine est le consommateur final.

---

## 5. PLAN D'INTÉGRATION — Bridge DiffSynth Unifié

### Objectif

Un bridge Python unique (`diffsynth_bridge.py`) capable d'appeler les 3 backends :
1. **WorldMirror 2.0** — feed-forward (déjà intégré)
2. **Vista4D** — point cloud editing + novel viewpoint synthesis
3. **AnyRecon** — reconstruction vues éparses + long trajectories

### Architecture proposée

```python
# addons/foveacore/scripts/reconstruction/diffsynth_bridge.py
"""
Unified DiffSynth-Studio bridge for FoveaEngine.
Supports WorldMirror 2.0, Vista4D, and AnyRecon backends.

Usage:
    python diffsynth_bridge.py --backend worldmirror2 --input frames/ --output workspace/
    python diffsynth_bridge.py --backend vista4d --input video.mp4 --output workspace/ --task reshoot
    python diffsynth_bridge.py --backend anyrecon --input frames/ --output workspace/
"""

BACKENDS = {
    "worldmirror2": WorldMirror2Backend,   # already implemented
    "vista4d":      Vista4DBackend,        # to implement
    "anyrecon":     AnyReconBackend,       # to implement
}
```

### Phases d'implémentation

| Phase | Backend | Effort | Dépendances |
|---|---|---|---|
| **DiffSynth setup** | Script d'installation commun (torch + DiffSynth + flash-attn) | 1 jour | CUDA 12.x |
| **Vista4D bridge** | Pipeline point cloud rendering + Wan 2.1 inference | 3-5 jours | Vista4D checkpoints (HF) |
| **AnyRecon bridge** | Geometry memory + LoRA inference | 3-5 jours | AnyRecon LoRA + Wan I2V |
| **Unified CLI** | Sélection backend + format de sortie unifié | 1 jour | — |

### Format de sortie unifié

Indépendamment du backend, le bridge produit toujours :
```
workspace/
  ├── gaussians.ply          # 3DGS (WorldMirror 2.0) ou vide si non supporté
  ├── points.ply             # Point cloud complet
  ├── camera_params.json     # Extrinsics + intrinsics
  ├── depth/                 # Depth maps PNG
  ├── novel_views/           # Vues synthétisées (Vista4D / AnyRecon)
  └── .diffsynth_done        # Marqueur de complétion
```

---

## 6. RÉFÉRENCES

| Projet | Repo | Paper |
|---|---|---|
| **HY-World-2.0** | https://github.com/Tencent-Hunyuan/HY-World-2.0 | https://arxiv.org/abs/2604.14268 |
| **Vista4D** | https://github.com/Eyeline-Labs/Vista4D | https://arxiv.org/abs/2604.21915 |
| **AnyRecon** | https://github.com/OpenImagingLab/AnyRecon | https://arxiv.org/abs/2604.19747 |
| **DiffSynth-Studio** | https://github.com/modelscope/DiffSynth-Studio | — |
| **Wan 2.1** | https://github.com/Wan-Video/Wan2.1 | — |

---

*Analyse rédigée le 2026-05-03 — Base pour le bridge DiffSynth unifié.*
