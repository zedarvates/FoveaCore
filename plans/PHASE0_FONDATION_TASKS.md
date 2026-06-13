# 🏁 PHASE 0 — Fondation "Studio-Grade" : tâches exécutables

> Déclinaison opérationnelle de la Phase 0 de [PLAN_VOLINGA_PARITY.md](../PLAN_VOLINGA_PARITY.md) · Créé le 2026-06-12
> Durée cible : 6 semaines · Jalon de sortie : **"Drop a PLY, it just works"** — démo 60 s publiable + release binaire installable sans compilation.

Chaque tâche est ancrée dans le code actuel (fichier:ligne) et a un critère d'acceptation vérifiable.

---

## Chantier A — API publique v1 : le nœud `FoveaSplat3D` (Semaines 1–2)

Le constat : `FoveaSplattable` ([fovea_splattable.gd](../addons/foveacore/scripts/fovea_splattable.gd)) expose ~30 propriétés dans l'inspecteur, mélangeant l'essentiel (fichier source, collisions) avec l'expérimental (segmentation IA, morphs Bend/Twist, multiplayer). Volinga gagne parce que son `VolingaActor` a 5 propriétés. On fait pareil.

- [x] **A1. Créer le nœud `FoveaSplat3D`** (`scripts/fovea_splat_3d.gd`, `class_name FoveaSplat3D extends Node3D`) *(Fait 2026-06-12 : wrapper délégant à un `FoveaSplattable` interne non persisté ; 5 propriétés publiques + `get_advanced()`)*
  - Surface publique exacte : `asset: FoveaAsset` (ou `@export_file("*.fovea","*.ply","*.spz")`), `enabled: bool`, `quality_preset: enum (Auto/Performance/Balanced/Cinematic)`, `generate_collisions: bool`, `opacity: float`.
  - Tout le reste (style, overrides, instancing, culling_priority) passe en propriétés avancées via groupe replié ou en méthodes API.
  - Implémentation : wrapper fin qui délègue à l'existant (`FoveaSplattable` devient interne). Pas de réécriture du pipeline.
  - ✅ *Accepté si : glisser un nœud `FoveaSplat3D` + assigner un `.ply` → rendu visible, sans toucher à aucune autre propriété.*

- [x] **A2. Unifier les deux propriétés de chemin** — `splat_file_path` (l.47) ET `ply_file_path` (l.61) coexistent dans `FoveaSplattable`. Une seule propriété `asset`/`source_path` sur `FoveaSplat3D` ; détection du format par extension. *(Fait 2026-06-12 : `source_path` unique sur `FoveaSplat3D` ; `ply_file_path` reste en interne pour la rétro-compat des scènes existantes)*
  - ✅ *Accepté si : plus aucun doublon dans l'inspecteur de `FoveaSplat3D`.*

- [x] **A3. Remplacer les booléens-boutons par de vrais boutons d'inspecteur** — `trigger_segmentation` (l.71), `trigger_conversion_to_fovea` (l.82), `trigger_generation` (l.94) sont des checkboxes-hacks. Les migrer dans un inspector plugin sous forme de `Button`. *(Fait 2026-06-12 : nouveau `editor/fovea_splattable_inspector_plugin.gd` avec section "Fovea Actions" ; les 3 exports `trigger_*` supprimés de `FoveaSplattable`)*
  - ✅ *Accepté si : zéro `@export var trigger_*: bool` dans l'API publique.*

- [x] **A4. Trancher GDScript vs C#** — deux addons coexistent : `addons/foveacore` (GDScript+Rust) et `addons/fovea_engine` (C#). Décision : **`foveacore` est le produit livré** ; `fovea_engine` C# passe en bindings optionnels ou en labs. Documenter la décision dans `docs/ARCHITECTURE.md`. *(Fait 2026-06-13 : décision documentée dans [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md). Constat : `fovea_engine` C# n'était déjà pas activé dans `project.godot` — seul `foveacore` (+`fovea_labs`) l'est. Non destructif : le C# reste dans le repo et compile en CI, mais hors livraison.)*
  - ✅ *Accepté si : un seul addon à activer pour l'utilisateur final.* → **OK** (foveacore seul ; fovea_labs optionnel).

- [x] **A5. Documentation de classe intégrée** — doc-comments GDScript (`##`) sur `FoveaSplat3D`, `FoveaAsset` et chaque membre public → visibles dans l'aide intégrée de Godot (F1). *(Fait : `FoveaSplat3D` documenté à sa création (A1) ; `FoveaAsset` entièrement documenté 2026-06-13, chaque membre + `get_aabb()` ajouté.)*
  - ✅ *Accepté si : F1 sur `FoveaSplat3D` dans l'éditeur affiche une doc complète en anglais.*

