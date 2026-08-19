# 🎯 FoveaEngine — Top Tâches À Faire (2026-07-03)

> Fichier maître de suivi, **plafonné à 300 tâches**. Liste volontairement **non
> gonflée** : ~100 tâches réelles et actionnables, déduplicées à partir de
> `AUDIT_AND_TASKS.md`, `ROADMAP.md`, `AUDIT_TODO_2026-06-11.md` et
> `ROADMAP_COMPLETE_BACKLOG.md` (300 items, dont 245 déjà ✅), plus le travail
> Phase 7 "Splats Animés" de la session en cours. Seules les tâches **encore
> ouvertes** figurent ici — pas de doublons avec ce qui est déjà `[x]` ailleurs.
> Inventer des tâches fictives pour atteindre 300 aurait rendu ce fichier
> inutile ; mieux vaut une liste courte et vraie qu'une liste longue et fausse.

**Légende de priorité** : 🔴 P0 (bloquant/vérification immédiate) · 🟠 P1 (dette
technique) · 🟡 P2 (Phase 7 en cours) · 🔵 P3 (backlog R&D avancé) · 🟣 P4
(publication) · ⚪ P5 (doc/marketing).

---

## 🔴 P0 — Vérification immédiate (avant tout merge/commit)

- [x] 1. Lancer les 8 scripts de test Phase 7 dans Godot :
      `godot --script res://addons/foveacore/test/test_animation_subsystem.gd`,
      `test_flow_field_animator.gd`, `test_morph_covariance_animator.gd`,
      `test_material_oscillation.gd`, `test_lod_stretch_animator.gd`,
      `test_flipbook_animator.gd`, `test_neural_offset_field.gd`,
      `test_bone_skin_animation.gd`.
- [x] 2. Vérifier la compilation de `splat_render_triangle.gdshader` après l'ajout
      de la branche `LAYER_ANIM` (layer_type == 7u) — jamais compilé dans cet environnement.
- [x] 3. Valider dans l'éditeur les hypothèses d'API `Skeleton3D` utilisées par
      `fovea_bone_skin_animator.gd`/`test_bone_skin_animation.gd`
      (`set_bone_rest`, `reset_bone_pose`, `set_bone_pose_position`,
      `get_bone_global_pose`, `force_update_all_bone_transforms`) — risque le
      plus élevé de tout le batch Phase 7, jamais exécuté contre un vrai Godot.
- [x] 4. Committer les fichiers de la session en cours (nouveaux animateurs
      Phase 7, modifs `foveacore_manager.gd`/`fovea_splat_subsystem.gd`/
      `gaussian_splat.gd`/`style_engine.gd`, shader, docs) en commits logiques
      groupés par sous-phase.
- [x] 5. Ouvrir `test/demo_desktop.tscn` et vérifier l'absence de régression
      visuelle sur le rendu de base après les changements Phase 7.
- [x] 6. Vérifier que `git status` ne contient plus de travail non commité
      résiduel d'avant cette session (suite à B6 de `AUDIT_TODO_2026-06-11.md`).

---

## 🟠 P1 — Dette technique restante (`AUDIT_TODO_2026-06-11.md`)

- [ ] 7. **D1 — Typage strict** : ~1230 variables encore non typées (`var x = ...`)
      hors du cœur du pipeline de rendu déjà traité. Continuer fichier par
      fichier en respectant la règle CLAUDE.md "Strictly Typed GDScript".
- [x] 8. Auditer les nouveaux animateurs Phase 7 pour confirmer qu'ils respectent
      déjà cette règle (typage complet) avant qu'ils ne s'ajoutent à la dette.

---

## 🟡 P2 — Phase 7 "Splats Animés" : travail restant

*(Détail complet et justification technique dans*
*`docs/RD_SPLATS_ANIMES_ROADMAP.md`.)*

### 7.1 Flow-Driven Animation
- [x] 9. Preset `CURRENT` : rasteriser les strokes de `splat_brush_engine.gd`
      dans une texture 3D de flux échantillonnable (outil auteur, pas juste un modifier).
- [x] 10. Portage GPU compute (`splat_animate.glsl`, mode `ANIM_FLOW`) pour le
      chemin `FoveaInstancedSplatRenderer` (budget VR 1M splats / 0,5 ms).
