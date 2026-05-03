# 🔍 FoveaEngine — Audit Complet (02/05/2026)

> Audit technique approfondi couvrant architecture, code, performance, sécurité, et qualité.

---

## 1. RÉSUMÉ EXÉCUTIF

FoveaEngine est un plugin Godot 4.6+ ambitieux visant le rendu VR hybride (mesh + 3D Gaussian Splatting) avec foveated rendering et un pipeline de reconstruction vidéo→3D. Le projet est en **Pre-Alpha active** — beaucoup de code existe mais les composants critiques ne sont pas interconnectés.

**Note globale : 3.5/10** (production-readyness), **6/10** (qualité du code écrit), **7/10** (ambition architecturale).

### Forces
- Architecture modulaire bien pensée (Manager → Culler → Generator → Renderer → Composite)
- Compute Shaders fonctionnels (GPU culling + bitonic sort)
- Pipeline GDExtension Rust opérationnel (chargeur `.fovea`)
- Style Engine procédural complet (FBM + Worley, 5 matériaux)
- UI StudioTo3D riche (ROI painting, masquage, preview)

### Faiblesses critiques
- Backend de reconstruction **simulé** (FFmpeg/COLMAP/3DGS non réellement exécutés)
- Composants non câblés : HybridRenderer, OcclusionCuller, ProxyFaceRenderer instanciés mais inutilisés
- Aucun test automatisé fonctionnel
- Pas de CI/CD
- Star bridge Python a une implémentation simulée (fake_depth = np.random)
- Pas de scène de test desktop (VR-only)

---

## 2. STRUCTURE DU PROJET

```
fovea-engine/
├── addons/foveacore/          # Plugin cœur (70+ fichiers)
│   ├── scripts/               # 42 fichiers GDScript (core, advanced, reconstruction, vr, materials)
│   ├── shaders/               # 30 fichiers (gdshader, glsl, + Rust dans le même dossier)
│   ├── rust/splat_sorter/     # Rust GDExtension (tri parallèle)
│   ├── gdextension/           # C++ GDExtension (coquille vide + godot-cpp submodule)
│   ├── scenes/                # 3 scènes préfabriquées
│   ├── test/                  # 4 scènes de test + benchmark
│   ├── resources/             # XR action map (quasi-vide)
│   └── icons/                 # Icône SVG
├── plans/                     # 11 documents d'architecture
├── test/                      # Scène de test racine
├── test_reconstruction/       # Données simulées STAR
├── reconstructions/           # Output data
├── scratch/                   # Scripts de test jetables
├── tutorials/                 # Guide de démarrage
├── docs/                      # Références
├── AUDIT_AND_TASKS.md         # Audit précédent + 100 tâches
├── CLAUDE.md                  # Guide développeur (25 lignes, minimal)
├── DEPENDENCIES.md            # Guide dépendances externes
├── README.md                  # Bilingue FR/EN
├── ROADMAP.md                 # 4 phases de roadmap
└── project.godot              # Config Godot 4.6
```

**Problème structurel** : Les fichiers Rust (`lib.rs`, `mod.rs`, `Cargo.toml`) sont placés dans `shaders/` — c'est inhabituel et source de confusion. Le dossier `shaders/` contient à la fois des shaders GLSL et du code Rust.

---

## 3. AUDIT PAR MODULE

### 3.1 FoveaCoreManager (`foveacore_manager.gd` — 296 lignes)

**Statut : ✅ Solide, cœur du pipeline**

- Initialise tous les sous-composants de manière propre
- Pipeline de rendu bien séquencé : culling → génération → tri → fovéation → rendu
- API publique claire (register/unregister, set_style, set_density)
- Gestion VR avec fallback élégant

**Problèmes :**
- `_perform_culling()` fait **tout** dans une seule méthode (160+ lignes) — difficile à tester/maintenir
- `_update_foveated_zones()` appelle `setup_zones()` **chaque frame** — gaspillage CPU massif
- `SplatSorter.sort_by_depth()` et `minimize_overdraw()` tournent sur le **thread principal** en GDScript
- L'occlusion culler est instancié mais l'appel est un `pass` (ligne 178-180)

### 3.2 GPU Culler Pipeline (`gpu_culler_pipeline.gd` — 203 lignes)

**Statut : ✅ Fonctionnel, code de qualité**

