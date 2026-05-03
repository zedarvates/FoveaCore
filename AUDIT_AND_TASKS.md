# 🔍 FoveaEngine — Audit Complet & 100 Tâches Prioritaires

> Mis à jour le 2026-04-20 | Basé sur l'analyse exhaustive de `addons/foveacore/`

---

## 📊 RÉSUMÉ DE L'AUDIT

### Architecture Générale

| Composant | Statut | Note |
|---|---|---|
| `FoveaCoreManager` (autoload) | ✅ Solide | Pipeline bien structuré |
| `SplatRenderer` | ⚠️ Proto | ImmediateMesh → pas scalable pour 100k+ splats |
| `SplatGenerator` | ✅ Complet | Barycentric sampling propre |
| `StyleEngine` | ✅ Excellent | FBM + Worley + 5 matériaux |
| `SurfaceExtractor` | ✅ Bon | Backface culling + triangle extraction |
| `TemporalReprojector` | ✅ Bon | Cohérence temporelle OK |
| `HybridRenderer` | ⚠️ Proto | Setup OK, pas encore branché à FoveaCoreManager |
| `EyeCuller` | ✅ | Existe, référencé |
| `OcclusionCuller` | ⚠️ Stub | Le bloc Hi-Z est un `pass` — rien n'est fait |
| `SplatSorter` | ⚠️ CPU | Tri CPU sur `_current_splats` → bottleneck à 90 FPS |
| `GazeTrackerLinker` | ⚠️ Proto | Lit l'XR tracker API — mais jamais testé sur hardware |
| `FoveaXRInitializer` | ✅ Bon | Initialisation OpenXR propre |
| `ProxyFaceRenderer` | ⚠️ Partiel | Camera cherchée par nom "Camera" — fragile |
| `StudioTo3D Panel` | ⚠️ Proto | ROI = hardcodé Rect2i(100,100,800,800) |
| `ReconstructionBackend` | ❌ Simulé | `_simulate_command_execution` avec `await 3.0` |
| `StudioProcessor` | ❌ Simulé | `_simulate_extraction` avec `await 1.0` |
| `GDExtension (C++)` | ⚠️ Vide | `fovea_renderer.cpp` = shell vide, DLL compilée mais pas fonctionnelle |
| PLY Loader | ❌ ABSENT | Aucun fichier pour charger des `.ply` 3DGS |
| `.fovea` Asset Format | ❌ ABSENT | Container binaire non implémenté |
| GPU Compute Culling | ⚠️ Shader existant mais non branché | `gpu_culling.gdshader` existe mais pas de RenderingDevice code |
| `xr_action_map.tres` | ❌ Vide | Fichier de 114 bytes — actions non configurées |

---

### 🔴 Problèmes Critiques (Bloquants)

1. **~~Aucun chargeur PLY~~** — Remplacé par le chargeur binaire Fast-Path Rust (`.fovea`).
2. **Backend de reconstruction simulé** — Toutes les phases (FFmpeg, COLMAP, 3DGS) s'exécutent avec `await timer(3.0)`. Rien ne s'exécute réellement.
3. **~~GDExtension vide~~** — L'extension Rust est maintenant implémentée (`FoveaAssetLoader` + Culling pipeline).
4. **~~OcclusionCuller non branché~~** — Remplacé par le `FoveaCompositorEffect` qui injecte le Depth Buffer dans le Compute Shader.
5. **`xr_action_map.tres` non configuré** — Référencé dans `project.godot` mais quasi-vide (114 bytes).
6. **`HybridRenderer` non intégré** — Instancié dans le manager mais jamais utilisé pour rendre quoi que ce soit.

### 🟠 Problèmes Architecturaux