- [ ] 11. Démo scène forêt/rideau + GIF pour le README et la boutique Godot.

### 7.2 Morph Covariance Animation
- [ ] 12. Preset `MORPH` : outil SplatBrush "Covariance Target" (sculpter l'état
      cible Σ_target via le clay deformer existant).
- [ ] 13. Portage GPU : interpolation `Σ_t = slerp_covariance(...)` via le
      codebook `covar_texture` (deux entrées Σ_base/Σ_target + phase, +16 bits/splat).
- [ ] 14. Démo créature/blob organique + article technique
      *"Morph Covariance Animation: Animating the Gaussians Themselves"*.

### 7.3 LAYER_ANIM & Flipbook Temporel
- [x] 15. Extension `fovea_asset_loader.gd` : importer un dossier `.ply`/`.fovea`
      en tant que flipbook (peupler `flipbook_frame`/`flipbook_frame_count` au chargement).
- [ ] 16. Pont StudioTo3D : séquence vidéo reconstruite (pipeline STAR/WorldMirror)
      → flipbook automatique.
- [ ] 17. Portage GPU : sélection de frame active dans `gpu_culling_compute.glsl`
      via uniform `anim_time`/`fps` (éviter la lecture CPU du buffer).
- [ ] 18. Démo flamme stylisée + sort magique en VR.

### 7.4 Material Oscillation & LOD Stretch
- [x] 19. Exposer des presets nommés en éditeur ("Living Watercolor",
      "Pulsing Metal", "Breathing Wood") comme valeurs par défaut de `MaterialStyleConfig`.
- [ ] 20. Animation fovéatée : injecter une référence caméra dans
      `FoveaAnimationSubsystem.apply()` (ou déplacer ces animateurs vers le GPU)
      pour pouvoir couper l'animation hors zone de regard.
- [x] 21. Brancher `FoveaLodStretchAnimator` dans la logique existante de
      `fovea_hybrid_lod_controller.gd` plutôt qu'en animateur indépendant.

### 7.5 Neural Offset Field
- [ ] 22. Pipeline de baking effectif : `neural_style_bridge.gd`/ComfyUI →
      export d'un `FoveaNeuralOffsetField.tres` (aujourd'hui le champ doit être
      peuplé manuellement).
- [ ] 23. Distillation du mouvement via le cache temporel causal STAR (pipeline
      offline Python).
- [ ] 24. Runtime MLP (hash-grid + petit réseau évalué en compute shader) —
      stretch goal explicitement reporté.
- [ ] 25. Portage GPU de l'échantillonnage bake-lookup (texture 3D GPU native
      au lieu de `PackedVector3Array` + trilinéaire GDScript).

### 7.6 Bone-Driven Splat Animation
- [ ] 26. Pipeline auteur : import GLB riggé → splat → binding automatique via
      `FoveaSplatSkinBinder.bind_splats()` → lecture via `AnimationPlayer` standard.
- [ ] 27. Hybride mesh riggé LOD proche / splats riggés LOD loin (extension du hybrid renderer).
- [ ] 28. Portage GPU du solveur cloth (`fovea_splat_cloth.gd`) pour les vêtements du personnage.
- [ ] 29. Portage GPU du skinning lui-même (opération la plus coûteuse de toute
      la Phase 7 en CPU : 4 lookups de bone pose + 2 multiplications de transform par splat).
- [ ] 30. Démo créature riggée animée, sculptable au SplatBrush VR pendant l'animation.

---

## 🔵 P3 — Backlog R&D avancé restant (55 tâches, réf. `ROADMAP_COMPLETE_BACKLOG.md`)

*(Numérotation `[BL-###]` = référence à l'item original dans*
*`ROADMAP_COMPLETE_BACKLOG.md` pour traçabilité ; 245/300 items de ce fichier*
*sont déjà `[x]`, seuls les 55 restants sont repris ici.)*

