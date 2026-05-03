# 🔗 Plan d'Intégration — WorldMirror 2.0 → FoveaEngine

> **Date :** 2026-05-03 | **Auteur :** FoveaEngine Team
>
> Remplacer les backends de reconstruction simulés/placeholder par WorldMirror 2.0 (Tencent Hunyuan), un modèle feed-forward SOTA qui reconstruit depth, normals, caméras, point clouds et 3DGS en un seul forward pass.

---

## 1. CONTEXTE : ÉTAT ACTUEL DE LA RECONSTRUCTION

### Pipeline actuel (fichiers concernés)

```
reconstruction_manager.gd  ── orchestre 3 phases
  ├── studio_processor.gd        Phase 1: extraction frames (ffmpeg réel ✅) + masquage GPU (réel ✅)
  ├── reconstruction_backend.gd  Phase 2: COLMAP SfM (réel ✅) OU star_bridge.py (SIMULÉ ❌)
  └── reconstruction_backend.gd  Phase 3: 3DGS training (réel ✅) → PLY → SplatRenderer ✅
```

### Problèmes identifiés

| Composant | Problème |
|---|---|
| `star_bridge.py:34-35` | DA3 model instancié mais **poids non chargés** — fallback heuristique (luminance inversée + Sobel) |
| `star_bridge.py:72` | Extrinsics = matrice identité, intrinsics = `[w, h, w/2, h/2]` hardcodés — **pas de pose estimation réelle** |
| `star_simulator.py` | Génère des données synthétiques (OK pour tests, PAS pour production) |
| `ply_loader.gd / studio_to_3d_panel.gd` | Mismatch d'API : appelle `load_ply()` sur `PLYLoader` qui expose `load_gaussians_from_ply()` |
| Pipeline COLMAP | Lent (30+ min pour vidéo 10s), nécessite GPU NVIDIA, paramétrage manuel |

### Ce qui est déjà solide

- FFmpeg frame extraction et masquage GPU ✅
- PLY parsing → GaussianSplat → MultiMeshInstance3D rendering ✅
- GPU bitonic depth sort + Hi-Z occlusion culling ✅
- Foveated rendering 3 zones (base/saturation/light/shadow) ✅
- Format `.fovea` compressé (VQ 1024 codebook, 16B/splat) ✅
- Gestion OOM, timeout, hang detection dans le backend ✅

---

## 2. WORLD MIRROR 2.0 — CE QU'IL APPORTE

### Comparaison technique

| Critère | COLMAP + 3DGS (actuel) | WorldMirror 2.0 |
|---|---|---|
| **Temps de reconstruction** | 30-90 minutes | ~2-10 secondes (single forward pass) |
| **Type** | Optimization itérative | Feed-forward (réseau de neurones) |
| **Input** | Images multi-vues | Vidéo OU images multi-vues (1-32 frames) |
| **Outputs** | Sparse point cloud + 3DGS PLY | Depth maps, normals, camera poses (c2w+intrinsics), point cloud 3D, 3DGS attributes (means/scales/quats/opacities/SH) |
| **Caméra estimation** | COLMAP SfM (parfois instable) | Prédite directement par le réseau |
| **Modèle** | classique (SIFT + BA + densification) | Neural (~1.2B params, ViT backbone) |
| **GPU requis** | NVIDIA CUDA | CUDA 12.4 (ou CPU, lent) |
| **VRAM** | 6-12 GB (3DGS training) | ~8-16 GB (selon résolution et nombre de frames) |
| **API** | CLI (scripts Python) | CLI + diffusers-like Python API + Gradio app |
| **Multi-GPU** | Non | Oui (FSDP + Sequence Parallel + BF16) |
| **Modèle** | Propriétaire (3DGS) + COLMAP (BSD) | Open-source (Apache/MIT-like) |
| **Maturité** | Production-proven | Avril 2026 release, partial open-source |

### Mapping des formats de sortie

```
WM2 Output                    → FoveaEngine Equivalent
─────────────────────────────────────────────────────────
gaussians.ply (standard PLY)  → PLYLoader.load_gaussians_from_ply() ✅ compatible
points.ply                    → EnhancedPointCloudViewer ✅ compatible
depth/*.npy                   → star_loader.gd (déjà conçu pour ça) ✅
normal/*.png                  → StyleEngine / lighting ✅ ajout mineur
camera_params.json            → ReconstructionSession (poses 4×4) ✅ compatible
sparse/0/cameras.bin          → ColmapSparseImporter ✅ déjà implémenté
```

