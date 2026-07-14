# R&D — Splats Animés : Prompt Amélioré & Roadmap Phase 7

> **Date** : 2026-07-02
> **Statut** : Proposition R&D validée contre le code réel du repo
> **Objectif** : Faire de FoveaCore le premier moteur 3DGS avec un système d'animation de splats complet (différenciateur mondial)

---

## 1. État des lieux — Vérifié contre le code

Avant de rêver, inventaire de ce qui **existe réellement** dans le repo (audit du 2026-07-02).

### ✅ Briques déjà en place (fondations de l'animation)

| Brique | Fichier | Pertinence pour l'animation |
|---|---|---|
| Codebook de covariance (texture) | `splat_render.gdshader` (`covar_texture`), `water_splat_particle.gdshader` | Base du **Morph Covariance** : Σ est déjà indexée, donc interpolable |
| Palette / quantification K-Means | `scripts/color_quantization.gd` (`kmeans_quantize`, 256 clusters) | Animation de couleur par interpolation de palette |
| Layered Splatting (layer_type 8 bits dans `data3`) | `shaders/splat_render_triangle.gdshader:136-228`, `gpu_culling_compute.glsl`, `tile_rasterizer.glsl` | Le champ `layer_id` a de la place pour un **LAYER_ANIM** |
| Advection GPU eau (flow, recyclage, obstacles, splash) | `shaders/water_splat_particle.gdshader` | **70% du système Flow Fields généralisé est déjà écrit** |
| Flow painting (direction stockée dans `splat.normal`) | `scripts/advanced/splat_brush_engine.gd` (`brush_flow_direction`) | L'outil auteur du champ de flux existe déjà |
| Animation de layers pilotée par la lumière | `scripts/advanced/splat_lighting_animator.gd` | Preuve de concept : les layers SHADOW/LIGHT bougent déjà à runtime |
| Cloth Verlet masse-ressort sur splats (+ déchirure, squish) | `scripts/advanced/fovea_splat_cloth.gd` (`FoveaSplatCloth3D`) | Animation physique de splats **déjà fonctionnelle en CPU** |
| Déformation non-destructive (snapshot des transforms) | `scripts/advanced/fovea_clay_deformer.gd`, `fovea_surface_deformer.gd` | Pattern à réutiliser pour toute animation réversible |
| Bridge neural / ComfyUI | `scripts/advanced/neural_style_bridge.gd`, `scripts/materials/style_engine.gd` | Porte d'entrée du **Neural Offset Field** |
| Pipeline compute complet (cull, sort bitonique, tile raster, Hi-Z) | `shaders/gpu_culling_compute.glsl`, `sort_bitonic_splats.glsl`, `tile_rasterizer.glsl` | Infrastructure GPU où brancher un pass d'animation |
| LOD hybride | `scripts/advanced/fovea_hybrid_lod_controller.gd` | Base du **LOD Stretch** et du budget d'animation |

### ❌ Ce qui n'existe pas encore (le champ libre)

