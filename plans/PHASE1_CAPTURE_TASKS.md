# 🎬 PHASE 1 — Capture → Asset en un clic : tâches exécutables

> Déclinaison opérationnelle de la Phase 1 de [PLAN_VOLINGA_PARITY.md](../PLAN_VOLINGA_PARITY.md) · Créé le 2026-06-15
> L'équivalent **Volinga Suite** : vidéo/photos en entrée → asset `.fovea` prêt-à-rendre en sortie, **sans terminal**.
> Jalon de sortie : **vidéo smartphone → scène Godot navigable en < 30 min, sans quitter l'éditeur.**

---

## Lecture stratégique : ce qui existe vs le verrou « zéro terminal »

Le pipeline StudioTo3D est **déjà branché de bout en bout** — mais chaque étape shell-out vers des outils **installés à la main par l'utilisateur**. C'est le seul (mais total) verrou face à Volinga.

| Brique existante | Fichier | État |
|---|---|---|
| Panneau UI StudioTo3D | `reconstruction/studio_to_3d_panel.gd` | ✅ complet (onglets, ROI, logs, bannière config) |
| Orchestrateur de phases | `reconstruction/reconstruction_manager.gd` | ✅ `run_extraction`→`run_sfm`/`run_worldmirror`→`run_training`/`run_artifixer` |
| Exécution de process | `reconstruction/reconstruction_backend.gd` | ✅ `OS.create_process` + pipes async |
| Extraction FFmpeg | `reconstruction/studio_processor.gd` | ✅ réelle |
| Bridges Python | `reconstruction/{worldmirror,diffsynth,star}_bridge.py` | ✅ |
| **Vérif** des dépendances | `reconstruction/studio_dependency_checker.gd` | ⚠️ **vérifie le PATH seulement** (`OS.execute("ffmpeg"…)`, `pip install`/`git clone` à la main) |
| **Installation** des dépendances | — | 🔴 **inexistant** |
| **Entraîneur 3DGS embarqué** | — | 🔴 dépend de WorldMirror/COLMAP+3DGS externes |
| Presets qualité / estimation temps | — | 🔴 inexistant |
| File d'attente / batch | — | 🔴 inexistant |
| Auto-cleanup → `.fovea` | `FoveaSplatCleaner` existe, **pas chaîné** | 🟠 manuel |
| Import mobile (.splat/.sog) | `ply_loader.gd` (.ply), `.spz` filtré | 🟠 partiel |

**La thèse Phase 1 :** transformer le *checker* en *installer*, embarquer un entraîneur (Brush, Rust/WGPU — même stack que notre GDExtension), et chaîner le post-traitement jusqu'au `.fovea`. Aucune ligne de commande pour l'utilisateur final.

---

## Chantier F — Installateur de dépendances « zéro terminal » (Sem. 1–4)

Le constat : `studio_dependency_checker.gd` ne fait que `OS.execute` pour tester le PATH et affiche des `pip install`/`git clone` à copier-coller (l.88–93). Volinga installe tout pour vous.

- [ ] **F1. `FoveaDependencyManager`** (`reconstruction/fovea_dependency_manager.gd`) — surcouche au-dessus du checker : pour chaque dépendance, connaître {présente?, version, chemin résolu, URL de téléchargement par OS}. Source de vérité unique consommée par le panneau.
  - ✅ *Accepté si : un seul appel rend l'état complet {ffmpeg, colmap, python, trainer} avec chemins résolus.*

- [ ] **F2. Téléchargeur intégré** — `HTTPRequest` (ou `OS.create_process` curl) + barre de progression dans le panneau pour récupérer les builds statiques : **FFmpeg** (gyan.dev win / johnvansickle linux / evermeet mac), **COLMAP** (releases GitHub), dans `user://fovea_tools/`. Vérif SHA-256 (réutiliser la logique CRC/SHA du `.fovea`).
  - ✅ *Accepté si : cliquer « Install FFmpeg » télécharge, extrait et résout le binaire sans terminal ; re-vérif passe au vert.*

- [ ] **F3. Python portable embarqué** — télécharger un Python standalone (astral `python-build-standalone`) dans `user://fovea_tools/python/`, créer un venv, `pip install` les deps du trainer (torch CPU/CUDA selon GPU détecté). Tout dans `user://`, jamais le PATH système.
  - ✅ *Accepté si : sur une machine sans Python, l'entraîneur tourne après l'installation guidée.*