7. **`SplatRenderer` utilise `ImmediateMesh`** — Recréé chaque frame, pas de GPU instancing → impossible d'atteindre 90 FPS avec 100k splats.
8. **Tri des splats CPU-only** — `SplatSorter.sort_by_depth()` en GDScript, O(n log n) sur le thread principal.
9. **ProxyFaceRenderer** cherche son enfant par `get_node("Camera")` — cassera sur tout rig VR réel.
10. **ROI dans `studio_to_3d_panel.gd`** — Hardcodé à `Rect2i(100, 100, 800, 800)`. Pas d'interface de dessin visuelle.
11. **`FoveaSplattable.is_visible_to_camera()`** retourne toujours `true` — TODO non implémenté.
12. **`calculate_blur_score()`** dans `StudioProcessor` retourne toujours `1.0`.
13. **`run_reconstruction()` dans `ReconstructionManager`** n'existe pas — `_on_run_pressed()` l'appelle mais la méthode est absente.
14. **Double création de `ReconstructionManager`** — Le panel crée une instance locale ET il y a un autoload.
15. **`_exit_tree()` dans `plugin.gd`** ne retire pas `NeuralStyle` custom type (oubli).

### 🟡 Gaps de Features

16. **Pas de chargement de splats depuis fichier** — Seule la génération procédurale fonctionne.
17. **Pas de preview temps réel du masquage** — L'utilisateur ne voit pas l'effet du threshold slider.
18. **Pas de format binaire `.fovea`** — Pas de sérialisation/désérialisation des assets.
19. **ComfyUI Bridge** — Mentionné dans le roadmap mais inexistant.
20. **Splats anisotropiques** — Seulement des cercles (covariance 2D non utilisée dans le shader).

---

## ✅ 100 TÂCHES — PLAN D'ACTION COMPLET

Les tâches sont numérotées et ordonnées par priorité. Les **🔴 Critiques** débloquent le système, les **🟠 Importantes** améliorent la fiabilité, les **🟡 Normales** enrichissent les features.

---

### 🔴 CATÉGORIE 1 — BLOCKERS CRITIQUES (à faire en premier)

- [x] **1. Implémenter le chargeur Fast-Path** (`fovea_fast_path.rs`)
  > Chargeur Rust ultra-rapide implémenté en remplacement du parser PLY GDScript lent.

- [x] **2. Connecter le Fast-Path Loader au pipeline GPU**
  > `gpu_culler_pipeline.gd` et `fovea_splat_renderer.gd` connectés pour injecter directement en VRAM.

- [ ] **3. Implémenter `run_reconstruction()` dans `ReconstructionManager`**
  > La méthode est appelée par `_on_run_pressed()` mais n'existe pas. Orchestre les 3 phases.

- [ ] **4. Remplacer `_simulate_command_execution()` par `OS.create_process()`**
  > Dans `ReconstructionBackend`, remplacer le `await timer(3.0)` par un vrai appel externe. Lire stdout via `Thread`.

- [ ] **5. Remplacer `_simulate_extraction()` par un vrai appel FFmpeg**
  > Dans `StudioProcessor`, appeler `OS.create_process("ffmpeg", [...])` pour extraire les vraies frames.

- [x] **6. Implémenter le vrai `OcclusionCuller` (Hi-Z GPU)**
  > `FoveaCompositorEffect` intercepte la passe opaque et envoie la texture de profondeur au Compute Shader.

- [ ] **7. Configurer `xr_action_map.tres`**
  > Le fichier fait 114 bytes. Créer une action map complète: `grip_press`, `trigger_press`, `thumbstick_axis`, `menu_press` pour les deux mains.

- [ ] **8. Brancher `HybridRenderer` dans le pipeline de rendu**
  > Instancié dans le Manager mais jamais utilisé. Brancher `generate_splats_from_mesh()` ou `_apply_mode()` dans `_perform_culling()`.

- [ ] **9. Implémenter `FoveaSplattable.is_visible_to_camera()`**
  > Remplacer `return true` par un vrai test frustum AABB contre la caméra courante.

- [ ] **10. Corriger la double instanciation de `ReconstructionManager`**
  > `studio_to_3d_panel.gd._ready()` crée une nouvelle instance alors qu'il y a un autoload. Utiliser `/root/ReconstructionManager`.

---

### 🔴 CATÉGORIE 2 — RENDU CORE (Performance critiques)

- [x] **11. Migrer `SplatRenderer` de `ImmediateMesh` vers `MultiMesh`**
  > Implémenté via `FoveaSplatRenderer` utilisant un `MultiMeshInstance3D` couplé au Compute Shader.