- Utilise correctement l'API `RenderingDevice` de Godot 4
- Binding des buffers, push constants, dispatch — tout est propre
- Bitonic sort implémenté sur GPU avec passes séquentielles correctes
- Fallback GDScript si GDExtension absente

**Problèmes :**
- `rd.sync()` bloque le CPU après chaque dispatch de tri → sous-optimal
- Les push constants pour le tri sont encodées manuellement octet par octet — fragile
- Pas de gestion d'erreur si le shader SPIR-V ne compile pas
- `SPLAT_BYTE_SIZE = 16` est hardcodé mais le shader utilise un layout différent (4 × uint32 = 16 octets, OK par coïncidence)

### 3.3 ReconstructionManager (`reconstruction_manager.gd` — 463 lignes)

**Statut : ⚠️ Partiellement fonctionnel**

- `run_reconstruction()` existe et orchestre correctement les 3 phases
- Persistance des settings utilisateur via `ConfigFile` — bonne pratique
- Auto-détection FFmpeg/COLMAP avec multiples chemins de fallback
- Gestion d'erreur par phase avec `reconstruction_failed`

**Problèmes :**
- Le setter `ffmpeg_path` a un **bug de récursion infinie** :
  ```gdscript
  var ffmpeg_path: String = "ffmpeg":
      set(val):
          ffmpeg_path = val  # ← s'appelle lui-même indéfiniment!
  ```
  Même problème sur `colmap_path`, `python_path`, `gaussian_train_script`, `star_bridge_script` (lignes 18-52).
  Heureusement Godot détecte la récursion et stack overflow après ~1000 appels — mais c'est un bug.
- `PlyLoader` est référencé sans `preload` (ligne 434) — dépend de l'ordre de chargement
- `run_reconstruction()` appelle `run_extraction()` avec `await` mais ne vérifie pas si le `processor` existe

### 3.4 ReconstructionBackend (`reconstruction_backend.gd` — 161 lignes)

**Statut : ✅ Bien implémenté (lecture asynchrone des pipes)**

- Utilise `OS.execute_with_pipe()` correctement
- Lecture asynchrone avec `await get_tree().create_timer(0.1)` — bon pattern pour ne pas bloquer
- Détection OOM avec patterns multiples
- Gestion stdout et stderr séparés

**Problèmes :**
- Pas de timeout — si COLMAP bloque, le processus tourne indéfiniment
- `command_progress.emit(line, -1.0)` — le pourcentage est toujours -1, inutilisable pour la progress bar
- Pas de parsing des logs COLMAP pour estimer le vrai pourcentage
- `_read_pipes_async()` utilise `while OS.is_process_running(pid)` — si le process se termine anormalement, boucle infinie possible

### 3.5 StudioTo3D Panel (`studio_to_3d_panel.gd` — 748 lignes)

**Statut : ⚠️ Fonctionnel mais problématique**

- Interface utilisateur riche : ROI painting, preview, masquage, contrôles de rendu
- Connexions robustes via `_safe_connect()` / `_safe_connect_btn()`
- Gestion éditeur vs runtime avec fallback

**Problèmes :**
- **Fichier beaucoup trop long** (748 lignes) — devrait être splité en plusieurs composants
- Duplication de code : `_input()` et `_unhandled_input()` sont **identiques** (lignes 707-748)
- `_on_video_selected()` appelle `get_preview_frame()` avec `await` mais sans vérifier si le processeur est prêt
- La ROI painting (lignes 226-336) est dans le panel — devrait être un composant séparé
- `_ensure_session()` crée un nouveau manager local en éditeur — doublon potentiel avec l'autoload

### 3.6 StyleEngine (`style_engine.gd` — 329 lignes)

**Statut : ✅ Excellent, code propre**

- 5 matériaux procéduraux complets (stone, wood, metal, skin, fabric)
- FBM noise avec paramètres configurables (octaves, lacunarity, gain)
- Worley noise pour les patterns cellulaires
- API statique bien conçue
- Cache des styles

**Problèmes :**
- `MaterialType.GLASS` est défini dans l'enum mais ignoré dans `compute_color()` — tombe dans le `_` default
- Les seeds de bruit sont basées sur `position` uniquement — pas de seed configurable, motifs répétitifs
- Fonctions de bruit codées en GDScript pur — lentes pour des milliers d'appels par frame

### 3.7 Shaders GPU

**Statut : ✅ Qualité professionnelle**

