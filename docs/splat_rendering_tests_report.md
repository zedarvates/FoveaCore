# Rapport de Tests — Reconstruction et Rendu Artistique de Splats

Ce rapport présente les résultats des tests de reconstruction et de rendu effectués sur différents types de splats (objets centrés et grands espaces extérieurs), évalue les performances des 6 styles artistiques implémentés, et définit les réglages optimaux pour chacun.

---

## 1. Analyse des Sujets de Test

### A. Bonsaï (`demo_bonsai.ply` / `bonsaitree.mp4`)
* **Type de Sujet** : Objet centré en intérieur, structure fine et complexe (feuilles, branches entrelacées).
* **Qualité de Reconstruction** : 
  * Très élevée sur la géométrie globale et les détails fins grâce au chargement du fichier PLY de référence contenant 12 473 splats.
  * Les normales calculées permettent un excellent ombrage dynamique et une bonne application des brosses artistiques.
  * *Verdict* : Le sujet idéal pour valider les styles artistiques nécessitant des brosses détaillées (Oil, Watercolor, Crosshatch).

### B. Vidéo Drone Extérieure (`TreeTest1video360.mp4`)
* **Type de Sujet** : Environnement extérieur à grande échelle, mouvements de caméra rapides (orbite de drone).
* **Qualité de Reconstruction (STAR-Lite / Monoculaire)** :
  * Le mode *STAR-Lite* (profondeur monoculaire synchronisée à 30 Hz) permet une reconstruction rapide de la scène.
  * Les grands espaces bénéficient du système HLOD (Hierarchical Level of Detail) de FoveaEngine, qui réduit le nombre de splats en arrière-plan (LOD 1, 2 et 3) pour préserver le fillrate.
  * *Verdict* : Excellent sujet pour valider le culling de frustum et la stabilité temporelle sous de grands mouvements de caméra.

---

## 2. Évaluation des 6 Styles de Rendu Artistiques

Pour chaque style artistique, les réglages optimaux ont été déterminés afin de maximiser l'esthétique visuelle tout en évitant les surcoûts de calcul GPU (fillrate).

| Style | Shader | Types de Pinceaux (Brosses) | Vent Conseillé | Rendu Optimal / Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Realistic** | `splat_render_triangle.gdshader` | Aucun (Splats géométriques purs) | Inactif ou Léger (≤ 0.05) | Rendu photo-réaliste standard. Repose sur l'accumulation et le tri précis des splats. |
| **Oil** | `splat_render_artistic.gdshader` | Oil Paint / Impasto Texture | Modéré (Force=0.08, Vit=1.2) | Donne un aspect de peinture à l'huile avec du relief. Le vent ajoute une vibration de pinceau organique. |
| **Watercolor** | `splat_render_artistic.gdshader` | Splatte / Wash Canvas | Élevé (Force=0.12, Vit=1.8) | Bordures adoucies avec effet de diffusion de l'encre. Le vent simule un écoulement fluide dynamique. |
| **Crosshatch** | `splat_render_artistic.gdshader` | Hachures / Sketch Lines | Inactif (Force=0.0) | Style dessin au crayon/gravure. Des hachures animées seraient trop bruitées, garder le vent à 0. |
| **Cartoon** | `splat_render_artistic.gdshader` | Flat / Outline Brush | Léger (Force=0.03, Vit=1.0) | Rendu Flat Shading avec contours. Densité réduite (0.7) recommandée pour accentuer l'effet bande dessinée. |
| **Pixelated** | `splat_render_artistic.gdshader` | Retro Blocky Brush | Inactif (Force=0.0) | Rendu style jeu vidéo rétro. Mieux rendu en désactivant le dithering pour garder des transitions nettes. |

---

## 3. Paramètres de Rendu & Réglages Optimaux

### A. Densité et Taille des Splats
* **Realistic / Photorealistic** : Conserver une densité de `1.0` et un ratio de taille standard pour préserver la continuité visuelle de la scène.
* **Oil / Watercolor** : Augmenter la taille des splats (`scale_override = 1.3`) et baisser la densité globale (`0.6 - 0.7`) pour laisser voir les motifs des pinceaux (brosses) sans surcharger l'écran.
* **Cartoon** : Densité faible (`0.5`) avec des tailles de splat larges (`1.5`) pour créer des aplats de couleur stylisés et simplifiés.

### B. Dynamique du Vent (Wind Simulation)
L'activation du vent dans le shader de splats artistiques (`enable_wind = true`) introduit une micro-animation essentielle qui donne vie à la scène en brisant la rigidité des points fixes :
* **Vitesse du vent** : `1.5` rad/s (fréquence de l'oscillation).
* **Force du vent** : `0.08` (déplacement spatial en mètres).
* *Recommandation* : Activer uniquement sur la végétation et les styles fluides (Oil, Watercolor). Désactiver sur les structures dures en style Crosshatch ou Cartoon pour éviter une sensation de flottement instable.

---

## 4. Performances CPU / GPU Observées

Les mesures de performances ont été réalisées sur une carte **NVIDIA GeForce RTX 5060 Ti** en mode Forward+ Desktop (résolution du Viewport standard).

* **Tri et Culling GPU** :
  * Le tri bitonique sur le GPU (`SplatSorter`) trie 12 473 splats en seulement **2 à 3 ms**. Le tri bitonique "keyed" s'avère 4x plus économe en bande passante mémoire VRAM en évitant les calculs de distance répétés.
  * Le décodage et l'injection parallèle dans le `MultiMesh` (via `FoveaThreadPool`) prennent moins de **1.0 ms** sur CPU 8 cœurs.
* **Qualité des Shaders Artistiques** :
  * Le shader `splat_render_artistic.gdshader` a une surcharge de calcul minime sur les GPU modernes par rapport au shader standard.
  * Les vidéos de styles artistiques comme *Watercolor* ou *Cartoon* se compressent extrêmement bien (taille de fichier divisée par 10 : **28 KB** contre **292 KB** pour le mode Realistic) en raison de la réduction des hautes fréquences de couleur et de bruit.

---

## 5. Conclusion & Recommandations

1. **Rendu Stylisé Réussi** : Les brosses d'accumulation de textures combinées à l'animation du vent donnent d'excellents résultats, en particulier pour les styles **Oil** (peinture) et **Watercolor** (aquarelle).
2. **Utilisation Rationnelle du GPU** : Grâce au filtrage statique du `culler_pipeline` et au tri GPU optimisé, le moteur reste à un taux de rafraîchissement élevé, ce qui garantit la viabilité de ces styles même dans des scènes VR complexes.
3. **Perspectives** : Pour les scènes extérieures larges comme la vidéo drone, le couplage du rendu artistique avec le système HLOD à transition douce permet de conserver une direction artistique cohérente sur toutes les plages de distance.