- [x] **12. Implémenter le GPU Bitonic Sort dans un Compute Shader**
  > `splat_sort_compute.glsl` ajouté et orchestré par `GPUCullerPipeline`.

- [x] **13. Brancher le Culling Compute via `RenderingDevice`**
  > `gpu_culler_pipeline.gd` fonctionnel avec backface et occlusion culling.

- [ ] **14. Pré-allouer les buffers de splats**
  > Pré-allouer `_current_splats` à `max_splats_per_frame` pour éviter les resize dynamiques.

- [ ] **15. Rendre `SplatSorter.minimize_overdraw()` opérationnel**
  > Vérifier l'implémentation. Implémenter clustering spatial (grid 3D) pour fusionner splats voisins redondants.

- [ ] **16. Implémenter le shader de splat anisotropique**
  > Modifier `splat_render.gdshader` pour utiliser la covariance 2D. Remplacer `length(uv)` par ellipse matricielle.

- [ ] **17. Ajouter le LOD aux splats (MIP-Splatting basique)**
  > 3 niveaux: <2m = micro (5 splats/tri), 2-10m = normal, >10m = macro (1 splat/tri, radius x3).

- [ ] **18. Implémenter le Spatial Chunking**
  > Diviser l'espace en chunks 16³. Charger/décharger selon position caméra. Nécessaire pour grandes scènes.

- [ ] **19. Optimiser `SurfaceExtractor` avec des threads**
  > Parcours des triangles mono-thread. Utiliser `WorkerThreadPool` pour paralléliser par surface de mesh.

- [ ] **20. Frustum Culling côté CPU avant le GPU**
  > Test AABB rapide en GDScript avant d'envoyer au `_eye_culler`. Réduire les nodes passés au culling fin.

---

### 🟠 CATÉGORIE 3 — PIPELINE STUDIOTO3D

- [ ] **21. Implémenter l'interface ROI visuelle**
  > Ajouter `TextureRect` dans le panel pour afficher la première frame. Dessiner rectangle avec souris → `session.roi_rect`.

- [ ] **22. Ajouter le preview temps réel du masquage**
  > Quand le slider change, extraire une frame, appliquer `mask_background()`, afficher le résultat dans un preview.

- [ ] **23. Implémenter la vraie détection de flou (`calculate_blur_score()`)**
  > Remplacer `return 1.0` par variance Laplacienne (kernel 3x3). Filtrer les frames floues avant export COLMAP.

- [ ] **24. Détecter FFmpeg/COLMAP et afficher les chemins manquants**
  > Au démarrage du panel, `OS.execute("ffmpeg --version")`. Afficher erreur + lien download si absent.

- [ ] **25. Implémenter la gestion des erreurs du backend**
  > `error_occurred` n'est pas connecté. Brancher dans `ReconstructionManager` et afficher dans `log_text`.

- [ ] **26. Ajouter une barre de progression par phase**
  > 3 segments visuels: Phase 1 (0-33%), Phase 2 (33-66%), Phase 3 (66-100%) avec labels.

- [ ] **27. Sauvegarder et restaurer les sessions**
  > Sérialiser `ReconstructionSession` en JSON. Sauvegarder auto dans `reconstructions/<name>/session.json`.

- [ ] **28. Implémenter le reset complet de session**
  > `_on_reset_pressed()` réinitialise l'UI mais pas `active_sessions`. Vrai cleanup: fichiers temp + mémoire.

- [ ] **29. Ajouter le support des vidéos MKV et WebM**
  > Ajouter mkv, webm, gif au filtre `FileDialog`.

- [ ] **30. Implémenter l'export COLMAP complet**
  > Vérifier que `DatasetExporter` génère `images/` + `masks/` + `database.db` + `cameras.txt` correctement.

- [ ] **31. Intégrer le mode COLMAP "exhaustive matching"**
  > Option UI: "exhaustive_matcher" (précis) vs "sequential_matcher" (rapide vidéos).

- [ ] **32. Implémenter la lecture asynchrone de stdout COLMAP**
  > COLMAP affiche sa progression. Lire ce stream via `Thread` pour mettre à jour la progress bar.