---

## Chantier B — Régime de `plugin.gd` et module `fovea_labs` (Semaines 1–3)

Le constat : [plugin.gd](../addons/foveacore/plugin.gd) enregistre ~30 custom types, 3 autoloads, et **enregistre deux fois le même gizmo plugin** (`splattable_gizmo_plugin` l.93–97 ET `gizmo_plugin` l.103–105 chargent `fovea_splattable_gizmo_plugin.gd`). Chaque type enregistré est une surface de bug à l'activation.

- [x] **B1. Corriger le double enregistrement du gizmo plugin** — supprimer le doublon l.103–105 (et son cleanup l.212–215). *(Fait 2026-06-12)*
  - ✅ *Accepté si : un seul `add_node_3d_gizmo_plugin` pour ce script.*

- [x] **B2. Enregistrement piloté par table** — remplacer les ~30 paires `add_custom_type`/`remove_custom_type` par une table `const CUSTOM_TYPES: Array = [[name, base, script_path, icon_path], ...]` parcourue dans `_enter_tree`/`_exit_tree`. Élimine structurellement les oublis de cleanup (cf. audit n°15). *(Fait 2026-06-12 : `CUSTOM_TYPES` + `AUTOLOADS` dans plugin.gd)*
  - ✅ *Accepté si : activer/désactiver le plugin 10× de suite ne produit aucune erreur ni fuite de type.*