---

## 3. PLAN D'INTÉGRATION — 4 PHASES

### Phase A : WorldMirror 2.0 Backend Bridge (semaine 1-2) 🔴 Priorité maximale

**Objectif :** Remplacer `star_bridge.py` par un bridge WorldMirror 2.0 fonctionnel.

#### Tâche A1 : Nouveau bridge Python `worldmirror_bridge.py`

```python
# Remplace addons/foveacore/scripts/reconstruction/star_bridge.py
# Nouveau fichier : addons/foveacore/scripts/reconstruction/worldmirror_bridge.py

"""
WorldMirror 2.0 bridge for FoveaEngine.
Drop-in replacement for the STAR bridge using Tencent Hunyuan's WorldMirror 2.0.
"""
import argparse, json, sys, os
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Directory of extracted frames")
    parser.add_argument("--output", required=True, help="Workspace output directory")
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--target_size", type=int, default=952)
    parser.add_argument("--fps", type=int, default=2)
    parser.add_argument("--save_depth", action="store_true", default=True)
    parser.add_argument("--save_normal", action="store_true", default=True)
    parser.add_argument("--save_gs", action="store_true", default=True)
    parser.add_argument("--save_camera", action="store_true", default=True)
    parser.add_argument("--save_points", action="store_true", default=True)
    parser.add_argument("--save_colmap", action="store_true", default=False)
    args = parser.parse_args()

    from hyworld2.worldrecon.pipeline import WorldMirrorPipeline

    pipeline = WorldMirrorPipeline.from_pretrained('tencent/HY-World-2.0')
    pipeline(
        input_path=args.input,
        output_path=args.output,
        target_size=args.target_size,
        save_depth=args.save_depth,
        save_normal=args.save_normal,
        save_gs=args.save_gs,
        save_camera=args.save_camera,
        save_points=args.save_points,
        save_colmap=args.save_colmap,
        strict_output_path=args.output,  # flat output, no timestamp subdirs
    )

if __name__ == "__main__":
    main()
```

**Spécifications :**
- CLI compatible avec l'appel actuel du backend GDScript : `python worldmirror_bridge.py --input <frames_dir> --output <workspace>`
- Sorties placées directement dans `workspace/` (pas de sous-dossiers timestamp)

#### Tâche A2 : Modifier `reconstruction_backend.gd`

Ajouter une nouvelle méthode `_run_worldmirror_path()` :

```gdscript
func _run_worldmirror_path(session: ReconstructionSession) -> void:
    var args := PackedStringArray([
        "worldmirror_bridge.py",
        "--input", session.output_directory + "/input",
        "--output", session.output_directory,
        "--device", "cuda",
        "--target_size", str(_target_size),      # nouveau @export
        "--fps", str(session.extraction_fps)
    ])
    var pid := OS.create_process(python_path, args)
    await _watch_process(pid, session)  # réutilise la boucle async existante
```

#### Tâche A3 : Modifier `reconstruction_manager.gd`

- Remplacer la branche `use_fast_sync` par `use_worldmirror` (nouveau flag)
- La branche COLMAP+3DGS reste en fallback pour compatibilité
- Le pipeline complet devient : `extract → worldmirror → done` (1 étape au lieu de 3)

#### Tâche A4 : Install script & dependency checker

```bash
# Nouveau script : scripts/setup_worldmirror.sh (et .bat pour Windows)
pip install torch==2.4.0 torchvision==0.19.0 --index-url https://download.pytorch.org/whl/cu124
pip install -r requirements_worldmirror.txt
# Optionnel : FlashAttention pour perf
```

---

### Phase B : Format Bridge & Conversion (semaine 2-3) 🟠 Priorité haute

**Objectif :** Assurer que les sorties WM2 sont consommables par toute la chaîne FoveaEngine.

#### Tâche B1 : Fixer le mismatch d'API `PLYLoader`

Actuellement `studio_to_3d_panel.gd:475` appelle `_PLYLoaderScript.load_ply()` qui n'existe pas. Deux options :
- **Option 1 (simple) :** Ajouter un wrapper `static func load_ply(path) -> Dictionary` dans `PLYLoader` qui appelle `load_gaussians_from_ply()` et retourne un dict compatible
- **Option 2 (propre) :** Refactorer le panel pour utiliser directement `load_gaussians_from_ply()`

Recommandé : Option 1 pour rétrocompatibilité, Option 2 en follow-up.

#### Tâche B2 : Importer les caméras WM2 → Godot

Créer `worldmirror_camera_importer.gd` :