- [ ] **33. Ajouter un mode "Dry Run" pour test sans exécution réelle**
  > Logger les paramètres qui seraient envoyés sans vraiment appeler COLMAP.

- [ ] **34. Implémenter l'ouverture du dossier de résultats**
  > Bouton "Ouvrir dossier" → `OS.shell_open(output_directory)` après reconstruction.

---

### 🟠 CATÉGORIE 4 — VR / EYE TRACKING

- [ ] **35. Tester `FoveaXRInitializer` sur hardware réel**
  > Valider sur Quest Pro ou Vision Pro. Documenter les erreurs, ajuster les fallbacks.

- [ ] **36. Implémenter le fallback desktop (sans casque)**
  > Si OpenXR absent: caméra orbitale. `FoveaCoreManager` détecte et adapte le rendu.

- [ ] **37. Brancher le ray casting dans `GazeTrackerLinker`**
  > `_calculate_gaze_world_hit()` projette `gaze_vec * 100.0`. Utiliser `PhysicsDirectSpaceState3D.intersect_ray()`.

- [ ] **38. Implémenter l'eye tracking OpenXR extension Meta**
  > Support de `XR_EXT_eye_gaze_interaction` pour Quest Pro. Activer extension + permissions Android.

- [ ] **39. Ajouter le support eye tracking Apple Vision Pro**
  > Via ARKit ou runtime OpenXR d'Apple. Path de code distinct de Meta.

- [ ] **40. Implémenter le VRS (Variable Rate Shading) hardware**
  > Relier `_apply_foveation_settings()` à la texture VRS de Godot 4.6.

- [ ] **41. Tester et fixer la scène `fovea_vr_rig.tscn`**
  > Vérifier que tous les nœuds existent: `XRCamera3D`, deux `XRController3D`.

- [ ] **42. Implémenter les contrôleurs VR dans `splat_brush_playground.tscn`**
  > Input physique pour `SplatBrush` avec manettes VR.

- [ ] **43. Implémenter la vibration haptique lors du SplatBrush**
  > `XRController3D.trigger_haptic_pulse()` quand brush touche un splat.

- [ ] **44. Corriger `ProxyFaceRenderer` pour chercher la caméra correctement**
  > Remplacer `get_node_or_null("Camera")` par `get_viewport().get_camera_3d()`.

---

### 🟠 CATÉGORIE 5 — GDEXTENSION / C++ / RUST

- [x] **45. Implémenter le Bitonic Sort sur GPU**
  > Déplacé intégralement sur Compute Shader plutôt qu'en C++ pour éviter les transferts CPU/GPU.

- [x] **46. Implémenter le Fast-Path Binaire en Rust**
  > Lecture de `.fovea` via struct alignée 16 octets (`fovea_fast_path.rs`).

- [x] **47. Exposer l'AssetLoader via GDExtension Rust**
  > Classe `FoveaAssetLoader` correctement déclarée et compilée avec Cargo.

- [x] **48. Mettre en place la structure Rust GDExtension**
  > Cargo.toml configuré avec la dépendance `godot-rust/gdext`.

- [x] **49. Migrer le tri vers le GPU**
  > Remplacé par `splat_sort_compute.glsl`.

- [ ] **50. Migrer `SurfaceExtractor.gd` vers Rust avec SIMD**
  > Parcours de triangles embarrassingly parallel. `extract_visible_triangles_native()`.

- [ ] **51. Créer un CI/CD pour compiler la GDExtension**
  > GitHub Actions: `foveacore.dll` (Windows), `libfoveacore.so` (Linux), `libfoveacore.dylib` (macOS).

---

### 🟡 CATÉGORIE 6 — FORMAT ASSET `.fovea`

- [ ] **52. Définir le format binaire `.fovea`**
  > Spécifier: magic bytes, version, sections (mesh, splats, style, metadata). Doc dans `plans/fovea_format_spec.md`.

- [ ] **53. Implémenter le sérialiseur `.fovea`**
  > `fovea_asset_writer.gd`: Mesh + Array[GaussianSplat] + FoveaStyle → fichier binaire.