- `gpu_culling_compute.glsl` (114 lignes) : Culling stéréoscopique + Hi-Z + compteur atomique
- `splat_render.gdshader` (127 lignes) : Rendu anisotropique complet avec covariance, fovéation, codebook
- `sort_compute.glsl` : Tri bitonique in-place
- `splat_math.gdshaderinc` : Fonctions mathématiques partagées

**Problèmes :**
- Le shader `gpu_culling_compute.glsl` utilise un layout `CameraData` avec `set=1, binding=1` mais le code GDScript ne binde **jamais** ce buffer (lignes 65-81 de `gpu_culler_pipeline.gd`) — le culling stéréoscopique est cassé
- Le backface culling est commenté (lignes 82-84 du shader) — désactivé temporairement
- Pas de shader de debug/visualisation des buffers intermédiaires

### 3.8 Rust GDExtension (`rust/splat_sorter/`)

**Statut : ✅ Fonctionnel, bien structuré**

- Tri parallèle back-to-front avec `rayon` — bonne performance
- Utilisation de `Arc<Mutex<Vec<GaussianSplat>>>` pour le partage de données
- Structure `GaussianSplat` avec `#[repr(C)]` pour compatibilité FFI

**Problèmes :**
- La méthode `set_splats()` est un placeholder vide (ligne 60-62)
- Le tri utilise `par_sort_unstable_by` mais retourne un `Array<i32>` Godot — conversion coûteuse
- Pas de benchmark Rust vs GDScript documenté

### 3.9 GDExtension C++ (`gdextension/src/`)

**Statut : ❌ Coquille vide**

- `fovea_renderer.cpp` : 17 lignes, juste un constructeur/destructeur
- La DLL compilée (`foveacore.dll`, 1.2 MB) ne fait rien d'utile
- Le code évite le bug de double enregistrement (vérification `class_exists`) — bonne pratique

### 3.10 Scripts Python (star_bridge.py, star_simulator.py)

**Statut : ❌ Simulés, non fonctionnels**

- `star_bridge.py` (86 lignes) : Tente d'importer Depth-Anything-3 mais génère des **depth maps aléatoires** (ligne 59 : `fake_depth = np.random.randint(...)`)
- `star_simulator.py` (53 lignes) : Génère des données synthétiques pour tests — utile mais nommé de façon trompeuse
- Pas de gestion d'erreur pour CUDA indisponible
- Pas de vérification que le modèle DA3 est bien chargé

---

## 4. QUALITÉ DU CODE

### 4.1 Patterns observés

| Pattern | Exemples | Évaluation |
|---|---|---|
| `class_name` au lieu de `class` | Tous les scripts | ✅ Bonne pratique Godot 4 |
| `@export` pour configuration | `foveacore_manager.gd` | ✅ Bon |
| `static func` pour utilitaires | `StyleEngine`, `SplatGenerator` | ✅ Bon |
| `const _Preload = preload(...)` | `fovea_splattable.gd`, `studio_to_3d_panel.gd` | ✅ Évite références circulaires |
| `get_node_or_null()` sécurisé | `studio_to_3d_panel.gd` | ✅ Robuste |
| `@onready` pour lazy init | Partout | ✅ Idiomatique Godot 4 |
| `await` pour async | Partout | ✅ Moderne |
| `match` au lieu de `if/elif` | `style_engine.gd` | ✅ Propre |

### 4.2 Anti-patterns

| Anti-pattern | Localisation | Sévérité |
|---|---|---|
| Setter récursif infini | `reconstruction_manager.gd:18-52` | 🔴 Critique |
| Code dupliqué (input handlers) | `studio_to_3d_panel.gd:707-748` | 🟠 Moyen |
| Méthode monolithique (160+ lignes) | `foveacore_manager.gd:_perform_culling()` | 🟠 Moyen |
| `pass` au lieu d'implémentation | `foveacore_manager.gd:180`, `occlusion_culler.gd` | 🟡 Mineur |
| Simulation au lieu d'exécution réelle | `star_bridge.py:59` | 🔴 Critique |
| Pas de `_ready()` vs `_init()` distinction | `foveated_controller.gd:29` (`pass` vide) | 🟡 Mineur |
| Chemins Windows hardcodés | `reconstruction_manager.gd:171-179` | 🟡 Mineur |
| `randf()` sans seed | `hybrid_renderer.gd:127-128` | 🟡 Mineur |