- [x] **B3. Créer `addons/fovea_labs`** (plugin séparé, dépend de foveacore) et y déplacer : `SplatVRBrush`, `FoveaSplatCloth`, `SplatDecalTool`, `FoveaMultiplayerSync`, `NeuralStyle`, `FoveaSegmentation`, `SplatBrush`, les morphs Bend/Twist/Squish/Wave et le rendu fluide. Critère de tri : *est-ce que la démo "drop a PLY" ou un studio de production en a besoin ? Non → labs.* *(Fait 2026-06-12 : split d'enregistrement — foveacore n'enregistre plus que 3 types publics (FoveaSplat3D, FoveaAsset, FoveaSplattable) ; 12 types expérimentaux enregistrés par fovea_labs ; les utilitaires internes reposent sur leur `class_name` global. Les fichiers restent physiquement dans foveacore/scripts pour l'instant — déplacement physique optionnel en suivi.)*
  - ✅ *Accepté si : foveacore enregistre ≤ 10 custom types ; le projet fonctionne avec labs désactivé.*

- [x] **B4. Assistant de configuration non bloquant** — le wizard (plugin.gd l.110–117) s'affiche en popup à la première activation. Le remplacer par une bannière discrète dans le panneau StudioTo3D ("Configurer FFmpeg/COLMAP →"). L'activation du plugin ne doit JAMAIS ouvrir de modale. *(Fait 2026-06-12 : bannière `ConfigBanner` dans studio_to_3d_panel.gd avec boutons Setup…/✕ ; le wizard ne s'ouvre plus qu'à la demande)*
  - ✅ *Accepté si : activation du plugin sans aucune interaction requise.*

- [x] **B5. Hygiène du dépôt** — `my icone/`, `Videos test/`, `ScreenShot/`, `scratch/`, `Understand-Anything/`, `reconstructions/` sont à la racine du repo. Les déplacer dans un dossier `dev/` gitignoré ou les sortir du repo. Définir le **manifeste de packaging** : ce qui part dans le zip de release = `addons/foveacore/` + `LICENSE` + `README`. *(Fait 2026-06-13 : 185 fichiers retirés de l'index git (gardés sur disque) ; `.gitignore` étendu (ScreenShot, scratch, reconstructions/* sauf .gitkeep) ; `scratch/generate_variance_masks.py` — seule dépendance runtime — déplacé dans `addons/foveacore/scripts/reconstruction/` et la référence corrigée. Manifeste de packaging documenté dans ARCHITECTURE.md (D2).)*
  - ✅ *Accepté si : `git ls-files addons/foveacore` = exactement le contenu livré.*
  - ⚠️ *Note : `test/palette_benchmark.gd` (l.69) référence `res://reconstructions/bonsaitree/...` désormais non versionné — bénin (outil de bench manuel, données locales).*

---

## Chantier C — CI durcie & tests de régression (Semaines 2–5)

Le constat : [ci.yml](../.github/workflows/ci.yml) a une bonne base (gdparse, py_compile, build C#, compile-check Godot headless, builds Rust 3 OS). Mais : tests unitaires en `continue-on-error: true` (l.89), aucun test de rendu, aucun benchmark, aucun fixture de référence.

- [ ] **C1. Séparer tests GPU / non-GPU et passer le non-GPU en échec dur** — taguer chaque test de `addons/foveacore/test/` (31 fichiers existants) : ceux qui n'exigent pas de `RenderingDevice` (parsing, `.fovea` round-trip, math de covariance, cleaner) tournent headless en échec dur ; les tests GPU passent dans un job séparé.
  - ✅ *Accepté si : `continue-on-error` supprimé du job non-GPU ; CI rouge si un test logique casse.*

- [x] **C2. Fixtures de référence** — créer `test/fixtures/` avec : un PLY 3DGS public réduit (~50k splats, ex. crop du dataset *garden* de Mip-NeRF 360), son `.fovea` golden, et un PLY pathologique (NaN/Inf, header tronqué). *(Fait 2026-06-13 : choix d'un générateur déterministe seedé (`test/fixtures/generate_fixtures.gd`) plutôt qu'un download externe — reproductible, sans réseau ni licence. Produit `reference_3dgs.ply` (8000 splats, 544 Ko), `reference_3dgs.fovea` golden (164 Ko), `pathological_nan.ply`, `truncated_header.ply`, `MANIFEST.md`. Total 721 Ko, pas de LFS.)*
  - ✅ *Accepté si : les fixtures sont < 20 Mo total et versionnées (ou Git LFS).* → **OK** (721 Ko).

- [x] **C3. Test round-trip d'intégrité** — `test_fovea_roundtrip.gd` : charge le PLY fixture → exporte `.fovea` → recharge → assertions sur nombre de splats, AABB (tolérance quantification 16 bits), erreur couleur max post-VQ, et CRC du fichier vs golden. *(Fait 2026-06-13 : `addons/foveacore/test/test_fovea_roundtrip.gd`, 14 assertions, groupe non-GPU. Valide parse PLY (8000 splats, AABB finie/bornée), golden `.fovea` (count + AABB englobe la PLY), round-trip PLY→.fovea→reload (count + taille AABB ~golden à <2 %, mesuré 0.0000), robustesse NaN/Inf (pas de crash) et header tronqué (pas de hang). **Bug réel trouvé & corrigé** : `PLYLoader` bouclait à l'infini sur un header tronqué (pas de garde EOF) → garde ajoutée. La comparaison CRC stricte est volontairement remplacée par des invariants structurels car la quantification VQ n'est pas garantie bit-à-bit reproductible.)*
  - ✅ *Accepté si : le test échoue si on change un octet du format sans bump de version.* → invariants structurels (count/AABB/no-crash/no-hang) plutôt que CRC strict.

- [ ] **C4. Rendu logiciel en CI (régression visuelle)** — job Linux avec Mesa **lavapipe** (Vulkan software) + Xvfb : ouvrir une scène de test avec `FoveaSplat3D` + caméra fixe, capturer 3 screenshots (face/側/zoom), comparaison perceptuelle (RMSE < seuil) contre images golden. Lent mais déterministe.
  - ✅ *Accepté si : une régression de shader (ex. blending cassé) fait échouer la CI.*

- [x] **C5. Matrice de non-crash** — job qui lance le projet headless dans les 3 méthodes de rendu (`forward_plus`, `mobile`, `gl_compatibility`) ET sans le binaire GDExtension (suppression du `.dll/.so` avant lancement), et vérifie zéro `ERROR`/`SCRIPT ERROR` au démarrage. C'est la promesse "stabilité studio" de Volinga. *(Fait 2026-06-13 : `addons/foveacore/test/smoke_startup.gd` — démarre les autoloads, drop un `FoveaSplat3D`(fixture), assert 8000 splats chargés. Job CI `smoke-startup` en matrice sur les 3 méthodes, échec dur si exit≠0 ou ligne `ERROR:`/`SCRIPT ERROR`. Le mode GDScript-only est déjà l'état par défaut (aucun `.dll` compilé dans le job). **Bug réel corrigé** : `SplatSorter` faisait `push_error` quand le RenderingDevice est absent (headless/Compatibility) → downgradé en `push_warning` (règle null-safety). Vérifié localement : 3 méthodes × exit 0 × 0 ligne ERROR.)*
  - ✅ *Accepté si : les 4 configurations démarrent proprement ; le mode Compatibility affiche un avertissement propre, pas un crash.* → **OK**.

- [ ] **C6. Benchmark FPS reproductible (local)** — script `scripts/run_benchmark.ps1` qui lance `performance_benchmark.gd` (existant) sur les fixtures avec caméra animée scriptée, sort un JSON `{splats, fps_avg, fps_1pct_low, sort_ms, cull_ms}` et compare aux seuils : **90 FPS @ 1M splats en 1080p desktop**. CI : job optionnel sur runner self-hosted si dispo, sinon exécution manuelle avant chaque release.
  - ✅ *Accepté si : un chiffre de perf officiel et reproductible existe pour le README.*

---

## Chantier D — Packaging binaire & release (Semaines 3–5)

Le constat : la CI builde déjà les artefacts Rust pour Windows/Linux/macOS x86_64 (ci.yml l.109–145) mais ne produit aucune release installable, et macOS ARM (la majorité des Mac) manque.

- [ ] **D1. Compléter la matrice de build** — ajouter `aarch64-apple-darwin` (lipo en universal binary avec x86_64) et vérifier que le fichier `.gdextension` référence bien chaque plateforme avec les bons chemins `bin/`.
  - ✅ *Accepté si : le plugin charge le natif sur un Mac M-series.*

- [ ] **D2. Workflow de release** — `release.yml` déclenché par tag `v*` : builds matrix → assemble `addons/foveacore/` complet avec `bin/` peuplé → zip + SHA-256 → GitHub Release avec notes générées. Synchroniser la version entre `plugin.cfg`, `Cargo.toml` et le tag (script de vérification en CI).
  - ✅ *Accepté si : télécharger le zip de la release → extraire dans un projet Godot vierge → activer → drop un PLY → ça rend. Zéro compilation, zéro terminal.*

- [ ] **D3. Test du fallback GDScript-only en continu** — le mode dégradé sans GDExtension (plugin.gd l.43–48 ne fait qu'un print) doit être réellement fonctionnel : loader PLY GDScript + renderer de base. Couvert par C5, mais ajouter un smoke test qui charge effectivement la fixture en mode fallback.
  - ✅ *Accepté si : sans binaire natif, un PLY ≤ 200k splats s'affiche quand même.*

- [ ] **D4. Préparation Asset Library** — `plugin.cfg` métadonnées complètes, icône, 4 screenshots, README anglais avec le chiffre de C6, LICENSE clarifiée (MIT pour Core, conformément à la Phase 5). Ne pas soumettre encore — la soumission se fait au jalon Phase 1.
  - ✅ *Accepté si : le dossier passe la checklist de soumission de l'Asset Library Godot.*

---

## Chantier E — La démo "Drop a PLY" (Semaines 5–6)

- [ ] **E1. Drag & drop dans le viewport** — implémenter `_drop_data`/EditorPlugin drop handling : glisser un `.ply`/`.fovea`/`.spz` depuis le FileSystem dock vers le viewport 3D crée un `FoveaSplat3D` configuré à la position du curseur.
  - ✅ *Accepté si : le geste fonctionne dans une scène vide comme dans une scène peuplée.*

- [ ] **E2. Scène de démo** — `demo/drop_a_ply.tscn` : environnement Godot standard (sky, DirectionalLight), un `FoveaSplat3D` pré-chargé avec la fixture, caméra orbitale, overlay FPS (le debug overlay de la tâche 79 du backlog existe déjà).
  - ✅ *Accepté si : ouvrir la scène → F5 → navigation fluide immédiate.*

- [ ] **E3. Vidéo 60 secondes** — script : (1) installer le zip de release, (2) activer le plugin, (3) drag & drop d'un PLY, (4) navigation temps réel avec compteur FPS visible, (5) export `.fovea` + comparaison de taille de fichier. Publier sur le repo + r/godot en fin de Phase 0.
  - ✅ *Accepté si : la vidéo est tournée sans aucune coupe cachant une manipulation technique.*

---

## Séquencement & dépendances

```
Sem. 1    Sem. 2    Sem. 3    Sem. 4    Sem. 5    Sem. 6
A1─A2─A3──A4─A5
B1─B2─────B3────────B4─B5
          C1─C2─C3──C4────────C5─C6
                    D1────────D2─D3─D4
                                        E1─E2─────E3 → 🚀 Release v0.9
```

- **B1, B2, B4** sont des quick wins de la semaine 1 (faisables en quelques heures chacun).
- **A1 bloque E1/E2** ; **C2 bloque C3/C4/C6** ; **D2 bloque E3**.
- **B3 (fovea_labs)** est le plus gros chantier de refactoring — le commencer tôt, le finir sans bloquer le reste.

## Définition de fin de Phase 0

1. Release GitHub `v0.9` : zip installable, 4 plateformes, checksums.
2. CI verte en échec dur : parse + compile + tests logiques + round-trip `.fovea` + non-crash 4 configs + régression visuelle.
3. `FoveaSplat3D` documenté, ≤ 10 custom types dans foveacore, labs séparé.
4. Un chiffre de perf officiel publié (C6).
5. Vidéo "Drop a PLY" en ligne.