- [ ] **54. Implémenter le désérialiseur `.fovea`**
  > `fovea_asset_loader.gd`: reconstruit les données depuis le fichier. Enregistrer via `ResourceFormatLoader`.

- [ ] **55. Enregistrer `.fovea` comme ResourceFormatLoader dans Godot**
  > `plugin.gd`: `ResourceLoader.add_resource_format_loader()` pour que Godot reconnaisse les `.fovea`.

---

### 🟡 CATÉGORIE 7 — FEATURES ARTISTIQUES

- [ ] **56. Finaliser les Splat Layers (BASE/SATURATION/LIGHT/SHADOW)**
  > `LayerType` est défini mais non utilisé dans le rendu. Implémenter un render pass par layer.

- [ ] **57. Implémenter le SplatBrush interactif fonctionnel**
  > Détection collision splats (octree), modification couleur/opacité/rayon, undo/redo stack.

- [ ] **58. Implémenter `TexturedSplatGenerator` réel**
  > Charger textures Sponge/DryBrush/Stipple, assigner aux splats, UV mapping sur les quads.

- [ ] **59. Finaliser les Soft Matter (liquides style Manga)**
  > Simulation: forces externes → intégration velocity → update position. Max 1000 splats déformables.

- [ ] **60. Implémenter `SplatLightingAnimator` réel**
  > Détecter `DirectionalLight3D`, calculer direction d'ombre, déplacer splats SHADOW chaque frame.

- [ ] **61. Implémenter les reflets speculaires dynamiques**
  > Passer `light_direction` au shader. Calculer `specular_intensity` par splat selon angle vue-lumière.

- [ ] **62. Implémenter `HierarchicalSplatGenerator` complet**
  > 3 LOD: LOD0 (near, micro), LOD1 (mid, standard), LOD2 (far, macro) par distance.

- [ ] **63. Créer le Splat Decal Tool (weathering)**
  > `splat_decal.gd`: spray rouille/mousse/neige sur surfaces. `RayCast3D` + pattern procedural.

- [ ] **64. Implémenter le shader aquarelle**
  > `artistic_watercolor.gdshader`: edge darkening, granulation, wet-in-wet. Pour layer SATURATION.

- [ ] **65. Implémenter le shader Hatching (hachures)**
  > `artistic_hatching.gdshader`: UV triplanaire + texture hachures. Orienter selon normale de surface.

- [ ] **66. Ajouter le support GLASS dans `StyleEngine`**
  > `MaterialType.GLASS` dans l'enum mais ignoré. Implémenter `_compute_glass_color()` avec fake refraction.

---

### 🟡 CATÉGORIE 8 — INTELLIGENCE ARTIFICIELLE

- [ ] **67. Créer le ComfyUI Bridge basique**
  > `neural_style_bridge.gd`: HTTP vers ComfyUI (port 8188), envoi workflow JSON, polling résultat.

- [ ] **68. Implémenter l'Auto-ROI par IA**
  > Modèle SAM2/rembg pour détection objet principal et génération `roi_rect`. Appel via Python.

- [ ] **69. Créer le script Python `auto_roi.py`**
  > Script dans `tools/` utilisant `rembg`. Retourne bbox de l'objet. Appelé par le Bridge.

- [ ] **70. Intégrer ONNX Runtime pour inférence locale**
  > Packager un modèle ONNX léger (MobileNet-SAM). Segmentation hors-ligne dans StudioTo3D.

---

### 🟡 CATÉGORIE 9 — MULTIPLAYER / SYNC

- [ ] **71. Concevoir le protocole de sync des splats**
  > `plans/multiplayer_sync_spec.md`: delta encoding, batching, priorité zones fovéales.

- [ ] **72. Implémenter `network_interpolator.gd` complet**
  > Vérifier et brancher au Manager pour interpoler positions splats reçus via réseau.

- [ ] **73. Implémenter la sync des interactions SplatBrush**
  > Diffuser modifications splats à tous les pairs via `MultiplayerSynchronizer`.

---

### 🟡 CATÉGORIE 10 — TOOLING & UX ÉDITEUR