### Portage mobile & Web
- [ ] 31. [BL-226] Compatibilité Vulkan Mobile : adapter les compute shaders aux limitations ARM.
- [ ] 32. [BL-227] Optimisations Meta Quest 3 : préréglages graphiques pour 90 Hz stables.
- [ ] 33. [BL-228] Compilation WebAssembly : chaîne de compilation Rust vers WASM.
- [ ] 34. [BL-229] Portage WGSL (WebGPU) : réécrire les shaders GLSL de tri/rendu.
- [ ] 35. [BL-230] Optimisation d'autonomie énergétique mobile (désactiver le tri sur objets statiques stables).

### Tile-Based Rasterization (affinage — le cœur est déjà intégré, cf. A1)
- [ ] 36. [BL-238] Tri local par tuile en mémoire partagée GPU (shared memory).
- [ ] 37. [BL-239] Gestion des listes de collision par tuile via tampon chaîné.
- [ ] 38. [BL-242] Analyse comparative MultiMesh vs rastérisation par tuile (fillrate).

### Delta-Splat Variants (Morphs & Overrides)
- [ ] 39. [BL-243] Structure de données delta (position/couleur/normales).
- [ ] 40. [BL-244] Compute shader d'animation delta (morphing localisé sur instances visibles).
- [ ] 41. [BL-245] `FoveaDeltaManager` : overrides d'instances en tampons condensés.
- [ ] 42. [BL-246] Interpolation temporelle du coefficient d'application du delta.
- [ ] 43. [BL-247] Compression FP16 des deltas pour limiter la bande passante VRAM.
- [ ] 44. [BL-248] Outil de peinture delta dans l'inspecteur.

### GPU-Driven Indirect Draw (affinage — le cœur est déjà intégré, cf. A3)
- [ ] 45. [BL-252] Gestion multi-assets indirecte (multi-draw en un seul appel).
- [ ] 46. [BL-253] Culling d'instance avancé déplacé du CPU vers le GPU.
- [ ] 47. [BL-254] Gestion de barrière mémoire (transitions de buffers GPU).
- [ ] 48. [BL-255] Test de saccade : valider l'élimination des micro-gels périodiques.

### Out-of-Core VRAM Streaming
- [ ] 49. [BL-256] Format de chunk Morton pour les gros fichiers `.fovea`.
- [ ] 50. [BL-257] E/S asynchrone (DirectStorage-style) en Rust, fichier → buffer GPU.
- [ ] 51. [BL-258] Allocateur de segments mémoire VRAM pour chunks dynamiques.
- [ ] 52. [BL-259] Priorisation par distance et cône de vue pour le chargement des chunks.
- [ ] 53. [BL-260] Fade-in d'opacité pour les chunks qui se chargent en cours de vue.
- [ ] 54. [BL-261] LOD global basse résolution toujours en mémoire (retard de streaming).
- [ ] 55. [BL-262] Régulateur de débit pour éviter de saturer le bus PCIe.

### Séparation Static vs Dynamic Splats
- [ ] 56. [BL-263] Propriété statique/dynamique sur `FoveaSplatNode`.
- [ ] 57. [BL-264] Baking d'octree statique immuable en VRAM.
- [ ] 58. [BL-265] Compute shader de skinning dynamique pour entités mobiles
      (à mutualiser avec le portage GPU de la Phase 7.6, item 29).
- [ ] 59. [BL-266] Ne retrier les splats statiques qu'en cas de mouvement caméra majeur.
- [ ] 60. [BL-267] Buffers GPU séparés (statique lecture-seule / dynamique réécrit chaque image).
- [ ] 61. [BL-268] Connecter le Verlet Solver/forces physiques aux entités dynamiques uniquement.
- [ ] 62. [BL-269] Profils de performance : proportion max de splats dynamiques simultanés.

### Auto-ROI par IA
- [ ] 63. [BL-270] Charger un modèle de segmentation local (Segment Anything/MobileSAM) en ONNX.
- [ ] 64. [BL-271] Détection automatique de l'objet central pour centrer la bounding box.
- [ ] 65. [BL-272] Génération de masques ROI binaires sans intervention manuelle.
- [ ] 66. [BL-274] Cas multi-sujets : point d'intérêt cliquable pour guider l'IA.
- [ ] 67. [BL-275] Évaluation de netteté assistée par IA pour cibler la ROI.