- [ ] **F4. Résolution de chemins prioritaire `user://`** — `reconstruction_backend.gd` et les bridges doivent préférer les binaires de `user://fovea_tools/` au PATH système. Centraliser via `FoveaDependencyManager.resolve("ffmpeg")`.
  - ✅ *Accepté si : les outils installés par F2/F3 sont utilisés même si rien n'est dans le PATH.*

- [ ] **F5. Bannière → assistant d'installation** — la bannière non bloquante (Phase 0 B4) ouvre un panneau « Install missing tools » avec un bouton par dépendance + progression + estimation de taille.
  - ✅ *Accepté si : un nouvel utilisateur passe de « rien d'installé » à « prêt » uniquement par des clics.*

---

## Chantier G — Entraîneur 3DGS embarqué (Sem. 3–10) · *le cœur de la Suite*

Le constat : `reconstruction_manager.run_training()` (l.938) délègue à des outils externes. Il faut un entraîneur **par défaut, embarqué, observable dans l'éditeur**.

- [ ] **G1. Décision de backend (fin de chantier F)** — défaut = [**Brush**](https://github.com/ArthurBrussee/brush) (Rust/WGPU, même toolchain que notre crate `foveacore`) ; fallback = wrapper Python `gsplat`/splatfacto via le Python portable (F3). Documenter dans `docs/ARCHITECTURE.md`.
  - ✅ *Accepté si : un `.ply`/dataset COLMAP entre, un `.ply` 3DGS entraîné sort, sans WorldMirror.*

- [ ] **G2. `FoveaTrainerBackend`** (`reconstruction/fovea_trainer_backend.gd`) — interface uniforme {start(dataset, preset), signaux `progress(iter, total, psnr)`, `done(ply_path)`, `failed(msg)`, `cancel()`}. Brush et le fallback Python l'implémentent. Branché dans `run_training()`.
  - ✅ *Accepté si : `run_training` utilise le backend embarqué et émet la progression réelle.*

- [ ] **G3. Progression live dans l'éditeur** — relier `progress`/`psnr` à la `ProgressBar` + label du panneau StudioTo3D (déjà câblés pour les phases). Graphe PSNR optionnel.
  - ✅ *Accepté si : la barre et le PSNR avancent en temps réel pendant l'entraînement.*

- [ ] **G4. Preview live du modèle en cours** — checkpoints intermédiaires (`.ply` tous les N itérations) auto-chargés dans un `FoveaSplat3D` du viewport → on voit le nuage se raffiner. La démo qui vend la Suite.
  - ✅ *Accepté si : le viewport montre le modèle s'affiner pendant l'entraînement, sans recharger la scène.*

- [ ] **G5. Annulation & reprise** — bouton Cancel coupe proprement le process (pas de zombie — cf. leçon Phase 0 C4) ; reprise depuis le dernier checkpoint.
  - ✅ *Accepté si : Cancel laisse zéro process orphelin et un checkpoint réutilisable.*

---

## Chantier H — Presets, estimation, file d'attente (Sem. 8–14)

- [ ] **H1. Presets qualité** — `Draft` (~5 min) / `Standard` (~30 min) / `Cinematic` (2 h+) : itérations, résolution d'entraînement, densification, SH degree. Mappés sur `FoveaTrainerBackend`.
  - ✅ *Accepté si : choisir un preset change réellement le temps et la fidélité de sortie.*

- [ ] **H2. Détection GPU + estimation de temps** — `RenderingServer.get_video_adapter_name()` (déjà utilisé par le benchmark C6) + table d'étalonnage → ETA par preset affichée avant lancement.
  - ✅ *Accepté si : l'ETA est affichée et raisonnablement corrélée au temps réel.*

- [ ] **H3. File d'attente de jobs** — `FoveaJobQueue` : empiler plusieurs captures, exécution séquentielle (entraînement nocturne), persistance dans la session de reconstruction.
  - ✅ *Accepté si : 3 captures s'enchaînent sans intervention ; l'app peut être relancée et reprendre la file.*

- [ ] **H4. Notifications de fin** — toast éditeur + (option) son à la fin d'un job/de la file.
  - ✅ *Accepté si : l'utilisateur est notifié sans surveiller le panneau.*

---

## Chantier I — Auto-cleanup → recentrage → `.fovea` (Sem. 12–18)

Le constat : `FoveaSplatCleaner` (floaters, outliers, décimation) et le writer `.fovea` existent mais ne sont **pas chaînés** après l'entraînement. L'asset doit arriver **propre** dans le FileSystem dock.

- [ ] **I1. Pipeline de finition post-entraînement** — à `done(ply_path)` : `FoveaSplatCleaner` (outliers + floaters via SpatialHashGrid + décimation, sur le flux brut, règle zero-copy CLAUDE.md) → recentrage/orientation au sol (PCA de l'AABB) → conversion `.fovea` (writer existant) → import dans le projet.
  - ✅ *Accepté si : l'asset final est centré, nettoyé, compressé, et apparaît dans le FileSystem dock sans action manuelle.*

- [ ] **I2. Réglages de finition** — exposer agressivité du cleanup et activation du recentrage en presets (Draft = léger, Cinematic = conservateur).
  - ✅ *Accepté si : les presets H1 pilotent aussi la finition.*

- [ ] **I3. Rapport de finition** — log : nb splats avant/après cleanup, taille `.ply` vs `.fovea`, ratio de compression (réutiliser `reconstruction_metrics.gd`).
  - ✅ *Accepté si : un résumé chiffré s'affiche en fin de pipeline.*

- [ ] **I4. Bouton « Open result »** — ouvre la scène de démo (E2) pré-pointée sur le nouvel asset, ou l'instancie via l'action « Add FoveaSplat3D… » (E1).
  - ✅ *Accepté si : un clic passe de « entraînement fini » à « je navigue dans mon asset ».*

---

## Chantier J — Import mobile & SOTA (Sem. 14–18)

Le constat : `ply_loader.gd` gère `.ply`, le filtre `FoveaSplat3D` annonce `.spz` ; rien pour `.splat`, `.sog`, ni les exports Polycam/Luma/Scaniverse. Capter les utilisateurs qui ont déjà des captures.

- [ ] **J1. Loader `.splat`** (format Niantic/antimatter, 32 octets/splat) — parseur binaire → `Array[GaussianSplat]`, branché comme `ply_loader`.
  - ✅ *Accepté si : un `.splat` exporté de Luma/Polycam s'affiche via `FoveaSplat3D`.*

- [ ] **J2. Loader `.spz`** (gzip + quantifié, format Niantic) — honorer le filtre déjà déclaré. Décompression + dé-quantification → `GaussianSplat`.
  - ✅ *Accepté si : le filtre `.spz` de `FoveaSplat3D` n'est plus un mensonge.*

- [ ] **J3. Loader `.sog`/SOGS** (splat compressé WebP self-describing) — import du format compressé montant.
  - ✅ *Accepté si : un asset `.sog` se charge et se convertit en `.fovea`.*

- [ ] **J4. Détection auto à l'import** — `source_path` route vers le bon loader par extension + magic bytes (déjà fait pour `.fovea`/`.ply`).
  - ✅ *Accepté si : glisser n'importe quel format supporté « just works », sans choix manuel de loader.*

---

## Séquencement

```
Sem.  1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18
F  ████████████░
G        ░████████████████████░
H                      ░████████████░
I                              ░████████████░
J                                      ░████████████░ → 🎬 Jalon Phase 1
```

- **F bloque G/H** (pas d'entraîneur sans Python/deps installés).
- **G bloque I** (pas de finition sans sortie d'entraînement).
- **J est indépendant** — parallélisable tôt pour capter les utilisateurs existants vite.

## Définition de fin de Phase 1

1. Sur une machine vierge (ni FFmpeg, ni COLMAP, ni Python) : installer le plugin → installer les outils par clics → déposer une vidéo → obtenir un `.fovea` navigable, **sans terminal**.
2. Entraînement observable (barre + PSNR + preview live) et annulable proprement.
3. Presets Draft/Standard/Cinematic avec ETA.
4. Asset final auto-nettoyé, recentré, compressé, importé.
5. Import des formats mobiles courants (`.splat`/`.spz`/`.sog`).

---

*Complète [plans/PHASE0_FONDATION_TASKS.md](PHASE0_FONDATION_TASKS.md). Même règle de discipline : tout ce qui ne sert pas le jalon de phase courant reste hors scope (ou dans `fovea_labs`).*