- [ ] **74. Créer un panneau de statistiques en temps réel**
  > Plugin panel `FoveaStats`: FPS, nb splats, temps extraction, mémoire GPU, ratio reprojection.

- [ ] **75. Ajouter des gizmos 3D pour les FoveaSplattable nodes**
  > Gizmo: bounding box du mesh, densité de splats (gradient), priorité de culling.

- [ ] **76. Créer un wizard de configuration initiale**
  > À la première activation: détecter FFmpeg/COLMAP, configurer chemins, proposer téléchargements.

- [ ] **77. Implémenter le drag-and-drop de fichiers `.ply`**
  > Glisser un `.ply` dans la scène → créer automatiquement un `FoveaSplattable` avec splats chargés.

- [ ] **78. Créer le menu contextuel pour les FoveaSplattable**
  > Clic droit → "Generate Splats Now", "Export to .fovea", "Preview Masking", "Open in StudioTo3D".

- [ ] **79. Implémenter l'undo/redo pour le SplatBrush**
  > Utiliser `UndoRedo` de Godot pour maintenir stack de modifications du painting.

- [ ] **80. Créer un inspector custom pour `FoveaStyle`**
  > Preview live du matériau procédural (sphere preview) quand les params `MaterialStyleConfig` changent.

- [ ] **81. Ajouter des presets de style dans le panneau**
  > Dropdown: Photorealistic, Ghibli, Digital Painting, Oil Paint, Sketch. Configure `StyleEngine` auto.

- [ ] **82. Créer un outil de benchmark intégré**
  > `tools/benchmark.gd`: mesure FPS à 1k/10k/100k splats, génère rapport JSON.

- [ ] **83. Améliorer les logs du panneau StudioTo3D**
  > Colorer les logs: ✅ succès, ❌ erreur, ⚠️ warning. Bouton "Copier logs" et "Exporter .txt".

---

### 🟡 CATÉGORIE 11 — TESTS & VALIDATION

- [ ] **84. Créer des tests unitaires pour `StyleEngine`**
  > `addons/foveacore/test/`: vérifier couleurs dans [0,1], convergence FBM, Worley ∈ [0, √3].

- [ ] **85. Créer des tests unitaires pour `SurfaceExtractor`**
  > Meshes primitifs: cube (12 triangles), vérifier backface culling élimine les bonnes faces.

- [ ] **86. Créer des tests unitaires pour `TemporalReprojector`**
  > Tester: fade-in/fade-out, invalidation sur mouvement, cleanup après `max_history_frames`.

- [ ] **87. Créer une scène de test non-VR complète**
  > `test_desktop.tscn`: caméra orbitale, `FoveaSplattable` variés (cube/sphère/suzanne). Pas de casque requis.

- [ ] **88. Créer un test de performance automatisé**
  > Génère N `FoveaSplattable` avec M triangles, mesure temps frame sur 1000 frames, log JSON.

- [ ] **89. Valider le pipeline StudioTo3D sur un vrai asset**
  > Vrai turntable → FFmpeg → COLMAP → 3DGS. Documenter dans `tutorials/`.

- [ ] **90. Créer des tests d'intégration pour le plugin**
  > Vérifier activation/désactivation OK, autoloads créés/détruits, custom types disponibles.

---

### 🟡 CATÉGORIE 12 — DOCUMENTATION

- [ ] **91. Écrire la spécification du format PLY attendu**
  > `plans/ply_format_spec.md`: `x y z`, `f_dc_0/1/2`, `opacity`, `scale_0/1/2`, `rot_0/1/2/3`.

- [ ] **92. Créer le guide de configuration COLMAP**
  > `tutorials/colmap_setup.md`: download, install, PATH, première reconstruction.

- [ ] **93. Créer le guide de configuration 3DGS Training**
  > `tutorials/3dgs_training.md`: Python, `gaussian-splatting` repo, CUDA, training depuis COLMAP.

- [ ] **94. Documenter tous les signaux et l'API publique**
  > Docstrings complètes: `FoveaCoreManager` API, `ReconstructionManager` signals, `FoveaSplattable` events.