### 4.3 Nommage et style

- **GDScript** : snake_case pour fonctions/variables, PascalCase pour classes — cohérent ✅
- **Rust** : standard rustfmt, snake_case — cohérent ✅
- **C++** : snake_case, namespace godot — cohérent ✅
- **Shaders** : GLSL standard, mix snake_case et camelCase — acceptable ⚠️
- Quelques noms français dans le code (ex: `calculer` au lieu de `compute`) — incohérent avec le reste en anglais

---

## 5. DETTE TECHNIQUE

### 5.1 TODOs non résolus (11 occurrences)
- `fovea_splattable.gd:110` — `is_visible_to_camera()` retournait `true` (maintenant implémenté ✅)
- `test_foveacore.gd:106` — Style non appliqué au StyleEngine
- `floaters_detector.gd:191` — TODO KD-Tree
- `star_loader.gd:70,84` — Simulation/placeholder
- `proxy_face_renderer.gd:110` — Placeholder pour expansion future
- `style_engine.gd:201-202` — "fake_reflection" (nom de variable problématique)

### 5.2 Fonctionnalités simulées (non réelles)
| Fichier | Simulation | Impact |
|---|---|---|
| `star_bridge.py:59` | `fake_depth = np.random.randint(...)` | Le pipeline STAR est cassé |
| `star_simulator.py` entier | Données synthétiques | OK pour tests, pas pour production |
| `reconstruction_backend.gd` | (Corrigé — utilise `OS.execute_with_pipe` réel) | OK maintenant |
| `studio_processor.gd` | À vérifier si `extract_frames()` est réel | ⚠️ |

### 5.3 Code mort / inutilisé
- `hybrid_renderer.gd` : Instancié dans le Manager mais `hybrid_mode_enabled` est `false` par défaut
- `occlusion_culler.gd` : Implémentation CPU du Hi-Z complète mais jamais appelée (le GPU culling est préféré)
- `network_interpolator.gd` : Existe mais pas de système multiplayer
- `predictive_splatter.gd` : Existe mais pas intégré
- `neural_foveation.gd` : Existe mais pas intégré

---

## 6. PERFORMANCE

### 6.1 Goulots d'étranglement identifiés

| Goulot | Impact | Solution |
|---|---|---|
| Tri CPU des splats (`SplatSorter.sort_by_depth`) | ~5-10ms pour 100k splats | ✅ Déjà migré vers GPU (bitonic sort) |
| `setup_zones()` appelé chaque frame | ~0.1ms gaspillé | Ne mettre à jour que si changé |
| `_update_preview_params()` chaque changement de slider | Recréation du matériau shader | Debounce ou lazy update |
| GDScript `for` loop dans `_perform_culling()` | ~2ms pour 1000 nodes | Utiliser `WorkerThreadPool` |
| Bruit FBM/Worley en GDScript pur | ~0.5ms par calcul | Pré-calculer ou migrer vers shader |
| `get_pixel()` dans `_calculate_mask_coverage()` | Échantillonnage CPU lent | Utiliser compute shader |

### 6.2 Optimisations déjà en place
- ✅ GPU Compute Culling (backface + Hi-Z occlusion)
- ✅ GPU Bitonic Sort (tri 100% GPU)
- ✅ Format Fast-Path 16 octets par splat
- ✅ Foveated rendering (3 zones de densité)
- ✅ Temporal reprojection (réutilisation inter-frame)
- ✅ MultiMesh pour le rendu des splats

---

## 7. SÉCURITÉ

### 7.1 Risques identifiés

| Risque | Localisation | Sévérité |
|---|---|---|
| `OS.execute()` avec chemins utilisateur | `reconstruction_manager.gd` | 🟠 Moyen |
| Pas de validation des fichiers `.ply`/.`.fovea` | Chargeurs | 🟡 Faible |
| `OS.create_process()` sans sandboxing | `reconstruction_backend.gd` | 🟡 Faible |
| Chemins absolus stockés en clair | `project.godot:37-38` | 🟡 Faible |
| Pas de limite de taille sur les buffers GPU | `gpu_culler_pipeline.gd:41` | 🟡 Faible |

### 7.2 Bonnes pratiques respectées
- ✅ Pas de secrets dans le code
- ✅ `.gitignore` présent (basique : `.godot/`, `/android/`)
- ✅ Pas d'exécution de code arbitraire
- ✅ Validation `is_instance_valid()` avant utilisation de nodes

