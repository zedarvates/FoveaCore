# Plan d'Amélioration : Reconstruction par Proxy-FACES (Inspiration CGMatter)

Ce document détaille l'intégration de la méthode "All models can be 1 face" (inspirée par CGMatter) au sein de **FoveaCore**. L'objectif est de pousser l'optimisation VR à son paroxysme en remplaçant la géométrie complexe par des "Proxy Faces" enrichies par du Gaussian Splatting et un Style Engine.

## 🎯 Vision & Concept

Le principe fondamental est de réduire la charge géométrique au minimum absolu (parfois un seul quad) et d'utiliser le **Style Engine** de FoveaCore pour reconstruire visuellement la complexité, les volumes et la matière.

### Comparaison des Approches
| Élément | Méthode CGMatter (Shader) | FoveaCore (Proxy-Splat/STAR) |
| :--- | :--- | :--- |
| **Géométrie** | 1 Quad / Low Poly Extrême | Proxies visibles + STAR Anchoring |
| **Reconstruction** | Shader Procédural | Splatting + DA3 Depth Maps |
| **Détails** | Simulation via Shader | STAR Spatiotemporal Cache |
| **Usage** | Rendu artistique fixe/vidéo | VR 4D Interactive & Stéréoscopie |

---

## 🛠️ Piliers Techniques

### 1. Module `ProxyFaceRenderer`
Développement d'un nouveau moteur de rendu spécialisé qui :
- Intercepte les objets désignés comme "Proxy-Ready".
- Génère/Maintient une face (ou quelques faces) orientée vers la caméra (Billboard intelligent ou Fixed Proxy).
- Injecte la couche de splats correspondante à l'objet original sur cette surface plane.

### 2. Pipeline de Génération Automatique de Proxies
Création d'un outil dans l'éditeur Godot pour :
- Analyser un mesh complexe.
- Extraire sa silhouette et ses normales principales.
- Générer un mesh proxy ultra-simplifié (LOD 0 extrême).
- Baked le "Splat-Dataset" nécessaire à sa reconstruction visuelle.

### 3. "Visible-Only Splatting" Fusionné
Optimisation du pipeline de splatting pour ne traiter que les surfaces projetées sur les proxies.
- Réduction drastique du nombre de points.
- Alignement parfait avec le frustum de l'œil en VR.
- Suppression totale des faces cachées (Back-face culling au niveau du splat).

---

## 🚀 Feuille de Route (Roadmap)

### Phase 1 : Recherche & Prototype (Preuve de Concept)
- [x] Étude de la projection de Splats sur des géométries planes (Proxy Alignment).
- [ ] Intégration du pipeline **DA3** pour générer des depth maps "world-aligned".
- [ ] Prototype de cache spatiotemporel (Inspiration InSpatio STAR) pour l'ancrage des proxies.
- [ ] Création d'un shader de base "Fake Volume" pour les quads utilisant la profondeur DA3.
- [ ] Test de perception en VR pour valider l'illusion de profondeur.

### Phase 2 : Développement du `ProxyFaceRenderer`
- [ ] Implémentation du node Godot `FoveaProxyMesh`.
- [ ] Système de bascule dynamique entre Mesh Standard et Proxy selon la distance/zone fovéale.
- [ ] Intégration avec le `LayeredSplatGenerator` existant.

### Phase 3 : Enrichissement par le Style Engine
- [ ] Ajout de filtres de stylisation (Painted look, Outline, Grain) spécifiques aux proxies.
- [ ] Gestion de la cohérence temporelle pour éviter le scintillement des splats sur les faces simplifiées.
- [ ] Support des ombres portées "fake" basées sur la profondeur du splat.

### Phase 4 : Optimisation VR & Ultimate Odyssey
- [ ] Intégration du Foveated Rendering pour ajuster la densité de reconstruction.
- [ ] Déploiement sur des éléments de décor massifs (forêts, bâtiments) dans Ultimate Odyssey.
- [ ] Tests de performance (Gain FPS cible : +40-60% sur scènes denses).

---

## 💎 Avantages pour le Projet
1. **Zéro Texture/Normal Map** : Tout est défini par la position des splats et le style engine.
2. **GPU Minimal** : Le nombre de triangles tend vers zéro, laissant toute la puissance pour le post-processing et l'IA.
3. **Esthétique Unique** : Une signature visuelle "Engine-Native" cohérente et premium.
4. **Confort VR** : Réduction de la fatigue oculaire grâce à une simplification intelligente des micro-détails géométriques instables.

> "La géométrie n'est plus une contrainte, mais un simple support pour l'illusion visuelle."
