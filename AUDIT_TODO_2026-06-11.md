# 🔍 FoveaEngine — Audit & Liste de tâches (11/06/2026)

> Audit du code actuel (post-corrections de mai). Les blockers historiques (`run_reconstruction` absent, `calculate_blur_score` factice, `is_visible_to_camera` toujours `true`, backend simulé) sont **corrigés**. Ce document liste ce qui reste.

---

## 1. Constat rapide

- 141 fichiers GDScript + 23 Python + 13 C# (hors godot-cpp).
- Bonne dynamique : derniers commits = fixes parse/thread-safety/storage buffers.
- Principaux risques actuels : violations des règles de perf CLAUDE.md dans les deformers, garde null Vulkan manquante, double plugin GDScript/C# activé, ~1500 variables non typées, beaucoup de travail non commité.

---

## 2. 🔴 BUGS / CORRECTIONS (priorité haute)

- [x] **B1. Null safety Vulkan — `fovea_instanced_splat_renderer.gd:294`** ✅ *Corrigé le 11/06* : garde `instanced_culler == null or instanced_culler.rd == null` ajoutée avant `buffer_get_data()`.
- [x] **B2. Boucles `set_instance_transform()` interdites (règle Batch Processing)** ✅ *Corrigé le 11/06* : nouvel utilitaire `scripts/advanced/fovea_multimesh_bulk.gd` (`FoveaMultiMeshBulk`) — écriture bulk via `multimesh.buffer`. Appliqué à :
  - `fovea_clay_deformer.gd` (reset + `deform_multimesh`)
  - `fovea_surface_deformer.gd` (`_apply_deformation`)
  - `reconstruction/enhanced_point_cloud.gd`, `reconstruction/point_cloud_visualizer.gd`, `reconstruction/splat_renderer.gd` (load + sort)