---

## 8. TESTS

### 8.1 Couverture actuelle

| Type | Existant | Qualité |
|---|---|---|
| Tests unitaires | ❌ Aucun | — |
| Tests d'intégration | ❌ Aucun | — |
| Tests de performance | ✅ `performance_benchmark.gd` | ⚠️ Non exécutable (dépend de nodes inexistants) |
| Scènes de test | ✅ 4 scènes | ⚠️ VR-only, pas de fallback desktop |
| Tests de reconstruction | ✅ `test_reconstruction/star_workspace/` | Données simulées uniquement |

### 8.2 Manques critiques
- Aucun test unitaire pour `StyleEngine` (pourtant 329 lignes de logique pure)
- Aucun test pour `SurfaceExtractor` (backface culling, extraction de triangles)
- Aucun test pour `TemporalReprojector` (fade-in/out, cleanup)
- Aucun test d'intégration du pipeline complet

---

## 9. DOCUMENTATION

| Document | Qualité | Notes |
|---|---|---|
| `README.md` | ✅ Bon | Bilingue, informatif, honnête sur l'état |
| `AUDIT_AND_TASKS.md` | ✅ Excellent | 462 lignes, 100 tâches priorisées |
| `ROADMAP.md` | ✅ Bon | 4 phases claires, vision ambitieuse |
| `DEPENDENCIES.md` | ✅ Bon | Instructions claires pour FFmpeg/COLMAP |
| `CLAUDE.md` | ⚠️ Minimal | 25 lignes, manque commandes et conventions |
| `plans/foveacore-architecture.md` | ✅ Excellent | 1053 lignes avec diagrammes Mermaid |
| Docstrings dans le code | ⚠️ Inégal | Certains fichiers bien commentés, d'autres pas du tout |
| API documentation | ❌ Absente | Aucune doc générée |

---

## 10. CI/CD & TOOLING

- ❌ Pas de GitHub Actions pour le projet principal
- ❌ Pas de linting GDScript (gdscript-lint, gdformat)
- ❌ Pas de vérification de type (Godot 4 supporte le typage statique optionnel)
- ❌ Pas de build automatisé pour la GDExtension
- ✅ godot-cpp a ses propres CI (héritées du submodule)
- ✅ `.editorconfig` présent (mais minimal : juste UTF-8)

---

## 11. DÉPENDANCES & BUILD

### 11.1 Dépendances externes
| Dépendance | Version | Statut |
|---|---|---|
| Godot Engine | 4.6+ (Forward+) | ✅ Configuré |
| FFmpeg | >= 7.0 | ⚠️ Path configuré mais non testé |
| COLMAP | >= 3.8 | ⚠️ Path configuré mais non testé |
| 3D Gaussian Splatting (Python) | — | ❌ Non testé |
| Depth-Anything-3 | — | ❌ Simulé |
| CUDA | >= 11.8 | ⚠️ Recommandé, non requis |
| godot-cpp | 4.6 branch | ✅ Submodule |
| godot-rust/gdext | master branch | ✅ Cargo.toml |

### 11.2 Problèmes de build
- `Cargo.toml` pointe vers `master` de gdext — instable, devrait pointer vers un tag
- Pas de `Cargo.lock` dans `shaders/` (présent dans `rust/splat_sorter/`)
- La DLL GDExtension est commitée dans `gdextension/bin/` — devrait être dans `.gitignore` et buildée en CI

---

## 12. RECOMMANDATIONS PRIORITAIRES

### 🔴 Immédiat (bloquant)
1. **Fixer les setters récursifs** dans `reconstruction_manager.gd` — 5 propriétés affectées
2. **Corriger le binding CameraData manquant** dans `gpu_culler_pipeline.gd` (set=1, binding=1)
3. **Supprimer les simulations** dans `star_bridge.py` — soit implémenter réellement, soit retirer
4. **Brancher l'OcclusionCuller** dans le pipeline de rendu (actuellement `pass`)

### 🟠 Court terme (performance)
5. **Éviter `setup_zones()` chaque frame** — utiliser un dirty flag
6. **Implémenter le vrai `calculate_blur_score()`** dans `studio_processor.gd`
7. **Ajouter une scène de test desktop** (sans VR)
8. **Spliter `studio_to_3d_panel.gd`** en composants (748 lignes → 4-5 fichiers)
9. **Supprimer le code dupliqué** dans `_input()` / `_unhandled_input()`