- [ ] **95. Mettre à jour le README avec l'état réel**
  > Phase 1-4 marquées ✅ mais incomplètes. Être honnête sur proto vs production.

- [ ] **96. Créer un CONTRIBUTING.md**
  > Conventions: GDScript snake_case, classes PascalCase, PR guide, compilation GDExtension.

- [ ] **97. Créer des vidéos tutoriels ou GIFs**
  > GIF: StudioTo3D en action, SplatBrush VR, toggle foveated rendering.

- [ ] **98. Écrire `plans/architecture_overview.md`**
  > Diagramme complet: Video → StudioProcessor → DatasetExporter → COLMAP → 3DGS → PLY → FoveaSplattable → SurfaceExtractor → SplatGenerator → FoveatedController → SplatSorter → SplatRenderer.

---

### 🟡 CATÉGORIE 13 — HOUSEKEEPING

- [ ] **99. Corriger `plugin.gd._exit_tree()`: ajouter `remove_custom_type("NeuralStyle")`**
  > Type custom ajouté dans `_enter_tree()` mais jamais retiré. Warning Godot à chaque rechargement.

- [ ] **100. Nettoyer les TODO restants dans le code**
  > Audit des `# TODO`, `# FIXME`, `# placeholder`. Implémenter ou tracker:
  > - `fovea_splattable.gd:58` → `is_visible_to_camera()`
  > - `test_foveacore.gd:106` → `_set_style()` appelle vraiment le StyleEngine
  > - `reconstruction_backend.gd:47` → vrai `OS.create_process()`
  > - `studio_processor.gd:65` → vrai FFmpeg call
  > - `foveacore_manager.gd:170` → Hi-Z occlusion
  > - `hybrid_renderer.gd:146` → couleur par défaut → StyleEngine

---

## 🗺️ ORDRE DE PRIORITÉ RECOMMANDÉ

| Sprint | Tâches | Objectif |
|---|---|---|
| Sprint 1 | #1-10, #99, #100 | Débloquer le système — rien ne fonctionne vraiment sans ça |
| Sprint 2 | #11-20, #44 | Rendu Core — atteindre 90 FPS avec vrais splats |
| Sprint 3 | #21-34 | StudioTo3D — pipeline vidéo→3D fonctionnel |
| Sprint 4 | #35-43 | VR/XR — validation hardware complète |
| Sprint 5 | #45-51 | GDExtension — performance native |
| Sprint 6 | #52-73 | Features artistiques + IA + fovea format |
| Sprint 7 | #74-98 | Polish, outils, docs, tests |

---

## 💡 DÉDUCTION — CE QU'ON A OUBLIÉ DE FAIRE

Voici les **oublis structurels** qui empêchent le système de fonctionner de bout en bout :

| # | Oubli | Impact |
|---|---|---|
| 🔴 | **Aucun lecteur PLY** | Sans ça, impossible de charger de vrais Gaussian Splats. Tout le rendu tourne sur du procédural depuis les meshes Godot. |
| 🔴 | **Backend FFmpeg/COLMAP non branché** | L'UI StudioTo3D "fonctionne" mais ne fait rien de réel. La boucle vidéo→3D est brisée. |
| 🟠 | **`run_reconstruction()` manquante** | La méthode appelée par "Run" n'existe pas. |
| 🟠 | **Systèmes non câblés entre eux** | `HybridRenderer`, `OcclusionCuller`, `ProxyFaceRenderer` sont instanciés mais jamais utilisés dans le pipeline réel. |
| 🟠 | **Eye tracking jamais testé** | Le code est correct (XR tracker API), mais sans hardware, on ne sait pas si ça fonctionne. |
| 🟡 | **Aucune scène de test sans VR** | Impossible de tester le moteur sans casque XR. Une scène desktop est indispensable au quotidien. |
| 🟡 | **Pas de données de test incluses** | Aucun `.ply` de démo. Les nouveaux contributeurs ne peuvent tester absolument rien. |

---

*"Un moteur de rendu, c'est comme un moteur de voiture : tous les composants peuvent exister, mais si les câbles ne sont pas branchés, il ne démarre pas."*
