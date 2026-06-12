# 🚀 PLAN AUDACIEUX — FoveaEngine : le "Volinga de Godot" (et au-delà)

> Créé le 2026-06-12 · Objectif : amener FoveaEngine au niveau d'une offre équivalente à [Volinga](https://web.volinga.ai/) — capture → entraînement → édition → rendu temps réel de qualité production — en plugin Godot, avec des différenciateurs que Volinga n'a pas.

---

## 1. Lecture stratégique

### Ce que Volinga vend réellement
| Pilier Volinga | Description | État FoveaEngine aujourd'hui |
|---|---|---|
| **Volinga Suite** | Création/édition/préparation de modèles 3DGS, entraînement local, HDR + pipeline ACES | 🟡 StudioTo3D existe (FFmpeg → COLMAP/WorldMirror → 3DGS) mais l'entraînement dépend d'outils externes installés à la main |
| **Plugin Unreal** | Rendu 3DGS temps réel in-engine, stabilité "studio-grade" | 🟢 Renderer GPU (MultiMesh + compute culling/sort bitonique + Hi-Z) déjà en place |
| **Relighting** | Ré-éclairage des splats par les lumières de la scène | 🟡 Ombres dynamiques basiques dans le shader, pas de vrai relighting PBR |
| **Production virtuelle** | LED walls, broadcast, tracking caméra, Disguise | 🔴 Inexistant |
| **Licence commerciale, sans watermark** | Plans pro par paliers | 🔴 Pas de modèle de distribution défini |

### Notre avantage injuste (ce que Volinga n'a PAS)
1. **Foveated rendering + VR natif** — le sous-système fovéal/eye-tracking est unique au monde dans l'écosystème 3DGS.
2. **Format `.fovea` compressé** (VQ 1024, Morton order, loader Rust zero-copy) — Volinga utilise des formats plus lourds.
3. **4D / temporel** — les bridges STAR/Vista4D ouvrent les splats animés (capture vidéo → scène 4D), frontière encore quasi vierge.
4. **Open-source + Godot** — marché vide : il n'existe AUCUN équivalent Volinga sérieux sur Godot. Premier arrivé = standard de facto.
5. **Édition in-engine déjà riche** — clay deformer, cloth, brush VR, voxelizer : Volinga n'édite pas dans le moteur à ce niveau.

### La thèse audacieuse
> **Ne pas copier Volinga. Le dépasser sur Godot en 4 coups : (A) entraînement local one-click intégré, (B) qualité visuelle de référence (relighting + anti-aliasing + HDR), (C) outils de production virtuelle, (D) modèle open-core qui capture la communauté Godot avant qu'un concurrent n'existe.**

---

## 2. Les 6 phases (≈ 12 mois)

### 🏁 PHASE 0 — Fondation "Studio-Grade" (Semaines 1–6)
*Volinga vend de la stabilité avant tout. Sans elle, rien ne compte.*

- **0.1** Geler une **API publique v1** (`FoveaSplat3D` node unique, à la `VolingaActor`) : un nœud qu'on glisse dans la scène, on assigne un `.fovea`/`.ply`, ça marche. Tout le reste devient interne.
- **0.2** **Suite de tests automatisés CI** : import PLY de référence (datasets publics : garden, bicycle, truck), captures d'écran de régression, benchmarks FPS seuils (90 FPS @ 1M splats en desktop, 72 FPS en VR).
- **0.3** **Crash-proofing** : matrice de tests Forward+/Mobile/Compatibility, fallback propre sans RenderingDevice, zéro crash possible à l'activation du plugin.
- **0.4** **Packaging binaire** : builds GDExtension Rust signés Windows/Linux/macOS publiés en GitHub Releases, installation sans compilation.
- **0.5** Nettoyer le périmètre : déplacer l'expérimental (cloth, VR brush, voxelizer) dans un module `fovea_labs` optionnel. Le cœur doit être irréprochable.

**Jalon : "Drop a PLY, it just works" — démo 60 s publiable.**

---

### 🎬 PHASE 1 — Capture → Asset en un clic (Semaines 4–14) · *l'équivalent Volinga Suite*
*Le cœur de la valeur Volinga : vidéo en entrée, asset prêt-à-rendre en sortie, sans terminal.*