- [x] **B3. Indentation mixte `test/benchmark_report.gd`** ✅ *Faux positif* : les espaces sont à l'intérieur de chaînes multilignes (template texte), pas de l'indentation de code. Rien à corriger.
- [x] **B4. Doublon de shaders tile rasterizer** ✅ *Corrigé le 11/06* : `tile_based_rasterizer.glsl` (orphelin, non référencé) supprimé. `tile_rasterizer.glsl` (chargé par `gpu_culler_pipeline.gd:137`) conservé.
- [x] **B5. Double plugin actif** ✅ *Corrigé le 11/06 (choix : désactiver le C#)* : `fovea_engine` retiré de `editor_plugins` dans `project.godot`. Le code C# reste dans `addons/fovea_engine/` et peut être réactivé via Paramètres du projet → Plugins. Ajouter `project.godot` au commit des corrections.
- [ ] **B6. Travail non commité massif** — ⚠️ *À faire côté Windows* : le sandbox Cowork lit des versions tronquées des fichiers modifiés (cache de montage), committer depuis celui-ci corromprait le dépôt. Commandes à exécuter localement :
  ```
  rtk git add .gitignore && rtk git rm -r --cached *.log
  rtk git commit -m "chore(repo): ignore root logs and local assets (audit D5)"
  rtk git add addons/foveacore/scripts/advanced/fovea_multimesh_bulk.gd addons/foveacore/scripts/advanced/fovea_clay_deformer.gd addons/foveacore/scripts/advanced/fovea_surface_deformer.gd addons/foveacore/scripts/advanced/fovea_instanced_splat_renderer.gd addons/foveacore/scripts/reconstruction/enhanced_point_cloud.gd addons/foveacore/scripts/reconstruction/point_cloud_visualizer.gd addons/foveacore/scripts/reconstruction/splat_renderer.gd AUDIT_TODO_2026-06-11.md
  rtk git commit -m "fix(perf): bulk MultiMesh writes + Vulkan null guard (audit B1/B2), drop orphan tile shader (B4)"
  rtk git add addons/foveacore/scripts/reconstruction/diffsynth_bridge.py addons/foveacore/scripts/reconstruction/star_bridge.py addons/foveacore/scripts/reconstruction/reconstruction_backend.gd
  rtk git commit -m "fix(reconstruction): fail loudly on stubbed backends, add --dry-run/--checkpoint (audit B8)"
  rtk git add project.godot .github/workflows/ci.yml addons/foveacore/test/run_all_tests.gd addons/foveacore/test/test_node_runner.gd addons/foveacore/test/test_compile_all_scripts.gd
  rtk git commit -m "ci: Godot 4.7-dev5 headless pipeline + disable duplicate C# plugin (audit B5/D3/D4)"
  ```
  Puis committer le reste du WIP antérieur par lots logiques. NB : si git affiche « index file corrupt », supprimer `.git/index` puis `git reset`.
- [x] **B7. `script_parse.log`** ✅ : log obsolète, désormais ignoré par `.gitignore` (cause : lancement standalone de `fovea_thread_pool.gd` via `godot -s`, usage incorrect, pas un bug du fichier).
- [x] **B8. Placeholders Python** ✅ *Corrigé le 11/06* :
  - `diffsynth_bridge.py` — AnyRecon et DVLT échouent explicitement (`exit 2`) hors `--dry-run` ; plus de fausses poses silencieuses ; bug `t_start` jamais défini dans `main()` corrigé.
  - `star_bridge.py` — `--checkpoint` requis pour DA3 (plus de poids aléatoires), `--allow-heuristic` pour le repli explicite, erreurs en `exit 1`, métadonnées marquent `depth_source` et `poses_are_placeholder`.
  - `reconstruction_backend.gd` — nouveau réglage `star_da3_checkpoint` propagé au bridge (repli heuristique + `push_warning` si vide).

## 3. 🟠 DETTE TECHNIQUE / FIABILITÉ (priorité moyenne)

- [ ] **D1. Typage strict** : ~1522 `var x = ...` non typés au départ. ✅ *Fichiers du cœur traités le 11/06 (~160 annotations, 0 restant)* : `foveacore_manager.gd`, `gpu_culler_pipeline.gd` (+ `ceili()` pour workgroups), `fovea_core_splat_renderer.gd` (+ `-> void` sur 3 signatures), `fovea_instanced_splat_renderer.gd` (+ membre `triangle_mesh_generator: GDScript`). Règles suivies : retours dynamiques (`get_shader_parameter`, `camera.attributes`) typés `Variant`, instances GDExtension (`ClassDB.instantiate`) typées `Object`, classes internes vérifiées membre par membre. ✅ *2e lot (11/06)* : subsystems (`fovea_splat_subsystem`, `fovea_foveated_subsystem`, `fovea_vr_subsystem`), `fovea_instanced_culler.gd` (39), `fovea_splat_cleaner.gd` (46), `fovea_splattable.gd` (33) — soit ~282 annotations au total, 0 restant dans le cœur du pipeline de rendu. **Reste** : ~1230 occurrences, surtout reconstruction/UI (`studio_to_3d_panel` 139, `reconstruction_manager` 81, `studio_processor` 66) et utilitaires (`mesh_simplifier` 134, `fovea_segmentation_bridge` 84, `style_engine` 72). Ajouter les fichiers typés au commit des corrections.
- [ ] **D2. 11 appels `rd.sync()`** dans les pipelines GPU → stalls CPU-GPU chaque frame. Court terme : regrouper submit/sync ; long terme : voir A3 (indirect draw).
- [x] **D3. Tests automatisés** ✅ *11/06* : l'infra existait déjà (`run_all_tests.gd` + `test_node_runner.gd` + `test_compile_all_scripts.gd`). Renforcé : `--path` explicite pour les sous-processus (robuste en CI), pas de doublon `--headless`. Commande locale : `godot --headless --path . -s res://addons/foveacore/test/run_all_tests.gd`.
- [x] **D4. CI/CD** ✅ *11/06* : `.github/workflows/ci.yml` réécrit — 6 jobs : parse GDScript (gdparse 4.x, hors godot-cpp), syntaxe Python (tous les bridges), build C# (dotnet 9), compile-check Godot 4.7-dev5 headless (le conteneur 4.6 était incompatible avec le projet 4.7), tests unitaires (informatif tant que pas de GPU sur les runners — `continue-on-error`), build Rust multi-OS. ⚠️ À vérifier au 1er run : nom de l'asset `Godot_v4.7-dev5_mono_linux_x86_64.zip` sur godot-builds, et disponibilité de `Godot.NET.Sdk/4.7.0-dev.5` sur NuGet.
- [x] **D5. Hygiène du dépôt** : déplacer/ignorer `test_run*.log`, `test_output.log`, `script_parse.log`, `import.log`, `audit_foveacore.diff`, `nemotron AUdit.txt`, `my icone/`, `Videos test/` (`.gitignore` + dossier `docs/audits/`).
- [x] **D6. Snapshot Clay Deformer en `Dictionary` non typé** (`_original_transforms[mm.get_instance_id()]`) : OK fonctionnellement (non-destructif respecté) mais stocker en `PackedFloat32Array` pour cohérence avec B2 et mémoire réduite.
- [x] **D7. Code Rust dans `shaders/`** (relevé dans l'audit du 02/05, toujours d'actualité ?) : déplacer `lib.rs`/`Cargo.toml` vers `rust/`.
- [x] **D8. `GazeTrackerLinker`** : toujours jamais testé sur matériel réel — prévoir un fallback simulation souris + flag de statut clair.

## 4. 🟡 AMÉLIORATIONS / DÉVELOPPEMENT (roadmap restante)

- [ ] **A1. Tile-Based Rasterization (16×16)** — les shaders existent (cf. B4), finir l'intégration dans `GPUCullerPipeline`/`FoveaCompositorEffect` (le flag `enable_tile_rasterizer` est déjà câblé).
- [ ] **A2. Delta-Splat Variants** — variantes légères d'objets instanciés (tints, déformations locales) stockées en delta.
- [ ] **A3. GPU-Driven Indirect Draw** — éliminer les `rd.sync()` (D2) via draw indirect buffer écrit par le compute shader.
- [ ] **A4. Out-of-Core VRAM Streaming** — chunks SSD→VRAM pour mondes ouverts (étend `fovea_streaming_manager` + chunks Morton existants).
- [ ] **A5. Séparation Static vs Dynamic Splats** — baking/octree pour le décor, compute skinning pour les entités mobiles.
- [ ] **A6. Auto-ROI par IA** — détection automatique de l'objet principal dans StudioTo3D (le pont segmentation `fovea_segmentation_bridge.gd` existe déjà : s'appuyer dessus).
- [ ] **A7. Compression Gaussienne** — format ultra-léger pour streaming VR (étendre VQ 1024 existant).
- [ ] **A8. Pont Hermes/Blender** — passerelle agents autonomes ↔ Blender/Godot (conception planifiée).
- [ ] **A9. Vraies poses caméra DVLT** (suite de B8) — exporter les poses prédites au format COLMAP/`cameras.json` exploitable par le pipeline.
- [ ] **A10. Scène de démo desktop non-VR** — faciliter le test sans casque (relevé en mai, à confirmer/créer `test/demo_desktop.tscn`).

---

## 5. Ordre d'attaque suggéré

1. **Semaine 1** : B1 → B4 (crashs et perfs), B6 (commits).
2. **Semaine 2** : B5, B7, B8, D3 + D4 (tests/CI = filet de sécurité avant la suite).
3. **Ensuite** : D1/D2 en continu, puis A1 (tile rasterizer, déjà à moitié fait) et A3.