```gdscript
class_name WorldMirrorCameraImporter
extends Node

static func import_cameras(json_path: String) -> Array[Camera3D]:
    # Lit camera_params.json (format WM2)
    # Crée des Camera3D avec extrinsics 4×4 + intrinsics
    # Convention : OpenCV → Godot (Y-up → -Y)
```

#### Tâche B3 : Charger les depth maps WM2 dans le pipeline

Modifier `star_loader.gd` (ou créer un équivalent) pour charger les `.npy` depth maps de WM2 :
- WM2 format : `float32 [H, W]`, valeurs Z-depth
- Appliquer au shader `star_proxy.gdshader` (parallax mapping déjà existant)

#### Tâche B4 : Mapping des attributs 3DGS

Vérifier la compatibilité du format PLY WM2 avec `PLYLoader.load_gaussians_from_ply()` :
- WM2 produit `gaussians.ply` en format standard (x, y, z, opacity, scale_0/1/2, rot_0/1/2/3, f_dc_0/1/2)
- `PLYLoader` parse exactement ces propriétés → **compatible à 100%**
- Seule vérification nécessaire : ordre des propriétés dans le header PLY

---

### Phase C : UI & UX (semaine 3-4) 🟡 Priorité moyenne

#### Tâche C1 : Nouvelle option "WorldMirror 2.0 (Fast)" dans l'UI

Dans `studio_to_3d_panel.gd`, ajouter un radio button ou dropdown :
- `Mode COLMAP + 3DGS` (fallback, lent, pas de modèle requis)
- `Mode WorldMirror 2.0` (recommandé, ~10s, nécessite CUDA 12.4 + modèle HF)

#### Tâche C2 : Preview 3D en temps réel

Inspiré de la Gradio app WM2, ajouter une preview 3D interactive dans Godot :
- Depth map visualization (fausse couleur)
- Point cloud preview avant import complet
- Normal map overlay

#### Tâche C3 : Barre de progression adaptée WM2

Le pipeline WM2 n'a pas de "pourcentage progressif" comme COLMAP (c'est un forward pass). Afficher :
- "Downloading model..." (première utilisation, depuis HuggingFace)
- "Running WorldMirror 2.0..." (forward pass, ~2-10s)
- "Post-processing..." (conversion formats, ~1s)

---

### Phase D : Avancé (semaine 5+) 🟢 Long terme

#### Tâche D1 : Panorama Generation (HY-Pano 2.0)

Quand HY-Pano 2.0 sera open-source, l'intégrer pour :
- Génération de skyboxes 360° pour les scènes VR
- Text-to-panorama → input pour WorldStereo 2.0 → monde 3D complet

#### Tâche D2 : Multi-GPU optimisé

Activer FSDP + BF16 pour les scènes lourdes (>32 frames, >500k pixels) :
```python
torchrun --nproc_per_node=2 -m hyworld2.worldrecon.pipeline \
    --input_path frames/ --use_fsdp --enable_bf16
```

#### Tâche D3 : Prior Injection pour qualité maximale

Permettre à l'utilisateur d'injecter :
- Caméra intrinsics connues (ex : depuis calibration VR headset)
- Depth map LiDAR ou COLMAP (fusion avec WM2)
- Via `--prior_cam_path` et `--prior_depth_path`

#### Tâche D4 : Bridge ComfyUI (Phase 4 existante du ROADMAP.md)

Quand World Generation sera open-source (WorldNav + WorldStereo 2.0 + WorldMirror 2.0) :
- Connexion ComfyUI → WorldMirror 2.0 pour génération procédurale
- Text/Image → 3D World complet, directement dans Godot

#### Tâche D5 : WM2 comme service local

Wrapper HTTP autour de WM2 pour :
- Exécution en arrière-plan (pas de blocage Godot)
- Cache des modèles en RAM (VRAM persistante)
- Queue de reconstruction (batch processing)

---

## 4. IMPACT SUR LE CODE EXISTANT

### Fichiers modifiés

| Fichier | Modification |
|---|---|
| `reconstruction_backend.gd` | +30 lignes : nouvelle méthode `_run_worldmirror_path()` |
| `reconstruction_manager.gd` | +20 lignes : flag `use_worldmirror`, appel backend |
| `reconstruction_session.gd` | +2 champs : `use_worldmirror` (bool), `target_size` (int) |
| `studio_to_3d_panel.gd` | +50 lignes : radio mode WM2, UI adaptée |
| `studio_dependency_checker.gd` | +15 lignes : vérification CUDA 12.4 + modèle HF |