- **1.1** **Installateur de dépendances intégré** : le panneau StudioTo3D télécharge/installe FFmpeg, COLMAP, et un environnement Python portable (entraîneur 3DGS) automatiquement. *Zéro instruction en ligne de commande pour l'utilisateur.*
- **1.2** **Entraîneur 3DGS embarqué** : intégrer [Brush](https://github.com/ArthurBrussee/brush) (entraîneur 3DGS en Rust/WGPU — même langage que notre GDExtension !) comme backend d'entraînement par défaut. Audacieux : entraînement *dans* Godot, barre de progression dans l'éditeur, preview live du modèle en cours d'entraînement dans le viewport.
- **1.3** **Presets qualité** : Draft (5 min) / Standard (30 min) / Cinematic (2 h+), avec estimation de temps selon le GPU détecté.
- **1.4** **File d'attente de jobs** : plusieurs captures en batch, entraînement nocturne, notifications.
- **1.5** **Auto-cleanup post-entraînement** : chaîner automatiquement `FoveaSplatCleaner` (floaters, outliers, décimation) + recentrage/orientation au sol + conversion `.fovea` → l'asset arrive propre dans le FileSystem dock.
- **1.6** **Import mobile** : support des captures Polycam/Luma/Scaniverse/RealityScan (`.ply`, `.splat`, `.spz`, `.sog`) pour capter les utilisateurs existants.

**Jalon : vidéo smartphone → scène Godot navigable en < 30 min, sans quitter l'éditeur.**

---

### 💡 PHASE 2 — Qualité visuelle de référence (Semaines 10–22)
*Là où Volinga justifie ses tarifs pro : relighting, HDR, stabilité de l'image.*

- **2.1** **Mip-Splatting / anti-aliasing 3D** : filtre 3D + 2D contre l'aliasing en zoom/dézoom — différence visible immédiatement, standard de qualité 2024+.
- **2.2** **Relighting réel** :
  - Extraction de normales par splat (depuis l'axe min de covariance) + albédo désaturé de l'éclairage de capture.
  - Réception des `DirectionalLight3D`/`OmniLight3D` Godot dans le shader splat (diffus + ombres via shadow maps du moteur).
  - Mode "delit" à l'entraînement (suppression de l'éclairage cuit) — pont avec les modèles récents de relightable 3DGS.
- **2.3** **Pipeline HDR/ACES** : tonemapping ACES, exposition physique, support `Environment` Godot complet (les splats répondent au sky, fog, volumetrics).
- **2.4** **Ombres projetées PAR les splats** : injection de la profondeur splat dans les shadow maps → les objets mesh reçoivent les ombres du décor splat. Personne ne fait ça proprement dans Godot.
- **2.5** **Intégration profondeur bidirectionnelle** : les mesh Godot s'occluent correctement avec les splats (déjà amorcé via `FoveaCompositorEffect`) — finaliser, y compris transparents.
- **2.6** **Mode "Cinematic"** : tri par profondeur exact (au lieu de l'approximation temps réel), motion blur, DOF compatible — pour le rendu offline/Movie Maker mode de Godot.

**Jalon : comparaison côte à côte FoveaEngine vs Volinga/UE5 sur la même capture — indistinguable ou supérieur.**

---

### 🛠️ PHASE 3 — Édition pro in-engine (Semaines 18–28)
*Dépasser Volinga Suite : éditer DANS le moteur, pas dans un outil séparé.*

- **3.1** **Crop volumes** : boîtes/sphères/polygones de découpe en gizmos 3D natifs Godot (l'outil n°1 de Volinga). Non-destructif, animable.
- **3.2** **Suppression au pinceau** : gomme à splats 3D dans le viewport éditeur (la sélection existe déjà → ajouter le mode brush + undo/redo via `EditorUndoRedoManager`).
- **3.3** **Collisions automatiques** : `FoveaVoxelizer` → `ConcavePolygonShape3D`/heightmap en un bouton, avec LOD de collision. + génération NavMesh pour gameplay immédiat.
- **3.4** **Color grading par asset** : exposure/contrast/saturation/tint/courbes par `FoveaSplat3D`, sauvegardé dans le `.fovea`.
- **3.5** **Compositing multi-assets** : plusieurs nuages dans une scène avec tri inter-assets correct (déjà amorcé dans le manager — fiabiliser à N assets + streaming).
- **3.6** **Animation/Sequencer** : exposer crop, opacité, style, transformations à l'`AnimationPlayer` Godot → équivalent du support Sequencer de Volinga, gratuit grâce à l'architecture Godot.

**Jalon : refaire le showreel Volinga (crop + relight + séquence animée) 100 % dans Godot.**

---

### 📡 PHASE 4 — Production virtuelle & différenciateurs (Semaines 26–40)
*Le pari audacieux : attaquer le marché broadcast de Volinga, ET ouvrir des marchés que Volinga ignore.*

- **4.1** **Sortie broadcast** : plugin NDI (et SDI via Decklink si demande) pour sortir le rendu Godot vers régies/LED walls. Godot 4 + compositor le permet déjà techniquement.
- **4.2** **Camera tracking FreeD/PSN** : recevoir le tracking des caméras plateau (protocole FreeD UDP — simple à implémenter) → la killer feature production virtuelle à coût dérisoire.
- **4.3** **VR/XR fovéal — notre monopole** : démo Quest 3 / Vision Pro avec eye-tracked foveated splatting à 90 FPS sur des scènes 5M+ splats. *Aucun concurrent, Volinga compris, ne fait du 3DGS fovéal.* C'est LA démo virale.
- **4.4** **4D Gaussian Splatting** : pipeline vidéo → scène animée via les bridges STAR/Vista4D existants, lecture temporelle streamée depuis `.fovea` v2 (chunks temporels). Positionnement "volumetric video pour Godot".
- **4.5** **Streaming de mondes** : `FoveaStreamingManager` → scènes ville-échelle par chunks Morton, chargement prédictif. Cible : jeux, jumeaux numériques, immobilier.

**Jalon : 1 démo broadcast (LED wall simulé + FreeD), 1 démo VR fovéale virale, 1 démo 4D.**

---

### 🌍 PHASE 5 — Distribution, marque & modèle économique (Semaines 30–48)
*Volinga a 100+ studios. Nous avons la communauté Godot (~levier ×100 en nombre).*

- **5.1** **Open-core** :
  - **FoveaEngine Core** (MIT, Godot Asset Library) : import, rendu, crop, collisions — devient le standard 3DGS de Godot.
  - **FoveaEngine Studio** (payant, licence par siège) : entraîneur intégré, relighting avancé, 4D, broadcast/FreeD, support prioritaire. Tarif agressif sous Volinga (~49–99 €/mois vs tarifs Volinga).
- **5.2** **Site + branding** : foveaengine.com, galerie de scènes, comparateur interactif "before/after", documentation de classe (docs.foveaengine.com, MkDocs).
- **5.3** **Lancement orchestré** : démo VR fovéale sur Reddit r/godot + X + Hacker News, talk proposé au GodotCon, vidéos partenaires (créateurs YouTube Godot).
- **5.4** **Bibliothèque d'assets** : 20 scènes `.fovea` gratuites de haute qualité (capturer des lieux réels) — l'acquisition par le contenu.
- **5.5** **Programme studios pilotes** : 5 studios de production virtuelle / archviz en accès gratuit contre cas d'études et logos.
- **5.6** **Spec `.fovea` publiée** : format ouvert documenté + crate Rust standalone → adoption par l'écosystème (viewers web, outils tiers).

**Jalon : 10 000 installations Core, 50 licences Studio, FoveaEngine = réponse par défaut à "3DGS in Godot?".**

---

## 3. Synthèse du séquencement

```
Mois     1    2    3    4    5    6    7    8    9    10   11   12
PHASE 0  ████████░
PHASE 1       ░████████████░                    (Suite : one-click training)
PHASE 2                 ░██████████████░        (Relighting / HDR / AA)
PHASE 3                           ░██████████░  (Édition pro)
PHASE 4                                  ░██████████████░ (Broadcast/VR/4D)
PHASE 5                                       ░██████████████████ (Lancement)
```

## 4. KPIs de parité Volinga

| Critère | Volinga | Cible FoveaEngine |
|---|---|---|
| Vidéo → asset rendu | ✅ Suite locale | ✅ In-editor, < 30 min (M4) |
| Qualité rendu temps réel | ✅ UE5 studio-grade | ✅ 90 FPS @ 1M splats + Mip-AA (M5) |
| Relighting | ✅ | ✅ Lumières Godot natives (M6) |
| HDR/ACES | ✅ | ✅ (M6) |
| Crop/édition | ✅ Suite | ✅✚ In-engine, non-destructif (M7) |
| Sequencer | ✅ | ✅ AnimationPlayer (M7) |
| Broadcast/tracking | ✅ Disguise | ✅ NDI + FreeD (M10) |
| VR fovéal | ❌ | ✅ **monopole** (M9) |
| 4D / volumetric video | ❌ | ✅ **monopole** (M10) |
| Format compressé ouvert | ❌ | ✅ `.fovea` spec publique (M11) |
| Prix d'entrée | $$$ pro | Core gratuit + Studio < Volinga |

## 5. Risques majeurs & parades

1. **Entraînement intégré trop ambitieux** → Brush (Rust/WGPU) est le chemin le moins risqué ; fallback : wrapper gsplat/Python portable. Décision au plus tard fin Phase 0.
2. **Performance Godot vs UE5 Niagara/HLSL** → notre pipeline RenderingDevice est déjà bas niveau ; le risque est sur Mobile/Compatibility → assumer Forward+ only pour le tier "studio".
3. **Un concurrent open-source émerge sur Godot** → la parade est la vitesse : Phase 0+1 d'abord, communication publique dès le jalon "drop a PLY".
4. **Dispersion** (300 tâches backlog, modules labs) → règle stricte : tout ce qui ne sert pas le jalon de phase courant va dans `fovea_labs`.
5. **Relighting de qualité recherche** → viser le "good enough production" (normales + delit + lumières Godot), pas le papier SIGGRAPH.

---

*Ce plan complète `ROADMAP_COMPLETE_BACKLOG.md` (le « quoi » exhaustif) en fournissant le « pourquoi » et le « dans quel ordre » orientés produit/marché.*