### Compression Gaussienne
- [ ] 68. [BL-276] Affiner l'algorithme de quantification vectorielle (K-Means++ affiné).
- [ ] 69. [BL-277] Encodage de position progressif (différentiel par octree).
- [ ] 70. [BL-278] Compression logarithmique des opacités (4 bits au lieu de 8).
- [ ] 71. [BL-279] Format `.foveaz` ultra-compressé (ZStandard).
- [ ] 72. [BL-280] Décompression GPU native via compute shader.
- [ ] 73. [BL-281] Prototype de streaming VR réseau de trames compressées.
- [ ] 74. [BL-282] Mesure de perte PSNR (> 30 dB vs PLY d'origine).

### Pont Hermes/Blender (agents autonomes)
- [ ] 75. [BL-283] Serveur WebSocket léger en Godot pour écouter l'agent IA.
- [ ] 76. [BL-284] Protocole JSON de requêtes d'assets (générer/éditer en temps réel).
- [ ] 77. [BL-285] Addon Blender Python pour synchroniser caméras/scènes avec Godot.
- [ ] 78. [BL-286] Génération automatique déclenchée (capture Godot → Blender → retour `.fovea`).
- [ ] 79. [BL-287] Orchestration complète d'une scène Godot par l'agent IA (test).
- [ ] 80. [BL-288] Documentation technique de la passerelle Hermes-Blender-Godot.

### Vraies poses caméra DVLT
- [ ] 81. [BL-289] Exporter les poses prédites au format extrinsèques/intrinsèques COLMAP.
- [ ] 82. [BL-290] Produire le fichier `cameras.json` pour compatibilité 3DGS.
- [ ] 83. [BL-292] Outil de visualisation des pyramides de caméras reconstruites dans le viewport.
- [ ] 84. [BL-293] Alignement spatial automatique (up-vector) caméra reconstruite ↔ sol de la scène.
- [ ] 85. [BL-294] Rapport d'erreur de pose (erreur moyenne de projection).

---

## 🟣 P4 — Publication Godot Asset Library

*(Suite de la discussion R&D de cette session — `ASSET_LIBRARY.md` existe déjà*
*mais la publication elle-même n'a pas été faite.)*

- [ ] 86. Rédiger la description courte officielle pour la fiche boutique.
- [ ] 87. Rédiger une version condensée du README (~10 lignes) dédiée à la boutique.
- [ ] 88. Produire un logo carré 512×512 PNG à partir de `icon.svg`.
- [ ] 89. Prendre un screenshot du rendu splatting.
- [ ] 90. Prendre un screenshot du panel StudioTo3D.
- [ ] 91. Enregistrer un GIF du SplatBrush en VR.
- [ ] 92. Définir version (`0.2.1-alpha` ou suivante), licence, catégories
      (Rendering/Tools/VR/Import), compatibilité Godot 4.6+.
- [ ] 93. Ajouter le tag "Early Access / Experimental".
- [ ] 94. Soumettre la publication sur la Godot Asset Library.
- [ ] 95. Rédiger le texte d'annonce Reddit/Discord Godot.

---

## ⚪ P5 — Documentation & différenciation marketing

- [ ] 96. Mettre à jour le README principal avec une section "Animated Splats"
      présentant les 7 sous-phases (une fois vérifiées en P0).
- [ ] 97. Produire les vidéos/GIFs de démonstration listés dans chaque sous-phase
      Phase 7 (7.1, 7.2, 7.3, 7.6) pour la boutique et les réseaux sociaux.
- [ ] 98. Publier l'article technique Morph Covariance (item 14) sur un blog/Reddit
      une fois le portage GPU (item 13) réalisé — c'est l'argument de vente n°1.

---

## Résumé

| Priorité | Nombre de tâches | Portée |
|---|---|---|
| 🔴 P0 | 6 | Vérification avant merge (session en cours) |
| 🟠 P1 | 2 | Dette technique (typage) |
| 🟡 P2 | 22 | Phase 7 Splats Animés — travail restant |
| 🔵 P3 | 55 | Backlog R&D avancé (mobile, streaming, compression, IA, Hermes, DVLT) |
| 🟣 P4 | 10 | Publication Godot Asset Library |
| ⚪ P5 | 3 | Documentation & marketing |
| **Total** | **98** | sur un plafond de 300 |