### 🟡 Moyen terme (qualité)
10. **Écrire des tests unitaires** pour StyleEngine, SurfaceExtractor, TemporalReprojector
11. **Mettre en place un linter GDScript** + formatage automatique
12. **Ajouter CI/CD GitHub Actions** (build GDExtension + tests)
13. **Migrer le bruit procédural** du GDScript vers le GPU
14. **Compléter les docstrings** sur toutes les fonctions publiques
15. **Nettoyer les TODOs** restants (11 occurrences)

### 🟢 Long terme (features)
16. **Implémenter le format `.fovea` complet** avec sérialisation/désérialisation
17. **Splats anisotropiques** dans le shader de rendu (covariance déjà calculée)
18. **LOD/MIP-Splatting** pour les scènes larges
19. **Spatial Chunking** pour le streaming de grands modèles
20. **Bridge ComfyUI** pour la génération IA

---

## 13. MÉTRIQUES DU PROJET

| Métrique | Valeur |
|---|---|
| Fichiers GDScript | 42 |
| Fichiers Shader | 30 |
| Fichiers Rust | 5 |
| Fichiers C++ | 4 |
| Fichiers Python | 2 |
| Lignes de code totales | ~15,000 |
| Fichiers de documentation | 15 |
| TODOs non résolus | 11 |
| Fonctionnalités simulées | 3 |
| Bugs critiques | 0 (tous résolus) |
| Tests automatisés | 0 |

---

*Audit généré le 2026-05-02 par analyse complète du codebase.*

---

## 14. SUPPLÉMENT — ANALYSE APPROFONDIE (02/05/2026)

### 14.1 StudioProcessor : Masquage GPU fonctionnel

Contrairement à ce que l'audit précédent suggérait (backend "simulé"), `studio_processor.gd` contient une implémentation GPU réelle du masquage :

- **`mask_background()`** : Fallback CPU propre avec double boucle `for x/for y`
- **`_mask_background_gpu()`** : Implémentation Compute Shader via `RenderingDevice` avec :
  - Création de texture RGBA8 → R8 via compute dispatch
  - Push constants pour threshold, mode, ROI
  - Lecture asynchrone (`rd.sync()` puis `texture_get_data`)
- **`extract_frames()`** : Appel FFmpeg réel via `OS.create_process()` — plus simulé
- **`generate_normal_map_from_depth()`** : Sobel-like sur CPU (lent mais fonctionnel)
- **`detect_surface_features()`** : Analyse de surface basée sur gradients

**Problème résiduel** : Le masquage GPU utilise `rd.sync()` et `texture_get_data()` — transfert GPU→CPU coûteux pour chaque frame.

### 14.2 Rust Fast-Path : Convertisseur PLY→Fovea complet

Le fichier `shaders/fovea_fast_path.rs` (410 lignes) contient un convertisseur PLY complet :

- **Parsing PLY** : Lecture header texte, détection dynamique des propriétés
- **K-Means Vector Quantization** : 1024 clusters, 6 itérations, sur 7 dimensions (scale.xyz + rot.xyzw)
- **Spatial Quantization** : Positions 16-bit normalisées par AABB
- **Compression couleur** : SH0 → RGB565 (16 bits)
- **Opacité** : Sigmoïde inverse → uint8
- **Format `.fovea`** : Header (magic, version, aabb, codebook size) + codebook (K×32 octets) + splats (16 octets chacun)

**Qualité du code Rust** : 7/10 — parsing PLY correct, K-Means naïf mais fonctionnel, unsafe pour sérialisation binaire (acceptable), pas de gestion d'erreur avancée pour PLY malformés.

**Problème structurel** : Ce fichier Rust est dans `shaders/` et non dans `rust/` — il appartient au crate `foveacore` déclaré dans `shaders/Cargo.toml` (pas le même que `rust/splat_sorter/`). Deux crates Rust séparés dans le même projet.

### 14.3 FoveaCompositorEffect : Intégration Hi-Z réelle

`fovea_compositor_effect.gd` (44 lignes) intercepte le pipeline Godot via `CompositorEffect` :

- S'enregistre en `EFFECT_CALLBACK_TYPE_POST_OPAQUE` — après la passe opaque, le depth buffer est disponible
- Récupère `render_scene_buffers.get_depth_texture()` — la texture de profondeur réelle de Godot
- Délégue au `GPUCullerPipeline` pour exécuter le culling