### Fichiers remplacés

| Ancien fichier | Nouveau fichier | Raison |
|---|---|---|
| `star_bridge.py` (108 lignes, simulé) | `worldmirror_bridge.py` (~60 lignes, réel) | Modèle fonctionnel vs placeholder |
| `star_simulator.py` (53 lignes) | Conservé pour tests | Simulateur utile pour CI sans GPU |

### Fichiers conservés (compatibilité)

| Fichier | Rôle conservé |
|---|---|
| `studio_processor.gd` | Extraction frames + masquage (toujours nécessaire avant WM2) |
| `dataset_exporter.gd` | Export frames/masks (toujours nécessaire) |
| `reconstruction_backend.gd` | Backend process execution (réutilisé pour WM2) |
| `ply_loader.gd` | Parsing PLY de sortie (WM2 produit du PLY standard) |
| `splat_renderer.gd` | Rendu 3DGS dans Godot |
| `splat_sorter.gd` | Tri GPU des splats |
| `floaters_detector.gd` | Nettoyage post-reconstruction (WM2 peut générer des outliers) |

---

## 5. DÉPENDANCES & PRÉREQUIS

### Nouvelles dépendances Python

```
torch==2.4.0+cu124
torchvision==0.19.0+cu124
# hyworld2 s'installe depuis le repo GitHub cloné
# requirements_worldmirror.txt fourni par le repo
```

### GPU requis

| Configuration | VRAM min | Temps estimé |
|---|---|---|
| GPU NVIDIA (CUDA 12.4) | 8 GB | 2-5s (8 frames) |
| GPU NVIDIA (CUDA 12.4) | 16 GB | 5-10s (32 frames, target_size=1904) |
| CPU fallback | 16 GB RAM | 30-120s (déconseillé) |

### Stockage modèle

- Modèle WorldMirror 2.0 : ~5 GB (téléchargé automatiquement depuis HuggingFace)
- Cache HF par défaut : `~/.cache/huggingface/hub/`

---

## 6. RISQUES & MITIGATIONS

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| WM2 ne tourne pas sur GPU AMD/Intel | Moyenne | Medium | Fallback CPU lent + conserver COLMAP |
| Changements d'API WM2 (encore en dev) | Moyenne | Faible | Pinner version commit hash, pas `main` |
| Modèle HF indisponible/trop lent à télécharger | Faible | Élevé | Mirror local + cache + fallback COLMAP |
| Incompatibilité format PLY (propriétés non standard) | Faible | Faible | Adapter `ply_loader.gd` pour supporter variantes |
| VRAM insuffisante pour target_size élevé | Moyenne | Medium | `disable_heads` pour économiser la VRAM |
| Licence incompatible | Faible | Élevé | Vérifier la licence du modèle (Apache/MIT-like d'après le repo) |

---

## 7. KPI & SUCCÈS

### Métriques techniques

| Métrique | Avant (COLMAP+3DGS) | Après (WM2) | Cible |
|---|---|---|---|
| Temps reconstruction (vidéo 10s) | 30-90 min | 2-10s | <15s |
| Camera pose accuracy | Variable (SfM) | Prédite (SOTA) | ATE < 0.02 |
| Point cloud completeness | Moyenne | Élevée (feed-forward) | F1 > 0.40 |
| 3DGS quality | Bon (7000 iter) | Bon (direct) | PSNR > 28 dB |
| VRAM pic | 6-12 GB | 8-16 GB | <16 GB |
| Fallback dispo | Oui (COLMAP) | Oui (COLMAP conservé) | 100% |

### Métriques utilisateur

-  1 clic pour passer d'une vidéo à un modèle 3D visualisable
- Preview 3D interactive avant import final
- Pas de configuration manuelle (COLMAP params cachés)

---

## 8. RÉFÉRENCES

- **WorldMirror 2.0 repo :** https://github.com/Tencent-Hunyuan/HY-World-2.0
- **WorldMirror 2.0 paper :** https://arxiv.org/abs/2604.14268
- **HuggingFace model :** https://huggingface.co/tencent/HY-World-2.0
- **WorldMirror 1.0 (legacy) :** https://github.com/Tencent-Hunyuan/HunyuanWorld-Mirror
- **WorldStereo (background) :** https://github.com/FuchengSu/WorldStereo
- **HY-World-2.0 product page :** https://3d.hunyuan.tencent.com/sceneTo3D

---

*Plan rédigé le 2026-05-03 — Prêt pour implémentation.*