- **Aucun skinning / bones pour splats** (aucune occurrence de `bone`/`skeleton` dans les scripts) — le "WIP dans meshflow_outputs" mentionné par Copilot n'est pas confirmé dans le repo.
- **Aucune animation de covariance** (Σ est statique une fois chargée).
- **Aucun champ de flux généralisé** (l'advection est câblée en dur dans le shader eau).
- **Aucun système temporel/flipbook** (pas de `LAYER_ANIM`, pas de keyframes).
- **Aucun MLP/offset field neural** à runtime.

### 🎯 Conclusion de l'audit

Les propositions de Copilot sont **cohérentes avec l'architecture** et 3 d'entre elles sont à ~70% déjà construites. Les priorités qui maximisent le ratio différenciation/effort :

1. **Flow-Driven Animation** (généraliser l'eau) — effort faible, effet visuel immédiat.
2. **Morph Covariance Animation** — jamais publié nulle part, effort moyen.
3. **Bone-Driven Splat Animation** — révolutionnaire mais effort élevé (à faire en dernier).

---

## 2. Prompt Amélioré

Prompt autonome à donner à un agent (Claude Code, Copilot…) pour implémenter la Phase 7. Il encode le contexte réel du repo, les contraintes CLAUDE.md et les critères d'acceptation.

```markdown
# MISSION — Phase 7 : Dynamic Splat Animation pour FoveaCore (Godot 4.6+)

Tu travailles sur FoveaCore (F:\foveaengine\fovea-engine), un renderer hybride
Mesh + 3D Gaussian Splatting pour Godot 4 avec pipeline GPU compute complet
(culling `gpu_culling_compute.glsl`, tri bitonique `sort_bitonic_splats.glsl`,
tile rasterizer `tile_rasterizer.glsl`) et rendu via
`splat_render.gdshader` / `splat_render_triangle.gdshader`.

## Format de données existant (NE PAS CASSER)
- Splat packé : data3 = opacity (8 bits) | layer_id (8 bits) | padding (16 bits).
- Covariance quantifiée via codebook texture (`covar_texture`).
- Couleurs optionnellement palettisées (`palette_texture`, k-means dans
  `scripts/color_quantization.gd`).
- Layered splatting : layer_type ∈ {BASE=0, SATURATION=1, LIGHT=2, SHADOW=3}
  lu dans `splat_render_triangle.gdshader`.
- Format fichier `.fovea` : magic 8 octets `FOVEA_3D`, données triées Morton 30 bits.

## Systèmes existants à RÉUTILISER (pas réécrire)
- `shaders/water_splat_particle.gdshader` : advection GPU (flow_direction,
  flow_speed, cycle de recyclage, collision obstacle, splash) → à généraliser.
- `scripts/advanced/splat_brush_engine.gd` : peinture de flux
  (brush_flow_direction stocké dans splat.normal) → outil auteur du flow field.
- `scripts/advanced/splat_lighting_animator.gd` : déplacement runtime des
  layers LIGHT/SHADOW → modèle pour tout animateur de layer.
- `scripts/advanced/fovea_splat_cloth.gd` : solveur Verlet masse-ressort CPU
  avec bindings splat→point → base du portage GPU physique.
- `scripts/advanced/fovea_clay_deformer.gd` : pattern snapshot non-destructif
  → OBLIGATOIRE pour toute animation (réversibilité totale).

## Contraintes de code (CLAUDE.md)
- GDScript strictement typé ; pas de chaînage de méthodes void.
- Jamais de calcul lourd dans _ready() → call_deferred() ou thread.
- Garde-fous null sur culler_pipeline/rd avant tout buffer_get_data.
- Jamais de boucle set_instance_transform() : bulk writes PackedFloat32Array.
- Sous-systèmes découplés sous FoveaCoreManager (nouveau :
  `FoveaAnimationSubsystem`).
- Les animations opèrent sur snapshot des transforms originaux (réversible).

## Tâche
Implémente [SOUS-PHASE X — voir roadmap docs/RD_SPLATS_ANIMES_ROADMAP.md] :
1. Écris d'abord un test (scène ou script de test dans addons/foveacore/test/).
2. Implémente le minimum GPU-first : les offsets d'animation se calculent dans
   un compute shader AVANT le pass de culling, jamais en CPU par splat.
3. L'animation doit être un PASS ADDITIF : pos_final = pos_base + Δpos(t),
   Σ_final = morph(Σ_base, t). Les données de base ne sont jamais mutées.
4. Budget : l'animation ne doit pas coûter plus de 0,5 ms GPU pour 1M splats
   (mesure via RenderingDevice timestamps, cf. docs/benchmark.md).
5. Expose les paramètres en @export + un panneau editor minimal.
6. Documente dans docs/ANIMATED_SPLATS.md (append).

## Critères d'acceptation
- Zéro régression sur test_foveacore.tscn et les tests existants.
- Toggle on/off à chaud sans réallocation de buffers.
- Fonctionne en VR (stéréo) et en mode Compatibility (fallback no-op propre).
```

---

## 3. Roadmap Phase 7 — Dynamic Splat Animation

Découpage en 6 sous-phases, ordonnées par ratio impact/effort. Chaque sous-phase est livrable indépendamment (une release, une vidéo de démo, un post Reddit).

### Vue d'ensemble

| Sous-phase | Feature | Effort | Différenciation | Dépend de | Statut (2026-07-02) |
|---|---|---|---|---|---|
| 7.0 | Infrastructure `FoveaAnimationSubsystem` + pass compute animation | S | — (fondation) | — | ✅ CPU |
| 7.1 | Flow-Driven Animation (généralisation de l'eau) | M | ★★★ | 7.0 | 🟡 CPU (WIND+BREATHE) |
| 7.2 | Morph Covariance Animation | M | ★★★★★ (jamais publié) | 7.0 | 🟡 CPU (PULSE+BREATHE+WOBBLE) |
| 7.3 | LAYER_ANIM + flipbook temporel | M | ★★★ | 7.0 | 🟡 CPU + shader non compilé |
| 7.4 | Material Oscillation + LOD Stretch | S | ★★ | 7.0 | 🟡 CPU |
| 7.5 | Neural Offset Field (MLP/ComfyUI) | L | ★★★★ | 7.0, 7.2 | 🟡 CPU (baked lookup only) |
| 7.6 | Bone-Driven Splat Animation (GPU skinning) | XL | ★★★★★ | 7.0, portage GPU du cloth | 🟠 CPU, **non exécuté, risque le plus élevé** |

Légende : ✅ testé par construction (types purs) · 🟡 code + tests écrits, non exécutés dans
cet environnement (pas de binaire Godot disponible) · 🟠 idem 🟡 mais avec une dépendance API
moteur (`Skeleton3D`) non vérifiable sans exécution réelle. **Rien dans cette colonne ne
remplace `godot --script res://addons/foveacore/test/test_*.gd` — à faire avant tout merge.**

Effort : S ≈ 1-3 jours, M ≈ 1-2 semaines, L ≈ 3-4 semaines, XL ≈ 1-2 mois.

---

### Phase 7.0 — Fondation : `FoveaAnimationSubsystem` (prérequis) — ✅ implémentée (CPU pass point)

**But** : un point d'ancrage unique pour toute animation, non-destructif.

**Réalisé (2026-07-02)** — implémentation CPU-first alignée sur l'architecture réellement
en place (le pipeline splat de `FoveaSplatSubsystem` reconstruit `current_splats:
Array[GaussianSplat]` à partir de `FoveaSplattable.loaded_splats` **à chaque frame** ;
il n'y a pas de buffer GPU persistant partagé à ce niveau — celui-ci n'existe que côté
`FoveaInstancedSplatRenderer` / `gpu_culler_pipeline.gd`. La fondation choisit donc le
point d'ancrage qui correspond au code existant plutôt qu'un pipeline hypothétique) :

- [x] `scripts/fovea_animation_subsystem.gd` : `FoveaAnimationSubsystem`, registre de
      modifiers (`Callable(splat, time, intensity) -> void`), horloge `_time`, toggle
      `enabled` avec signal `animation_toggled`.
- [x] Enregistré dans `FoveaCoreManager._init_subsystems()` au même niveau que VR/Foveated/Splat,
      avec exports `animation_enabled` / `animation_global_intensity` et API publique
      `toggle_animation()` (miroir de `toggle_foveated()`).
- [x] Point d'ancrage dans `FoveaSplatSubsystem._generate_and_filter()` : `animation_subsystem.apply(current_splats)`
      appelé **après génération, avant le tri** — donc les positions animées entrent
      dans le depth-sort et dans la passe foveated (poids de gaze cohérents).
- [x] Non-destructif par construction : `current_splats` est une copie transitoire
      reconstruite chaque frame depuis `loaded_splats` (jamais muté) — donc désactiver
      l'animation restaure exactement l'état de base sans code de restauration dédié.
- [x] Test : `test/test_animation_subsystem.gd` (pattern `SceneTree` existant, cf.
      `test_fovea_asset.gd`) — no-op quand désactivé, application additive, retrait de
      modifier, signal de toggle. **Non exécuté dans cet environnement (pas de binaire
      Godot disponible ici) — à lancer via `godot --script res://addons/foveacore/test/test_animation_subsystem.gd` avant merge.**

**Non fait / reporté** :
- [ ] Le vrai pass **GPU compute** (`shaders/splat_animate.glsl`, double buffer base/animé,
      groupage dans le graphe de dispatch `gpu_culling_compute.glsl`) reste à faire pour
      le chemin **instancié GPU** (`FoveaInstancedSplatRenderer`) — nécessaire quand les
      sous-phases 7.1+ doivent tenir le budget 1M splats / 0,5 ms en VR. La version 7.0
      actuelle est CPU, donc valable pour la démonstration et les petites scènes, mais
      **doit être portée en compute shader avant que 7.1 (Flow) ne soit activé sur de
      gros nuages de points instanciés**.
- [ ] Réservation des 4 bits `anim_flags` dans `data3` (nécessaire seulement côté GPU).

**Livrable** : aucun effet visible par défaut (aucun modifier enregistré), mais le
point de branchement, le toggle et les tests sont en place pour 7.1+.

---

### Phase 7.1 — Flow-Driven Animation 🌊 (quick win, ~70% existant) — 🟡 implémentée en CPU (WIND + BREATHE)

**But** : généraliser l'advection du shader eau à n'importe quel groupe de splats. Cheveux, feuillage, tissus, fumée, scènes "vivantes".

**Réalisé (2026-07-02)** :
- [x] `scripts/advanced/fovea_flow_field_animator.gd` (`FoveaFlowFieldAnimator`, `Node3D`) : s'enregistre comme modifier sur `FoveaAnimationSubsystem` via `FoveaCoreManager.get_animation_subsystem()` (pattern autoload, cf. `foveacore_manager.gd:get_animation_subsystem()`).
- [x] Déplacement exprimé en **fonction pure du temps absolu** (`Δpos = f(pos, time) * amplitude * weight`), pas en advection intégrée (`pos += v*dt`) : nécessaire car `current_splats` est reconstruit depuis la source chaque frame côté CPU (pas de buffer persistant à ce niveau du pipeline, cf. note Phase 7.0) — donc pas d'accumulation de vélocité possible/voulue ici.
- [x] Preset `WIND` : pseudo-curl noise (`FastNoiseLite.get_noise_3d`, le temps encodé comme offset de scrolling par axe avec des constantes distinctes pour décorréler les 3 échantillons — Godot 4 n'a pas de bruit 4D natif).
- [x] Preset `BREATHE` : pulsation radiale sinusoïdale autour de l'origine du node.
- [x] Amplitude modulée par `layer_type` via un dictionnaire `layer_weights` exporté (défaut : `LEAVES`/`LIQUID` = 1.0, `SHADOW` = 0.5, comme spécifié).
- [x] Test `test/test_flow_field_animator.gd` : layer à poids nul jamais déplacé, `SHADOW` = exactement la moitié de `BASE`, offset `BREATHE` colinéaire à la direction radiale.

**Non fait / reporté** :
- [ ] Preset `CURRENT` (peint à la main via SplatBrush) — nécessite de rasteriser les strokes de `splat_brush_engine.gd` dans une texture 3D échantillonnable, c'est un outil auteur à part entière, pas juste un modifier CPU. Reporté à une itération dédiée.
- [ ] **Portage GPU compute** (`shaders/splat_animate.glsl`, mode `ANIM_FLOW`, texture 3D de flux) pour le chemin `FoveaInstancedSplatRenderer` — requis avant d'activer WIND/BREATHE sur de gros nuages instanciés (budget 0,5 ms / 1M splats). La version actuelle est CPU-only via `FoveaSplatSubsystem`, donc valable pour les scènes non-instanciées et les démos, pas encore pour le chemin GPU instancié.
- [ ] Démo scène forêt/rideau + GIF README/boutique.

**Différenciateur** : premier moteur 3DGS avec animation vector-field pilotée par layer_type, peinte à la main en VR (une fois CURRENT livré).

---

### Phase 7.2 — Morph Covariance Animation 💎 (le différenciateur absolu) — 🟡 implémentée en CPU (PULSE + BREATHE + WOBBLE)

**But** : animer la covariance Σ elle-même. Personne ne le fait — ni la littérature (4DGS anime les positions, pas les formes), ni les moteurs existants.

**Réalisé (2026-07-02)** — implémentation CPU alignée sur la représentation réelle du
pipeline : dans `GaussianSplat`, la covariance 2D (`covariance: Vector2`) n'est pas
stockée mais **dérivée** de `scale`/`rotation` via `compute_derived()`. "Morpher Σ" en
CPU signifie donc animer `scale`/`rotation` puis rappeler `compute_derived()` chaque
frame — l'équivalent CPU exact de morpher la vraie matrice 3x3 :

- [x] `scripts/advanced/fovea_morph_covariance_animator.gd` (`FoveaMorphCovarianceAnimator`,
      `Node3D`), même pattern d'enregistrement que le flow field animator (7.1).
- [x] **Correction critique appliquée** (celle que Copilot avait notée comme risque) :
      toute animation de scale est **multiplicative en log-space**
      (`factor = exp(amplitude * f(t))`), jamais additive/linéaire — le scale reste
      strictement positif, aucune ellipse ne peut dégénérer ou s'inverser. Test dédié
      `_test_pulse_never_degenerates` qui échantillonne un cycle complet.
- [x] `PULSE` : pulsation uniforme log-space de l'ellipsoïde entier.
- [x] `BREATHE` : anisotrope, approximativement préservatrice de volume — l'axe dominant
      (le plus grand des 3 composants de `scale`) s'étend pendant que les deux autres se
      contractent, cycle inversé en alternance.
- [x] `WOBBLE` : jitter de rotation par quaternion, angle max exporté en degrés, autour
      d'un axe pseudo-aléatoire **déterministe par splat** (dérivé du hash de sa position,
      pas d'état persistant — cohérent avec `current_splats` reconstruit chaque frame).
- [x] Phase per-splat déterministe via `hash(splat.position)` (pas de `splat_id` stable
      d'une frame à l'autre dans ce pipeline CPU, donc la position sert de clé stable).
- [x] Amplitude modulée par `layer_type` (dictionnaire `layer_weights`, défaut `LIQUID`=1.0,
      `LEAVES`=0.6, comme les autres animateurs de la Phase 7).
- [x] Tests `test/test_morph_covariance_animator.gd` : non-dégénérescence du pulse sur un
      cycle complet, direction opposée axe dominant/non-dominant en breathe, quaternion
      resté unitaire après wobble, layer à poids nul intact, déterminisme phase/axe.

**Non fait / reporté** :
- [ ] `MORPH` (Σ_base → Σ_target authoré) — nécessite l'outil SplatBrush "Covariance Target"
      (sculpter l'état cible via le clay deformer existant) ; c'est un outil auteur, pas
      juste un modifier, même raison de report que `CURRENT` en 7.1.
- [ ] **Portage GPU compute** : interpolation `Σ_t = slerp_covariance(...)` dans
      `splat_render.gdshader`/`splat_animate.glsl` via le `covar_texture` codebook
      (deux entrées Σ_base/Σ_target + phase, +16 bits/splat) — nécessaire pour le chemin
      instancié GPU et le budget VR. La version actuelle anime `scale`/`rotation` en
      CPU dans `FoveaSplatSubsystem`, donc valable pour scènes non-instanciées/démos.
- [ ] Démo créature/blob + article technique "Morph Covariance Animation: Animating the
      Gaussians Themselves".

**Différenciateur** : contribution originale au domaine. Base technique en place (CPU) ;
publication et portage GPU restent la prochaine étape à plus forte valeur marketing.

---

### Phase 7.3 — LAYER_ANIM & Flipbook Temporel ⚡ — 🟡 implémentée en CPU

**But** : un layer dédié à l'animation, avec interpolation temporelle et flipbook volumétrique. Flammes, FX magiques, sprites volumétriques VR ultra légers.

**Réalisé (2026-07-02)** :
- [x] `LAYER_ANIM = 7` ajouté à `GaussianSplat.LayerType` (`reconstruction/gaussian_splat.gd`) —
      valeur `7` choisie pour ne renuméroter aucun layer existant (BASE..TRUNK = 0..6).
- [x] `splat_render_triangle.gdshader` : **une seule branche ajoutée** dans la chaîne
      if/else-if existante de calcul de `layer_weight` (`layer_type == 7u → layer_weight = 1.0`,
      inconditionnel — les FX ne doivent pas s'assombrir hors zone de regard). Changement
      isolé, aucune autre ligne touchée. `gpu_culling_compute.glsl`/`tile_rasterizer.glsl`
      n'ont pas de logique dépendant de la sémantique du layer (juste le layout `data3`
      en commentaire) → **aucun changement requis** dans ces deux fichiers.
      ⚠️ **Non compilé/testé** : pas de binaire Godot disponible dans cet environnement
      pour valider la compilation du shader. À vérifier avant merge.
- [x] `GaussianSplat` reçoit deux nouveaux champs `flipbook_frame: int = -1` /
      `flipbook_frame_count: int = 0` (défaut rétrocompatible : un splat non tagué n'est
      jamais affecté), + support dans `to_dict()`/`from_dict()`.
- [x] `scripts/advanced/fovea_flipbook_animator.gd` (`FoveaFlipbookAnimator`) : sélectionne
      la frame active via `floor(time * fps) % frame_count` et met `opacity = 0` sur toutes
      les autres frames (culling par transparence + `discard` du fragment shader existant —
      coût quasi nul, cohérent avec la spec). Crossfade optionnel entre frame courante et
      suivante (`opacity` complémentaire), désactivé par défaut.
- [x] Tests `test/test_flipbook_animator.gd` : splat non tagué jamais touché, exactement une
      frame visible à un instant donné, cycle correct `floor(t*fps) % N`, crossfade à 50/50
      au point milieu exact.

**Non fait / reporté** :
- [ ] Import : dossier `.ply`/`.fovea` → flipbook (extension de `fovea_asset_loader.gd` pour
      tagger `flipbook_frame`/`flipbook_frame_count` au chargement). L'animateur consomme
      ces champs mais rien ne les peuple encore automatiquement — à faire manuellement ou
      via un futur outil d'import.
- [ ] Pont StudioTo3D (séquence vidéo reconstruite → flipbook automatique via le pipeline
      STAR/WorldMirror existant) — dépend de l'import ci-dessus.
- [ ] **Portage GPU** : la sélection de frame active est CPU-only aujourd'hui (dans
      `FoveaFlipbookAnimator`, via `FoveaAnimationSubsystem`) ; pour le chemin instancié
      GPU (`FoveaInstancedSplatRenderer`), il faudrait pousser `anim_time`/`fps` en uniform
      et calculer la frame active dans `gpu_culling_compute.glsl` pour éviter la lecture
      CPU du buffer — même remarque de portage que 7.1/7.2/7.4.
- [ ] Démo flamme stylisée + sort magique en VR.

---

### Phase 7.4 — Material Oscillation & LOD Stretch 🌈 (quick wins groupés) — 🟡 implémentée en CPU

**But** : animer les paramètres des 6 matériaux procéduraux du style engine + squash & stretch via le LOD.

**Réalisé (2026-07-02)** :
- [x] `scripts/materials/style_engine.gd` : `MaterialStyleConfig` reçoit deux nouveaux champs
      `osc_amplitude` / `osc_frequency` (défaut `0.0` → **zéro régression**, aucun appelant
      existant n'est affecté). Nouvelle fonction pure `compute_color_oscillated(pos, normal,
      material_type, config, light_direction, time)` qui domain-warp `detail`/`grain`/`noise_scale`
      par un facteur `1 + osc_amplitude * sin(time * osc_frequency * TAU)` avant de déléguer à
      `compute_color()` existant — donc les 6 matériaux (Stone, Wood, Metal, Skin, Fabric, Glass)
      héritent tous de l'oscillation gratuitement, sans dupliquer leur logique procédurale.
- [x] Test `test/test_material_oscillation.gd` : `osc_amplitude == 0.0` bit-identique à
      `compute_color()` (non-régression prouvée), amplitude non-nulle produit des couleurs
      différentes à des temps différents.
- [x] LOD Stretch : `scripts/advanced/fovea_lod_stretch_animator.gd` (`FoveaLodStretchAnimator`),
      même famille d'animateurs enregistrés (7.1/7.2) — pulsation isotrope log-space
      (`factor = exp(amplitude * sin(...))`, même garde-fou anti-dégénérescence que 7.2)
      pour le squash & stretch cartoon. Test `test/test_lod_stretch_animator.gd`.

**Non fait / reporté** :
- [ ] Presets nommés "Living Watercolor" / "Pulsing Metal" / "Breathing Wood" (juste des
      valeurs par défaut de `MaterialStyleConfig` à documenter/exposer en éditeur — trivial
      une fois qu'on a une UI de style, pas encore de blocage technique).
- [ ] **Animation fovéatée** (coupure hors zone de regard) : reportée. Le point d'ancrage
      actuel — `FoveaAnimationSubsystem.apply(splats)` — reçoit `(splat, time, intensity)`
      sans contexte caméra/viewport, donc impossible de projeter la position monde vers
      l'écran pour comparer à `fovea_gaze_*`/`fovea_outer_radius` (ces uniforms sont
      aujourd'hui consommés côté GPU uniquement). Deux options pour lever ça : (a) injecter
      une référence caméra dans `FoveaAnimationSubsystem.apply()`, ou (b) déplacer ces
      animateurs vers le pass GPU compute — à trancher en même temps que le portage GPU de
      7.1/7.2.
- [ ] Branchement dans `fovea_hybrid_lod_controller.gd` (l'implémentation actuelle est un
      animateur indépendant, pas encore piloté par la logique de LOD existante).

---

### Phase 7.5 — Neural Offset Field 🧠 — 🟡 implémentée (baked lookup, CPU)

**But** : un petit MLP prédit `Δpos, ΔΣ, Δcolor` en fonction de (time, splat_id, features locales). Micro-mouvements organiques "AI-driven".

**Réalisé (2026-07-02)** — la moitié "offline, zéro inférence runtime" du plan, comme
prévu en premier dans la spec originale :
- [x] `scripts/advanced/fovea_neural_offset_field.gd` (`FoveaNeuralOffsetField`, `Resource`) :
      grille 3D de déplacements bakés (`PackedVector3Array`, `grid_dims`, AABB, N frames
      temporelles, fps) + `sample(world_pos, time)` avec **interpolation trilinéaire
      spatiale** et **sélection de frame la plus proche temporellement**. C'est un lookup
      pur (pas d'inférence), conçu pour recevoir la sortie bakée d'un pipeline offline
      (ComfyUI / `neural_style_bridge.gd` / distillation STAR) sans dépendre de son format
      d'entraînement — juste un tableau de vecteurs.
- [x] `scripts/advanced/fovea_neural_offset_animator.gd` (`FoveaNeuralOffsetAnimator`) :
      même pattern d'enregistrement que les autres animateurs Phase 7, ajoute
      `field.sample(splat.position, time) * amplitude * weight` à la position du splat.
- [x] Tests `test/test_neural_offset_field.gd` : exactitude aux 8 coins d'une grille 2×2×2,
      moyenne trilinéaire exacte au centre, clamp hors-limites (pas d'extrapolation),
      champ vide = no-op, sélection de frame temporelle correcte, câblage de l'animateur.

**Non fait / reporté (le "stretch goal" était déjà annoncé comme tel dans la spec initiale)** :
- [ ] Pipeline de baking effectif (`neural_style_bridge.gd`/ComfyUI → export d'un
      `FoveaNeuralOffsetField.tres`) — aujourd'hui le champ doit être peuplé manuellement/
      par script ; aucun outil ne génère encore les offsets depuis une vidéo source.
- [ ] Entraînement / distillation via le cache temporel causal STAR — nécessite une vraie
      pipeline offline (Python), hors scope GDScript.
- [ ] Runtime MLP (hash-grid + petit réseau évalué en compute shader) — stretch goal
      explicitement reporté dès la version initiale de la roadmap, aucun changement de
      statut.
- [ ] **Portage GPU** de l'échantillonnage bake-lookup lui-même (actuellement CPU pur,
      texture 3D GPU native serait strictement plus rapide qu'un `PackedVector3Array` +
      trilinéaire GDScript) — même remarque de portage que 7.1/7.2/7.3/7.4.

---

### Phase 7.6 — Bone-Driven Splat Animation 🦴 (le boss final) — 🟠 implémentée en CPU, **risque le plus élevé de tout le batch**

**But** : personnages et créatures en splats riggés. Personne ne fait ça aujourd'hui.

**Réalisé (2026-07-02)** :
- [x] Étape 1 — Binding : `scripts/advanced/fovea_splat_skin_binder.gd` (`FoveaSplatSkinBinder`,
      classe statique). `bind_splats(splats, skeleton, max_bones=4)` calcule, pour chaque
      splat, les `max_bones` bones les plus proches en espace repos (poids inverse-distance
      normalisés). Heuristique volontairement simple (pas de heat diffusion/geodesic
      binding) — suffisant pour un premier pipeline fonctionnel, cf. note dans le fichier.
      `GaussianSplat` reçoit `bone_indices` (4×int), `bone_weights` (4×float), `bind_pose_position`
      (défauts rétrocompatibles : `[-1,-1,-1,-1]`/`[0,0,0,0]`/`ZERO` = splat non riggé).
- [x] Étape 2 — Skinning : `scripts/advanced/fovea_bone_skin_animator.gd`
      (`FoveaBoneSkinAnimator`), Linear Blend Skinning CPU : `pos = Σ wᵢ (Bᵢ · pos)` exactement
      comme spécifié, où `Bᵢ = get_bone_global_pose(i) * get_bone_global_rest(i)⁻¹`. **La
      transformation de la covariance est bien appliquée** comme demandé : la partie
      rotation de `Bᵢ` (blend par slerp pondéré) est composée avec `splat.rotation`, exactement
      le même pattern de composition quaternion que le preset `WOBBLE` de la Phase 7.2 — c'est
      la façon dont ce pipeline CPU réalise `Σ' = R Σ Rᵀ` (rappel : `covariance` est dérivée de
      `scale`/`rotation` via `compute_derived()`, pas stockée en 3x3 — cf. note Phase 7.2).
- [x] **Correctif appliqué au passage** : en implémentant le binding, j'ai découvert que
      `FoveaSplatSubsystem._generate_and_filter()` reconstruit chaque `GaussianSplat` transitoire
      champ par champ depuis `loaded_splats`, et la Phase 7.3 avait ajouté `flipbook_frame`/
      `flipbook_frame_count` à `GaussianSplat` **sans les ajouter à cette copie** — un splat
      authoré avec des tags flipbook perdait silencieusement ces tags à chaque frame. Corrigé
      dans le même commit que 7.6 (`fovea_splat_subsystem.gd`), avec `bone_indices`/`bone_weights`/
      `bind_pose_position` ajoutés en même temps pour ne pas reproduire l'oubli.
- [x] Tests `test/test_bone_skin_animation.gd` : pondération du binder (bone le plus proche =
      poids le plus fort, somme des poids = 1.0), no-op sur splat non riggé, translation à bone
      unique (résultat exact), blend à poids égal entre 2 bones (résultat exact).

**⚠️ Niveau de confiance — à lire avant merge** : ce fichier est le **moins fiable de tout le
batch Phase 7**. Les tests pilotent un vrai `Skeleton3D` (`set_bone_rest`, `reset_bone_pose`,
`set_bone_pose_position`, `get_bone_global_pose`, `force_update_all_bone_transforms`) d'après
la documentation Godot 4 connue, mais **aucune de ces API n'a pu être exécutée contre un
binaire Godot réel dans cet environnement** — contrairement aux autres animateurs (purement
`Vector3`/`Quaternion`/`GaussianSplat`, sans dépendance moteur), une erreur de signature ou de
sémantique de `Skeleton3D` ne sera visible qu'à l'exécution réelle des tests. **Priorité n°1
avant toute utilisation de cette phase : lancer `test_bone_skin_animation.gd` dans l'éditeur.**

**Non fait / reporté** :
- [ ] Étape 3 — Pipeline auteur (import GLB riggé → splat → binding automatique → lecture
      via `AnimationPlayer` standard) — nécessite de brancher `FoveaSplatSkinBinder.bind_splats()`
      quelque part dans le flux d'import, pas encore fait.
- [ ] Étape 4 — Hybride mesh riggé proche / splats riggés loin.
- [ ] Portage GPU du solveur cloth (`fovea_splat_cloth.gd`) pour les vêtements du personnage.
- [ ] **Portage GPU** du skinning lui-même — même remarque que 7.1-7.5, mais ici d'autant plus
      importante que le LBS par splat est l'opération la plus coûteuse de toute la Phase 7 en CPU
      (4 lookups de bone pose + 2 multiplications de transform par splat).
- [ ] Démo créature riggée + sculptable au SplatBrush VR pendant l'animation.

---

## 4. Séquencement & jalons

```
7.0 Fondation ──► 7.1 Flow ──► 7.4 Material/Stretch ──► release 0.3.0 "Living Splats"
      │
      ├─────────► 7.2 Morph Covariance ──► article de blog + release 0.4.0
      │
      ├─────────► 7.3 LAYER_ANIM/Flipbook ──► pont 4D StudioTo3D
      │
      └─────────► 7.5 Neural ──► 7.6 Bones ──► release 0.5.0 "Splat Characters"
```

**Jalons marketing** (synergie avec la publication Asset Library, cf. `ASSET_LIBRARY.md`) :

1. **0.3.0 "Living Splats"** (7.0 + 7.1 + 7.4) — GIF feuillage qui respire = visuel principal de la fiche boutique Godot.
2. **0.4.0 "Morph Covariance"** (7.2) — article technique + post r/godot + r/GaussianSplatting. C'est le moment "personne d'autre ne fait ça".
3. **0.5.0 "Splat Characters"** (7.5 + 7.6) — vidéo démo créature riggée. Candidat showcase Godot.

## 5. Risques identifiés

| Risque | Mitigation |
|---|---|
| Le tri bitonique doit re-trier chaque frame si les positions bougent | Amplitudes faibles → clés de profondeur FP16 quasi stables ; re-tri complet seulement tous les N frames + tri partiel (déjà le pattern du renderer) |
| Interpolation naïve de covariances → ellipses dégénérées | Décomposition rotation/scale obligatoire (quaternion slerp + lerp log-scale), test unitaire dédié |
| Budget VR (2 yeux, 90 Hz) | Animation fovéatée (7.4) + budget 0,5 ms mesuré au timestamp GPU dès la 7.0 |
| data3 padding limité (16 bits) | Layout documenté dès 7.0 ; buffers side-channel si dépassement |
| Compatibilité mode Compatibility/headless | Subsystem no-op propre avec gardes null (règle CLAUDE.md existante) |