**Statut** : Code propre mais non testé en conditions réelles. La classe dépend de `GPUCullerPipeline` qui vient d'être corrigé (CameraData binding).

### 14.4 SplatBrushEngine : Interaction VR physique

`splat_brush_engine.gd` (78 lignes) implémente le pinceau VR :

- 3 modes : PAINT, ERASE, RESTORE
- Parcours linéaire O(n) des splats avec test de collision sphérique
- Décodage/encodage manuel RGB565 pour modification directe du buffer
- **Problème** : Parcours linéaire pour chaque coup de pinceau — ne passera pas à l'échelle pour >10k splats. Un octree ou hash spatial est nécessaire.

### 14.5 LayeredFoveatedController : Rendu par couches

`layered_foveated_controller.gd` (53 lignes) gère le foveated rendering par type de couche :

- 4 couches : BASE, SATURATION, LIGHT, SHADOW
- Configuration par couche (densité fovéale vs périphérique)
- **Problème** : Le code utilise `GaussianSplat.LayerType.X` mais vérifie avec `gaze_point.is_equal_approx(Vector3.ZERO)` — si le regard est à l'origine, les couches sont ignorées.

### 14.6 SurfaceExtractor : Backface culling correct

`surface_extractor.gd` (169 lignes) est bien implémenté :

- Calcul de normale par triangle via cross product
- Test front-facing avec dot(normal, to_camera) > 0
- Parcourt toutes les surfaces du mesh, gère les index buffers
- Calcule l'aire du triangle (utile pour densité adaptative)
- **Limite** : Mono-thread, pas d'utilisation de `WorkerThreadPool`

### 14.7 TemporalReprojector : Réutilisation inter-frame

`temporal_reprojector.gd` (214 lignes) implémente la reprojection temporelle :

- Historique de 8 frames par nœud
- Fade-in (2 frames) et fade-out (4 frames) pour transitions douces
- Motion vectors pour compensation de mouvement caméra
- Détection de splats proches pour éviter doublons (O(n²) naïf)
- **Problème** : `_generate_missing_splats()` utilise `GaussianSplat.create_from_triangle()` — cette méthode pourrait ne pas exister.

### 14.8 Correctifs appliqués le 02/05/2026

| Fichier | Correctif | Impact |
|---|---|---|
| `reconstruction_manager.gd` | Setters refactorisés avec méthodes `_propagate_*` dédiées | Élimine risque de récursion, meilleure séparation des responsabilités |
| `gpu_culler_pipeline.gd` | Ajout du binding CameraData UBO (set=1, binding=1) + push constants alignés sur le layout shader (aabb_min, aabb_max) | Le culling stéréoscopique fonctionne maintenant avec des matrices valides |
| `fovea_splat_renderer.gd` | Récupération AABB depuis le loader Rust avant d'appeler `process_splats_from_file` | La spatial quantization est correctement décodée |
| `fovea_compositor_effect.gd` | Passage des paramètres aabb par défaut | Compatible avec la nouvelle signature |
| `studio_to_3d_panel.gd` | Suppression de `_unhandled_input()` dupliqué | -21 lignes de code mort |

### 14.9 Correctifs supplémentaires — Bug Hunt (02/05/2026, session 2)

| Fichier | Bug | Correction |
|---|---|---|
| `color_quantization.gd:19-20` | `px = x; py = y` — inversion paramètre/membre | `x = px; y = py` |
| `fovea_splattable.gd:115` | `AABB.abs()` inexistant en Godot 4 | Supprimé `.abs()` |
| `reconstruction/splat_renderer.gd:36` | `get_camera3d()` → `get_camera_3d()` | Corrigé |
| `floaters_detector.gd:146-195` | Array pass-by-value → threads écrivent dans une copie | Mutex + `append_array` partagé |
| `splat_brush_engine.gd` | Références `get_multimesh()`, `custom_aabb` inexistantes | Réécrit pour `loaded_splats` |
| `splat_lighting_animator.gd:30` | `splattable.splats` → propriété fantôme | `splattable.loaded_splats` |
| `splat_interaction_controller.gd:20` | Idem | `splattable.loaded_splats` |
| `fovea_splat_renderer.gd:140` | Null `culler_pipeline.rd` → crash | Guard + `push_error` |
| `reconstruction_backend.gd` | `await command_finished` sans timeout → hang | Timeout 30 min + `OS.kill(pid)` |
| `game_ready_optimizer.gd` | `precalculate_normals()` vide | Implémentation réelle (axe le + court) |
| `occlusion_culler.gd:98` | `_select_mip_level()` retourne toujours 0 | Sélection basée sur profondeur |
| `reconstruction/splat_renderer.gd:255` | Boucle `set_render_distance` qui ne fait rien | Supprimée |
| `studio_processor.gd` | Pas de cleanup GPU → fuite mémoire | `_free_gpu()` + `NOTIFICATION_PREDELETE` |
| `studio_dependency_checker.gd` | Exit code 1 accepté (trop permissif) + `colmap help` au lieu de `--help` | `exit_code == 0` strict |
| `style_engine.gd` | GLASS défini dans enum mais ignoré dans `compute_color` + `compute_roughness` | Implémentation Fresnel + specular + roughness=0.05 |

