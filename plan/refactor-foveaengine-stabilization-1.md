---
goal: Stabiliser FoveaEngine et supprimer les défauts bloquants, silencieux et structurels
version: 1.0
date_created: 2026-07-14
last_updated: 2026-07-14
owner: FoveaEngine maintainers
status: 'Planned'
tags: [refactor, stabilization, bug, godot, gdscript, gpu, xr, reconstruction]
---

# Introduction

![Status: Planned](https://img.shields.io/badge/status-Planned-blue)

Ce plan restaure d'abord un projet chargeable et des contrôles fiables, consolide ensuite les sous-systèmes du moteur, puis traite les chemins incomplets, la performance CPU/GPU/XR et la dette structurelle. Chaque phase possède des critères de sortie mesurables. Aucun lot fonctionnel ne doit commencer tant que la phase précédente ne passe pas.

## 1. Requirements & Constraints

- **REQ-001**: Le projet doit charger avec Godot 4.7.dev5 Mono ou une version 4.7 ultérieure sans `SCRIPT ERROR`, collision de `class_name` ni ressource `res://` manquante.
- **REQ-002**: Tous les scripts GDScript modifiés doivent déclarer les types des variables, arguments et valeurs de retour.
- **REQ-003**: Les opérations lourdes ne doivent pas bloquer `_ready()`; utiliser `call_deferred()`, un worker ou un thread borné.
- **REQ-004**: Les chemins GPU doivent vérifier le sous-système de rendu et `RenderingDevice` avant toute lecture ou allocation.
- **REQ-005**: Les mises à jour de `MultiMesh` doivent utiliser les tableaux groupés et ne jamais appeler `set_instance_transform()` ou `set_instance_custom_data()` dans une boucle de splats.
- **REQ-006**: Les backends non implémentés doivent échouer explicitement avec un code non nul; seul `--dry-run` peut produire des données factices clairement marquées.
- **REQ-007**: Les chemins FFmpeg, COLMAP, Python et modèles ne doivent pas contenir de chemin absolu propre à une machine dans `project.godot`.
- **REQ-008**: Une correction est terminée uniquement si son test ciblé et les tests de non-régression de sa phase passent.
- **REQ-009**: En cas d'échec, exécuter au maximum trois tentatives documentées avec trois causes ou approches distinctes; restaurer uniquement les modifications du lot courant si les trois échouent.
- **SEC-001**: Valider extension, existence, taille minimale et en-tête magique avant de lire un fichier `.fovea`, `.ply`, `.splat`, `.spz` ou `.sog`.
- **SEC-002**: Ne jamais construire une commande système avec concaténation de chemins utilisateur; utiliser `OS.create_process()` ou `subprocess.run()` avec une liste d'arguments.
- **CON-001**: Préserver les modifications utilisateur préexistantes et ne jamais utiliser `git reset --hard` ou `git checkout --`.
- **CON-002**: Préfixer toutes les commandes du projet avec `rtk`.
- **CON-003**: L'exécution de la phase 2 suppose l'approbation de l'architecture canonique décrite par **ASSUMPTION-001**.
- **GUD-001**: Garder `FoveaCoreManager` comme orchestrateur léger; placer la logique dans les sous-systèmes VR, fovéation, splats et animation.
- **GUD-002**: Classer chaque défaut P0, P1 ou P2 et enregistrer fichier, ligne, cause, impact, correction et test dans le rapport d'audit final.
- **PAT-001**: Le pipeline d'animation canonique reçoit `Array[GaussianSplat]` et applique des offsets additifs à la copie transitoire reconstruite à chaque image.

## 2. Implementation Steps

### Implementation Phase 0 — Baseline reproductible

- GOAL-001: Capturer l'état initial et rendre chaque régression attribuable à un lot précis.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Enregistrer `rtk git status --short --branch`, `rtk git diff --check`, le commit `HEAD`, la version Godot et la version .NET dans le journal d'audit sans modifier l'arbre de travail. | | |
| TASK-002 | Produire la liste des scripts suivis et non suivis sous `addons/foveacore/scripts`, puis séparer explicitement les changements préexistants des futurs patchs. | | |
| TASK-003 | Exécuter la vérification de collisions `class_name`; le baseline attendu contient exactement six collisions connues: `FoveaAnimationSubsystem`, `FoveaFlipbookAnimator`, `FoveaFlowFieldAnimator`, `FoveaLodStretchAnimator`, `FoveaMorphCovarianceAnimator` et `FoveaNeuralOffsetField`. | | |
| TASK-004 | Exécuter une analyse des références `res://` de `project.godot`, des scènes, ressources et scripts; enregistrer chaque cible absente avant toute correction. | | |
| TASK-005 | Créer une scène et une commande de démarrage headless minimales qui chargent les autoloads sans exiger OpenXR, GPU dédié, FFmpeg ou COLMAP. | | |

### Implementation Phase 1 — Outillage de validation fiable

- GOAL-002: Faire fonctionner les contrôles de qualité de manière identique sous Windows et Linux avant de modifier le moteur.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-006 | Modifier `addons/tools/check_typing.py::count_untyped` pour lire chaque fichier avec `encoding="utf-8"` et signaler proprement le chemin d'un fichier invalide; conserver un code de sortie non nul en cas d'erreur. | | |
| TASK-007 | Modifier `addons/tools/check_typing.py::main` et `addons/tools/validate_rules.py::main` pour ne pas dépendre de glyphes non encodables par une console Windows; utiliser des libellés ASCII `PASS` et `FAIL`. | | |
| TASK-008 | Modifier `addons/tools/validate_rules.py::check_scripts` pour utiliser `read_text(encoding="utf-8")`, exclure les dépendances vendored et analyser tous les chemins de production pertinents, pas uniquement `scripts/animation`. | | |
| TASK-009 | Ajouter un test Python temporaire ou permanent qui exécute les deux validateurs avec `PYTHONIOENCODING=cp1252` et UTF-8, et exige le même résultat logique. | | |
| TASK-010 | Modifier `.github/workflows/ci.yml` afin que l'étape d'import Godot capture et classe les erreurs au lieu de masquer tout échec avec `|| true`; autoriser seulement une liste documentée d'avertissements headless. | | |

### Implementation Phase 2 — Consolidation du système d'animation

- GOAL-003: Éliminer les collisions globales et conserver une seule API d'animation non destructive et strictement typée.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-011 | Déclarer `addons/foveacore/scripts/fovea_animation_subsystem.gd` comme implémentation canonique de `FoveaAnimationSubsystem`; conserver `register_modifier(Callable)`, `unregister_modifier(Callable)` et `apply(Array[GaussianSplat])`. | | |
| TASK-012 | Migrer les comportements encore nécessaires de `addons/foveacore/scripts/animation/` vers les implémentations typées de `addons/foveacore/scripts/advanced/`, puis supprimer les déclarations `class_name` concurrentes ou retirer les fichiers legacy devenus sans appelant. | | |
| TASK-013 | Harmoniser `FoveaFlipbookAnimator`, `FoveaFlowFieldAnimator`, `FoveaLodStretchAnimator`, `FoveaMorphCovarianceAnimator`, `FoveaNeuralOffsetAnimator`, `FoveaNeuralOffsetField`, `FoveaBoneSkinAnimator` et `FoveaSplatSkinBinder` sur la signature `(splat: GaussianSplat, time: float, intensity: float) -> void`. | | |
| TASK-014 | Corriger `addons/foveacore/scripts/foveacore_manager.gd::_init_subsystems` pour créer l'animation avant le pipeline splat, injecter exactement une instance, synchroniser les exports à l'exécution et libérer proprement le sous-système. | | |
| TASK-015 | Corriger `addons/foveacore/scripts/fovea_splat_subsystem.gd::_generate_and_filter` pour copier toutes les propriétés animables, appliquer les modificateurs avant le tri et ne jamais modifier `loaded_splats`. | | |
| TASK-016 | Ajouter des tests vérifiant zéro collision `class_name`, l'enregistrement/désenregistrement idempotent, l'absence de mutation de la source et la réversibilité image après image. | | |

### Implementation Phase 3 — Chargement, configuration et liens

- GOAL-004: Garantir un démarrage portable et des erreurs explicites lorsque les composants optionnels sont absents.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-017 | Retirer de `project.godot` les chemins absolus `C:\\Users\\redga\\...`; conserver des valeurs vides ou relatives et résoudre les exécutables via les réglages utilisateur du panneau StudioTo3D. | | |
| TASK-018 | Vérifier les trois plugins activés dans `project.godot`, chaque autoload UID, `xr_action_map.tres`, la scène principale et toutes les bibliothèques de `addons/foveacore/foveacore.gdextension`; désactiver proprement toute entrée absente sur une plateforme. | | |
| TASK-019 | Ajouter un validateur de références `res://` qui échoue sur toute cible absente et ignore uniquement les ressources générées documentées. | | |
| TASK-020 | Rendre OpenXR optionnel au démarrage headless et Compatibility; conserver une voie non-XR fonctionnelle lorsque l'interface OpenXR ou l'eye tracking est indisponible. | | |
| TASK-021 | Ajouter des messages d'erreur incluant composant, chemin, opération et code d'erreur pour chaque chargement de ressource critique. | | |

### Implementation Phase 4 — Logique incomplète et code mort

- GOAL-005: Remplacer les fonctions factices par une implémentation vérifiée ou une indisponibilité explicite sans faux succès.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-022 | Auditer chaque `pass`, `TODO`, `FIXME`, `not implemented`, retour constant et branche inaccessible hors code vendored; classer l'élément comme intentionnel, abstrait, incomplet ou mort avant modification. | | |
| TASK-023 | Implémenter ou retirer les méthodes factices de `addons/foveacore/scripts/advanced/fovea_mobile_optimizer.gd`; `apply_preset()` ne doit annoncer un succès que si les paramètres du renderer ciblé ont réellement changé. | | |
| TASK-024 | Examiner `FoveatedController._ready`, `VisibilityManager._ready` et les callbacks d'inspecteur; remplacer les corps vides non nécessaires par leur suppression, et documenter les callbacks volontairement vides exigés par Godot. | | |
| TASK-025 | Examiner `addons/foveacore/scripts/advanced/fovea_core_splat_renderer.gd` aux lignes contenant `pass` ou `return null`; ajouter des tests de voie nominale et de repli Compatibility/headless. | | |
| TASK-026 | Supprimer les modules sans appelant seulement après une recherche de références GDScript, scènes, ressources, C#, C++ et documentation; conserver un journal des suppressions avec justification. | | |

### Implementation Phase 5 — Formats et reconstruction

- GOAL-006: Éliminer les sorties factices silencieuses et renforcer toutes les frontières de fichiers/processus.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-027 | Corriger `addons/foveacore/scripts/reconstruction/diffsynth_bridge.py::_run_vista4d_render` et `_run_vista4d_inference` pour échouer avec le code 2 hors `--dry-run` tant que l'inférence réelle n'est pas câblée; ne jamais écrire `.diffsynth_done` après un backend incomplet. | | |
| TASK-028 | Remplacer `os.system()` dans `_run_vista4d_preprocess` par `subprocess.run([...], check=True)` et propager l'échec au processus appelant. | | |
| TASK-029 | Vérifier que AnyRecon et DVLT marquent toutes les sorties dry-run comme factices et que les consommateurs refusent ces sorties en mode production. | | |
| TASK-030 | Ajouter des tests de fichiers tronqués, magic invalide, versions inconnues, tailles incohérentes et extensions non prises en charge pour les loaders `.fovea`, `.ply`, `.splat`, `.spz` et `.sog`. | | |
| TASK-031 | Aligner la documentation et l'interface sur les formats réellement pris en charge; ne pas présenter `.spz`, `.sog`, Vista4D, AnyRecon ou DVLT comme opérationnels tant que leurs tests nominaux ne passent pas. | | |

### Implementation Phase 6 — Performance CPU, GPU, mémoire et XR

- GOAL-007: Supprimer les points chauds mesurables et garantir des replis sûrs.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-032 | Profiler `_generate_and_filter`, le tri, les modificateurs d'animation, le culling, la sérialisation et les readbacks GPU avec 50k, 100k et 200k splats; enregistrer temps CPU, temps GPU, allocations et VRAM. | | |
| TASK-033 | Remplacer toute mise à jour `MultiMesh` par `transform_array` et `custom_data_array` groupés; ajouter une règle statique qui interdit les appels par instance dans une boucle. | | |
| TASK-034 | Éviter la complexité CPU `O(nombre_splats × nombre_modificateurs)` pour les scènes importantes: regrouper les modificateurs compatibles, utiliser des filtres de couche en amont et transférer les animations massives au compute shader lorsque `RenderingDevice` existe. | | |
| TASK-035 | Garantir que `culler_pipeline`, `instanced_culler` et leurs champs `rd` sont valides avant `buffer_get_data`, création de pipeline, dispatch ou readback; tester Forward+, Mobile et Compatibility. | | |
| TASK-036 | Vérifier l'absence d'allocation par splat dans le nettoyeur, exécuter le nettoyage sur le flux binaire avant décodage et trier par code Morton 30 bits avant sérialisation. | | |
| TASK-037 | Mesurer le budget XR à 72, 90 et 120 Hz, la latence du regard, la stabilité temporelle et le comportement sans eye tracking; définir un seuil de frame time et une stratégie de dégradation déterministe. | | |

### Implementation Phase 7 — Tests et intégration continue

- GOAL-008: Transformer chaque correction en barrière de non-régression obligatoire.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-038 | Exécuter le parse GDScript sur tous les scripts de production hors `godot-cpp`; aucun script ne doit être ignoré à cause d'un import échoué. | | |
| TASK-039 | Exécuter `py_compile`, les tests des bridges, `dotnet build`, le build Rust sur la plateforme disponible et les tests GDScript non-GPU. | | |
| TASK-040 | Rendre les tests GPU obligatoires sur un runner GPU dédié; conserver un test de repli obligatoire sur les runners sans GPU. | | |
| TASK-041 | Figer une image golden et rendre la régression visuelle bloquante après calibration documentée du seuil RMSE sur les runners retenus. | | |
| TASK-042 | Ajouter une matrice de démarrage Forward+, Mobile et Compatibility, avec et sans XR, avec et sans GDExtension native; échouer sur toute ligne `SCRIPT ERROR` ou erreur non autorisée. | | |
| TASK-043 | Exécuter `rtk git diff --check`, les validateurs de règles et de types corrigés, puis `rtk python -m skills.checkup.cli .`; joindre les résultats au rapport final. | | |

### Implementation Phase 8 — Stabilisation avancée et clôture

- GOAL-009: Réduire la dette résiduelle et produire un état de livraison traçable.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-044 | Dédupliquer les roadmaps et audits obsolètes; conserver une seule source de vérité pour les fonctionnalités livrées, expérimentales et non implémentées. | | |
| TASK-045 | Normaliser les noms de classes, fichiers, signaux et paramètres publics; fournir une migration ou un alias temporaire pour toute API publiée renommée. | | |
| TASK-046 | Vérifier `AGENTS.md` et `CLAUDE.md` avec le checkup, retirer les références périmées et ramener les instructions sous la limite de taille prévue par la politique locale. | | |
| TASK-047 | Produire le rapport final en six sections: résumé global, problèmes détectés, analyse structurelle, analyse performance, corrections appliquées et roadmap résiduelle. | | |
| TASK-048 | Déclarer le projet stable uniquement si les P0 sont à zéro, les P1 restants sont explicitement acceptés, et toutes les barrières de la phase 7 passent sur un commit propre de correction. | | |

## 3. Alternatives

- **ALT-001**: Conserver l'ancien système `scripts/animation` fondé sur des `Dictionary`. Rejeté comme cible car il n'est pas raccordé au pipeline courant `Array[GaussianSplat]`, contient plusieurs corps factices et impose des allocations par splat.
- **ALT-002**: Garder les deux systèmes d'animation en renommant les classes legacy. Rejeté comme état final car cela double les API, les tests et le coût de maintenance; acceptable uniquement comme étape de migration courte et datée.
- **ALT-003**: Désactiver entièrement l'animation pour stabiliser le noyau. Acceptable comme repli temporaire si la phase 2 échoue trois fois, mais insuffisant pour clôturer le plan.
- **ALT-004**: Corriger les fonctions au fil de l'eau sans rétablir les validateurs. Rejeté car les contrôles actuels échouent eux-mêmes sous Windows et ne peuvent pas détecter les régressions de façon fiable.

## 4. Dependencies

- **DEP-001**: Godot 4.7.dev5 Mono officiel ou une version 4.7 compatible permettant le démarrage headless.
- **DEP-002**: .NET SDK 9 correspondant à `FoveaEngine.csproj`.
- **DEP-003**: Python 3.11 ou ultérieur pour les validateurs et bridges.
- **DEP-004**: Toolchain Rust stable pour `addons/foveacore/rust`.
- **DEP-005**: FFmpeg et COLMAP sont optionnels pour le démarrage, obligatoires uniquement pour leurs tests d'intégration respectifs.
- **DEP-006**: Un runner avec GPU Vulkan et, pour la validation XR complète, un runtime OpenXR avec eye tracking ou un simulateur déterministe.

## 5. Files

- **FILE-001**: `addons/tools/check_typing.py` — portabilité d'encodage et couverture de types.
- **FILE-002**: `addons/tools/validate_rules.py` — règles structurelles et portabilité console.
- **FILE-003**: `.github/workflows/ci.yml` — barrières d'import, parse, tests, GPU et rendu.
- **FILE-004**: `project.godot` — chemins portables, plugins, autoloads et XR.
- **FILE-005**: `addons/foveacore/scripts/fovea_animation_subsystem.gd` — coordinateur d'animation canonique.
- **FILE-006**: `addons/foveacore/scripts/foveacore_manager.gd` — orchestration et injection des sous-systèmes.
- **FILE-007**: `addons/foveacore/scripts/fovea_splat_subsystem.gd` — copie transitoire, animation, tri et rendu.
- **FILE-008**: `addons/foveacore/scripts/animation/*.gd` — implémentations legacy à migrer ou retirer.
- **FILE-009**: `addons/foveacore/scripts/advanced/fovea_*animator.gd` et `fovea_*field.gd` — implémentations typées canoniques.
- **FILE-010**: `addons/foveacore/scripts/advanced/fovea_mobile_optimizer.gd` — fonctions actuellement factices.
- **FILE-011**: `addons/foveacore/scripts/reconstruction/diffsynth_bridge.py` — backends incomplets et lancement de processus.
- **FILE-012**: `addons/foveacore/test/` et `test/` — tests unitaires, démarrage, GPU, XR et régression.
- **FILE-013**: `README.md`, `ROADMAP.md`, `ROADMAP_COMPLETE_BACKLOG.md`, `TOP_TASKS.md` et audits datés — statut réel des fonctionnalités.

## 6. Testing

- **TEST-001**: Le scan `class_name` retourne zéro collision dans `addons/` et `test/`.
- **TEST-002**: Les validateurs Python donnent le même résultat sous console UTF-8 et `cp1252` sans exception Unicode.
- **TEST-003**: Le projet démarre en headless dans les trois méthodes de rendu sans XR ni GDExtension native.
- **TEST-004**: Le pipeline d'animation ne modifie jamais les splats sources et restaure exactement la pose source à l'image suivante lorsque tous les modificateurs sont désactivés.
- **TEST-005**: Les fichiers invalides ou tronqués sont refusés avant décodage et ne provoquent ni allocation démesurée ni crash.
- **TEST-006**: Vista4D, AnyRecon et DVLT retournent un code non nul hors `--dry-run` tant que l'inférence nominale n'est pas disponible.
- **TEST-007**: Aucun preset mobile ne retourne ou n'affiche un succès si aucun composant réel n'a été configuré.
- **TEST-008**: Aucun appel GPU n'est effectué lorsque `RenderingDevice` est absent; la voie de repli produit un résultat ou une indisponibilité explicite.
- **TEST-009**: Les tests non-GPU, le build .NET, la syntaxe Python, le parse GDScript et le build Rust disponible passent.
- **TEST-010**: Le benchmark respecte les budgets définis pour 50k, 100k et 200k splats et documente toute dégradation admise.
- **TEST-011**: La matrice XR valide le comportement avec eye tracking, sans eye tracking et sans runtime OpenXR.
- **TEST-012**: `skills.checkup.cli` ne signale aucune dérive bloquante après les mises à jour.

## 7. Risks & Assumptions

- **RISK-001**: L'arbre contient des modifications utilisateur non validées; une correction qui écrase ces changements causerait une perte de travail.
- **RISK-002**: L'exécutable Godot n'est pas disponible dans le `PATH`; les validations complètes peuvent nécessiter son chemin explicite.
- **RISK-003**: Les tests GPU informatifs actuels peuvent masquer des défauts de synchronisation ou de format de buffer.
- **RISK-004**: La suppression de classes legacy peut casser des scènes non détectées si elles utilisent un UID ou une ressource externe au dépôt.
- **RISK-005**: Les performances XR ne sont pas démontrables uniquement en headless ou avec un GPU logiciel.
- **ASSUMPTION-001**: La cible recommandée est le nouveau pipeline typé `GaussianSplat` situé à la racine et sous `scripts/advanced`; cette hypothèse doit être approuvée par le choix A avant TASK-011.
- **ASSUMPTION-002**: `origin/main` est la source distante canonique; elle a été vérifiée à 0 commit d'écart le 2026-07-14.
- **ASSUMPTION-003**: Le miroir Gitea est secondaire et son indisponibilité ne bloque pas les corrections locales.

## 8. Related Specifications / Further Reading

- `AGENTS.md` — règles de codage, performance, architecture et workflow du dépôt.
- `.botte/policy.md` — routage local, hygiène et checkup obligatoire.
- `docs/RD_SPLATS_ANIMES_ROADMAP.md` — conception du pipeline d'animation dynamique.
- `.github/workflows/ci.yml` — contrôles d'intégration actuellement configurés.
- `AUDIT_TODO_2026-06-11.md` et `AUDIT_COMPLET_2026-05-02.md` — audits historiques à revalider, pas à considérer comme preuve actuelle.