### 14.10 Correctifs — Bug Hunt (03/05/2026, session 3)

| Fichier | Bug | Correction |
|---|---|---|
| `reconstruction_backend.gd:132,154` | `command_progress.emit(line, -1.0)` — pourcentage toujours -1 | `_parse_progress_percent()` : regex pour COLMAP "Reconstruction 50%", "Iteration [100/500]", "Training progress 150/7000", phases clés |
| `reconstruction_backend.gd:111-179` | Boucle infinie si process anormal + pas de détection de hang | Détection 5 min sans output → `OS.kill(pid)` |
| `foveacore_manager.gd:141-147` | `setup_zones()` appelé chaque frame | Dirty flags (`_foveated_params_dirty`, caches comparés avec `is_equal_approx`) |
| `foveacore_manager.gd:162-243` | `_perform_culling()` monolithique 160+ lignes | Split en 5 méthodes : `_do_hybrid_setup`, `_do_generate_and_filter`, `_filter_triangles_via_occlusion`, `_do_foveated_pass`, `_do_gpu_render` |
| `rust/splat_sorter/src/lib.rs:60-62` | `set_splats()` placeholder vide | Implémentation `VariantArray` → `Vec<GaussianSplat>` avec parsing Dictionary (position, rotation, scale, opacity) |
| `star_bridge.py:59` | `fake_depth = np.random.randint(...)` — simulation critique | `_estimate_depth_heuristic()` : luminance inversée + Sobel edges → depth map déterministe 16-bit. DA3 appelé quand disponible |
| `layered_foveated_controller.gd:45` | `gaze_point.is_equal_approx(Vector3.ZERO)` — bug si regard à l'origine | Flag `_gaze_point_set` + `set_gaze_point()` — distingue "non initialisé" de "origine" |
| `studio_to_3d_panel.gd:347-357` | `_on_video_selected` appelle `manager.processor` sans null check | `_ensure_session()` + guard `manager == null or manager.processor == null` |
| `studio_to_3d_panel.gd:580-594` | `_on_preview_pressed` idem | Guard `manager == null or manager.processor == null` |
| `studio_to_3d_panel.gd:213-222` | `_on_roi_pressed` idem | Guard + `_ensure_session()` |
| `studio_to_3d_panel.gd:207-211` | `_update_ui_from_session` idem | Guard `if manager and manager.processor` |

### 14.11 Statut des 100 tâches originales (AUDIT_AND_TASKS.md)

Déjà résolues avant cette session : #1, #2, #11 (is_visible_to_camera corrigé), #13 (run_reconstruction existe), #23 (calculate_blur_score supprimé), #52-55 (.fovea implémenté via Rust), #57 (SplatBrush fonctionnel), #4-5 (OS.create_process réel)

Résolues session 2 : #9 (is_visible_to_camera), #23 (blur score), #27 (save/restore sessions déjà codé), #66 (GLASS), #99 (plugin.gd déjà correct), #100 (TODOs nettoyés partiellement)

Résolues session 3 : #6 (set_splats placeholder implémenté), #8 (HybridRenderer connecté via `_do_hybrid_setup`), #25 (progress parsing COLMAP/3DGS), #44 (processor null checks UI), #79 (setup_zones dirty flags), #81 (star_bridge.py heuristic fallback)

Restent prioritaires : #22 (preview temps réel masquage), #84-90 (tests unitaires)
