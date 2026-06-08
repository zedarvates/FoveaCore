# 🗺️ Fovéa Engine — Backlog de Développement Intégral (235 Tâches)

Ce document présente le plan de développement complet et structuré de **Fovéa Engine**, un plugin de Gaussian Splatting (3DGS) de qualité professionnelle pour Godot Engine 4.x. Il détaille l'implémentation de A à Z, du noyau natif aux outils d'édition et à la compatibilité XR/VR.

---

## 📋 Table des Matières

1. [Architecture Globale & Noyau GDExtension (1-25)](#1-architecture-globale--noyau-gdextension-1-25)
2. [Pipeline d'Importation & Exportation (26-50)](#2-pipeline-dimportation--exportation-26-50)
3. [Système de Visualisation & Shading GPU (51-80)](#3-système-de-visualisation--shading-gpu-51-80)
4. [Culling, Tri & Streaming GPU (81-110)](#4-culling-tri--streaming-gpu-81-110)
5. [Éditeur Spatial & Outils d'Édition (111-138)](#5-éditeur-spatial--outils-dédition-111-138)
6. [Pipeline de Reconstruction StudioTo3D (139-163)](#6-pipeline-de-reconstruction-studioto3d-139-163)
7. [Intégration Godot, VR/XR & Performance (164-188)](#7-intégration-godot-vrxr--performance-164-188)
8. [Outillage, API Cloud & Tests Automatisés (189-213)](#8-outillage-api-cloud--tests-automatisés-189-213)
9. [Documentation, Roadmap & Packaging (214-235)](#9-documentation-roadmap--packaging-214-235)

---

## 1. Architecture Globale & Noyau GDExtension (1-25)

### 1.1 Structure du projet et configuration
1. **Initialisation des répertoires** : Créer l'arborescence standard du plugin sous `addons/foveacore/` (core, editor, shaders, resources, assets).
2. **Configuration du plugin** : Rédiger le fichier `plugin.cfg` définant Fovéa Engine, ses dépendances et le script d'initialisation principal.
3. **Point d'entrée de l'éditeur** : Développer `plugin.gd` pour gérer le cycle de vie du plugin, l'enregistrement des types personnalisés et l'intégration des interfaces.
4. **Singleton de gestion** : Implémenter l'Autoload `FoveaCoreManager` qui centralise les communications entre le CPU, le GPU et les outils de l'éditeur.
5. **Gestionnaire de configurations** : Créer `FoveaSettingsManager` pour stocker les préférences utilisateur et les chemins vers les outils tiers (COLMAP, FFmpeg).

### 1.2 Noyau natif et système de builds
6. **Structure GDExtension** : Configurer le projet Rust avec `Cargo.toml` et les liaisons `godot-rust/gdext` pour compiler le noyau natif.
7. **Compilation multiplateforme** : Écrire des scripts SCons/Cargo pour automatiser les builds GDExtension pour Windows, Linux et macOS (Intel/Apple Silicon).
8. **Enregistrement des classes GDExtension** : Déclarer et lier la classe native `FoveaAssetLoader` dans `src/lib.rs` pour un chargement direct sans passer par GDScript.
9. **Allocations mémoire alignées** : Implémenter en Rust des structures mémoire alignées sur 16 octets pour optimiser les transferts vers les buffers GPU.
10. **ThreadPool Natif** : Mettre en place `FoveaThreadPool` en Rust pour paralléliser les calculs CPU intensifs (comme le traitement préliminaire des octrees).

### 1.3 Communication inter-modules et Event Bus
11. **Event Bus asynchrone** : Créer `FoveaEventBus` pour découpler les modules de reconstruction, de rendu et d'édition spatiale.
12. **Mécanismes de synchronisation** : Implémenter des sémaphores et des verrous (Mutex) en Rust pour éviter les conflits d'accès aux ressources partagées.
13. **Système de journalisation unifié** : Développer un logger natif qui redirige les sorties de debug Rust et C++ vers la console d'erreur Godot.
14. **Gestionnaire de plantages** : Mettre en place des mécanismes de capture d'exceptions natifs (panic hooks en Rust) pour éviter le crash de Godot en cas d'erreur mémoire.
15. **Vérification matérielle** : Ajouter une routine de diagnostic au démarrage pour interroger le `RenderingDevice` sur le support des compute shaders requis.

### 1.4 API Publique et Bindings GDScript/C#
16. **Bindings GDScript** : Exposer les méthodes clés de chargement, de rendu et de stylisation dans l'API GDScript pour les développeurs de jeux.
17. **Bindings C#** : Générer et tester les wrappers d'API pour une intégration transparente dans les versions Godot Mono/C#.
18. **Signaux standardisés** : Définir les signaux de cycle de vie (import_started, import_completed, render_frame_ready, error_raised).
19. **Interface de bas niveau** : Permettre l'injection de nuages de points dynamiques via des tampons binaires directement accessibles en GDScript.
20. **Filtres de sécurité de l'API** : Implémenter une validation stricte des arguments en entrée des fonctions de l'API pour éviter les débordements de tampon.

### 1.5 Format propriétaire `.fovea`
21. **Spécification du format binaire** : Rédiger la structure formelle de `.fovea` (Magic Bytes, Version, Header, Tables de sauts, Données compressées).
22. **Sérialiseur natif** : Coder `FoveaAssetWriter` pour compresser et écrire les structures de splats, de style et de géométrie sous forme de fichier `.fovea`.
23. **Désérialiseur rapide** : Développer `FoveaAssetReader` capable de charger les données directement dans la mémoire alignée sans parsing textuel.
24. **Gestion des métadonnées** : Intégrer un dictionnaire JSON compressé dans le header du fichier pour sauvegarder les paramètres d'entraînement 3DGS.
25. **Compression de flux intégrée** : Ajouter le support natif de la décompression LZ4/Zstandard à la volée pendant la lecture du fichier `.fovea`.

---

## 2. Pipeline d'Importation & Exportation (26-50)

### 2.1 Parseurs de formats standards
26. **Parseur PLY Rust** : Implémenter un lecteur rapide de fichiers PLY (ASCII et Binaire Big/Little Endian) optimisé avec un parseur en streaming.
27. **Support 3DGS natif** : Développer l'importation de fichiers PLY d'entraînement 3DGS standard avec décodage des harmoniques sphériques (SH).
28. **Importation Splatfacto** : Gérer les spécificités des fichiers exportés par nerfstudio/splatfacto (orientation et mise à l'échelle spécifiques).
29. **Gestion des gros fichiers** : Optimiser la mémoire lors de l'importation de nuages de splats volumineux (plus de 10 millions de splats) via des tampons circulaires.
30. **Validation des attributs** : Écrire un outil de vérification de l'intégrité des fichiers PLY importés pour éliminer les valeurs infinies (NaN/Inf).
31. **Fallback d'importation** : Implémenter un parseur PLY écrit en GDScript pur comme alternative en cas d'absence de la bibliothèque GDExtension.

### 2.2 Processus de sérialisation et compression .fovea
32. **Quantification spatiale** : Implémenter la conversion des coordonnées XYZ flottantes 32 bits en entiers signés 16 bits basés sur l'AABB globale de l'asset.
33. **Compression vectorielle des couleurs** : Appliquer un algorithme K-Means++ en Rust pour créer une palette de 256 couleurs et encoder chaque splat sur 8 bits.
34. **Codebook de covariance** : Créer une table de covariance précalculée (codebook de 1024 entrées) pour stocker les matrices d'échelle et de rotation.
35. **Exportation progressive** : Développer un pipeline d'écriture asynchrone pour exporter les assets `.fovea` sans bloquer le thread principal de Godot.
36. **Vérification d'empreinte** : Intégrer un calcul de hachage SHA-256 dans les métadonnées pour vérifier l'intégrité de l'asset après transfert.
37. **Outil de re-compression** : Créer un script d'optimisation permettant de re-compresser un fichier `.fovea` existant avec des ratios plus agressifs.

### 2.3 Algorithmes de conversion Splats vers Mesh
38. **Barycentres géométriques** : Implémenter `SurfaceExtractor.gd` pour extraire des sommets de maillage à partir des positions des splats les plus denses.
39. **Triangulation de Delaunay 3D** : Écrire un algorithme de triangulation spatiale pour interconnecter les points extraits en triangles réguliers.
40. **Projection de textures** : Développer un outil pour projeter les couleurs et harmoniques sphériques des splats sur les coordonnées UV du maillage généré.
41. **Simplification de maillage** : Intégrer un décimateur de triangles (Quadric Error Metrics) pour réduire la complexité géométrique du maillage résultant.
42. **Calcul des normales** : Implémenter la génération automatique de normales lisses (smooth normals) adaptées aux shaders de rendu standards.
43. **Vérification des volumes fermés** : Développer un filtre pour s'assurer que le maillage extrait ne présente pas de trous de géométrie (non-manifold).

### 2.4 Algorithmes de conversion Mesh vers Splats
44. **Échantillonnage de surface** : Écrire un générateur procedural qui échantillonne uniformément la surface d'un `MeshInstance3D` avec des points de distribution.
45. **Génération de splats par triangle** : Convertir les sommets de triangles en splats en calculant le rayon de couverture en fonction de l'aire du triangle.
46. **Transfert de normales** : Aligner l'axe d'échelle minimal de chaque splat généré avec la normale locale de la surface du triangle.
47. **Échantillonnage de texture** : Lire les coordonnées UV de la texture d'albedo du mesh pour attribuer les couleurs diffuses aux splats correspondants.
48. **Génération d'harmoniques sphériques basiques** : Initialiser les harmoniques sphériques d'ordre 0 et 1 pour simuler une réflexion diffuse simple.
49. **Distribution volumétrique** : Implémenter un mode d'échantillonnage interne (volume sampling) pour remplir l'intérieur d'un mesh fermé avec des splats semi-transparents.
50. **Validation géométrique** : Mesurer l'erreur de distance de Hausdorff entre le mesh d'origine et le nuage de splats généré pour valider la fidélité.

---

## 3. Système de Visualisation & Shading GPU (51-80)

### 3.1 Architecture du Renderer et RenderingDevice
51. **Pipeline de rendu bas niveau** : Configurer les buffers et pipelines de rendu via le `RenderingDevice` de Godot dans `FoveaSplatRenderer`.
52. **Gestion des SSBO** : Mettre en place les Shader Storage Buffer Objects (SSBO) pour stocker les positions, échelles, rotations et couleurs des splats sur le GPU.
53. **Double-Buffering GPU** : Implémenter un mécanisme de double-buffering pour les données de rendu afin d'éviter les attentes de synchronisation GPU-CPU.
54. **Injection dans l'effet composite** : Intégrer le rendu des splats dans l'architecture `CompositorEffect` de Godot 4.3 pour un rendu post-opaque correct.
55. **Gestion de la mémoire VRAM** : Développer un allocateur de pools VRAM pour réutiliser les buffers de splats sans instanciations répétées.

### 3.2 Shaders de rendu et projection 2D
56. **Calcul de covariance 2D** : Coder les formules mathématiques EWA (Elliptical Weighted Average) pour projeter les ellipses 3D sur le plan image 2D du shader.
57. **Fragment Shader Gaussien** : Implémenter l'évaluation de la fonction exponentielle gaussienne par pixel pour obtenir des bords de splats adoucis.
58. **Gestion des Harmoniques Sphériques** : Écrire les fonctions GLSL pour évaluer les SH d'ordre 1, 2 et 3 en fonction du vecteur de vue caméra.
59. **Transparence et Blending** : Configurer les états de blending de l'API de rendu de Godot (Alpha Blend, Additive) pour éliminer les artefacts d'empilement.
60. **Intégration d'ombres dynamiques** : Adapter le shader pour qu'il reçoive les cartes d'ombres (Shadow Maps) de Godot et assombrisse les splats en conséquence.

### 3.3 Shaders artistiques et stylisation
61. **Shader Peinture à l'huile** : Créer un shader de postérisation et de distorsion basé sur un bruit de Kuwahara pour donner un effet de pinceau.
62. **Shader Aquarelle** : Implémenter un shader simulant la diffusion des pigments d'aquarelle avec assombrissement des bords des splats.
63. **Shader de hachures (Crosshatch)** : Développer un shader de rendu triplanaire qui applique des motifs de hachures selon la luminosité reçue.
64. **Shader Manga / Cell Shading** : Coder un rendu avec contours d'encre (edge detection) et aplats de couleurs stylisés pour les scènes animées.
65. **Moteur d'animation de style** : Implémenter `StyleEngine.gd` pour interpoler dynamiquement les paramètres de shaders artistiques.

### 3.4 Shaders de particules fluides (Water Splats)
66. **Compute Shader de physique fluide** : Écrire un simulateur d'advection et de gravité pour déplacer les splats de type liquide sur le GPU.
67. **Détection de collisions locale** : Implémenter des tests de collision simplifiés contre une grille de hauteur (Heightmap) ou des boîtes de collision (AABB).
68. **Shader d'écoulement (Flow Mapping)** : Développer un shader utilisant des vecteurs de flux peints pour animer la direction du mouvement des splats fluides.
69. **Cycle de vie des particules** : Gérer la naissance, le vieillissement (decay d'opacité) et le recyclage des splats de particules dans les buffers GPU.
70. **Rendu de réfraction fluide** : Implémenter une déformation de l'écran en arrière-plan des splats fluides pour simuler l'indice de réfraction de l'eau.

### 3.5 Niveaux de détail (LOD) et MIP-Splatting
71. **Calculateur de LOD dynamique** : Développer une routine qui évalue la distance caméra-splat et assigne un index LOD par frame.
72. **Génération de MIP-Splats** : Regrouper les splats adjacents dans des structures d'octree pour créer des niveaux de détail simplifiés.
73. **Interpolation inter-LOD** : Implémenter un cross-fade temporel pour éviter le pop visuel lors du changement de niveau de détail d'un asset.
74. **LOD basé sur la vélocité** : Adapter la densité de rendu en fonction de la vitesse de déplacement de la caméra (Kinematic LOD) pour préserver le framerate.
75. **Culling LOD agressif** : Désactiver le rendu des micro-splats lorsque leur taille projetée à l'écran est inférieure à un demi-pixel.

### 3.6 Debug View et profilage visuel
76. **Debug de densité** : Créer un mode de rendu affichant la densité des splats par unité de volume sous forme de gradient de couleur (chaud/froid).
77. **Debug d'octree spatial** : Dessiner les boîtes englobantes (AABB) de l'octree dans le viewport 3D pour visualiser le découpage spatial.
78. **Visualisation des vecteurs normaux** : Afficher de courtes lignes colorées représentant la direction normale de chaque splat pour le debug géométrique.
79. **Debug de performance à l'écran** : Intégrer un overlay affichant en temps réel le framerate, le temps GPU de tri, le nombre de splats affichés et rejetés.
80. **Debug d'overdraw** : Implémenter une vue cumulative de la transparence pour localiser les zones de forte superposition de splats (goulots d'étranglement).

---

## 4. Culling, Tri & Streaming GPU (81-110)

### 4.1 Frustum Culling CPU et GPU
81. **Culling Frustum CPU** : Implémenter `EyeCuller.gd` en utilisant l'AABB globale de l'asset pour exclure les objets entièrement hors du champ de vision.
82. **Compute Shader de Culling** : Écrire `gpu_culling_compute.glsl` pour éliminer individuellement chaque splat situé en dehors du frustum de la caméra.
83. **Optimisation par projection de plans** : Utiliser les équations de plans de frustum normalisés pour accélérer les tests de culling dans le compute shader.
84. **Indexation indirecte** : Écrire les index des splats visibles dans un buffer de visibilité compacté pour éviter de traiter les splats invisibles lors du tri.
85. **Culling directionnel** : Éliminer les splats dont l'échelle principale pointe à l'opposé de la direction de la caméra (Backface Culling de splat).

### 4.2 Occlusion Culling Hi-Z
86. **Génération de la pyramide Hi-Z** : Configurer un pipeline pour générer une texture mipmapée de profondeur (Hi-Z buffer) à partir du depth buffer opaque de Godot.
87. **Test d'occlusion GPU** : Dans le compute shader de culling, tester la boîte englobante de chaque splat contre le niveau mipmap approprié du buffer Hi-Z.
88. **Optimisation de la bande passante** : Réduire la résolution de la pyramide Hi-Z pour limiter les lectures de textures non-cohérentes sur le GPU.
89. **Culling conservateur** : S'assurer que le test Hi-Z ne rejette pas par erreur des splats partiellement visibles en raison de mips trop grossières.
90. **Mise à jour entrelacée du Hi-Z** : Mettre à jour la pyramide Hi-Z une frame sur deux pour économiser du temps de calcul sur le GPU.

### 4.3 Algorithmes de Tri GPU Bitonic
91. **Shader de tri bitonique** : Implémenter le tri bitonique parallèle dans `sort_bitonic_keyed.glsl` pour trier les splats selon leur profondeur.
92. **Précalcul des clés de profondeur** : Écrire un compute shader d'initialisation qui calcule la projection en profondeur (Z-depth) de chaque splat.
93. **Optimisation des swaps mémoire** : Réduire le nombre d'écritures VRAM dans le shader de tri en utilisant des variables de registre de thread locales.
94. **Tri par clés FP16** : Encoder la clé de profondeur en demi-précision (float16) pour diviser par deux la bande passante requise pour les comparaisons.
95. **Gestion des tailles dynamiques** : Adapter l'algorithme de tri bitonique pour qu'il prenne en charge des nombres de splats non-puissances de 2.

### 4.4 Tri temporel et entrelacé
96. **Tri entrelacé** : Répartir les étapes du tri bitonique sur plusieurs frames consécutives (tri étalé sur 2 ou 4 images) pour lisser les pics de framerate.
97. **Détection de mouvement de caméra** : Mesurer le déplacement de la caméra et forcer un tri complet uniquement si la caméra tourne de manière significative.
98. **Cohérence temporelle** : Réutiliser l'ordre de tri de la frame précédente comme point de départ pour réduire le nombre d'itérations de tri nécessaires.
99. **Coefficients d'amortissement** : Implémenter un fondu d'opacité dynamique pour masquer les splats mal triés pendant les rotations rapides de caméra.
100. **Contrôle de latence** : Assurer que la latence introduite par le tri entrelacé n'affecte pas l'expérience utilisateur, particulièrement en VR.

### 4.5 Pipeline de Streaming out-of-core
101. **Découpage spatial par grille** : Diviser les scènes géantes en chunks cubiques de taille fixe (par exemple 16x16x16 mètres).
102. **Calcul de priorité de streaming** : Évaluer en continu la distance et le vecteur de regard de la caméra pour trier les chunks à charger en priorité.
103. **Requêtes de chargement asynchrones** : Envoyer des requêtes non bloquantes au thread Rust pour charger les données de splats depuis le disque.
104. **Gestion de budget VRAM (LRU)** : Implémenter un cache de type Least Recently Used pour décharger de la VRAM les chunks les plus éloignés de la caméra.
105. **Repopulation progressive des buffers** : Injecter les nouvelles données de splat chargées dans les SSBO GPU de manière fragmentée pour éviter les saccades.

### 4.6 Instanciation globale et GPU Indirect Draw
106. **Gestionnaire d'instances globales** : Développer `FoveaSplatDispatcher` pour regrouper tous les assets splat de la scène dans un unique buffer géant.
107. **GPU Driven Rendering** : Éliminer les appels système CPU en utilisant des buffers d'arguments d'affichage indirect (Indirect Draw buffers).
108. **Instanciation de masse** : Permettre d'afficher des milliers de copies du même asset (ex. arbres, herbe) avec une seule copie en mémoire VRAM.
109. **Variation d'instance locale** : Ajouter un tableau de transformation et de couleur par instance dans le shader pour modifier chaque copie individuellement.
110. **Synchronisation indirecte** : Configurer des barrières mémoire GPU pour coordonner le compute shader de culling et le shader d'affichage indirect.

---

## 5. Éditeur Spatial & Outils d'Édition (111-138)

### 5.1 Outils de sélection spatiale
111. **Sélection par lasso** : Développer un outil permettant à l'utilisateur de tracer une ligne fermée à l'écran pour sélectionner les splats contenus dans le cône de vue.
112. **Raycasting de splats** : Implémenter un algorithme de détection de collision rayon-splat optimisé par octree pour sélectionner des éléments individuels.
113. **Sélection volumétrique** : Créer des outils de sélection par volume (boîte englobante, sphère d'influence) ajustables dans le viewport 3D.
114. **Filtrage de sélection** : Permettre de filtrer la sélection actuelle selon des critères d'attributs (couleur proche, opacité faible, échelle extrême).

### 5.2 Outils de transformation et Gizmos
115. **Gizmos de translation** : Intégrer des axes interactifs dans le viewport pour déplacer les splats sélectionnés selon les coordonnées locales ou globales.
116. **Gizmos de rotation et d'échelle** : Implémenter des anneaux de rotation et des poignées d'échelle agissant sur le centroïde de la sélection.
117. **Sélection douce (Soft Selection)** : Ajouter un rayon d'atténuation (falloff) pour déformer progressivement les splats voisins non sélectionnés.
118. **Alignement sur la grille** : Coder une fonction pour aligner les positions des splats sélectionnés sur la grille 3D de l'éditeur Godot.

### 5.3 Outils de duplication et instanciation
119. **Duplication directe** : Permettre la copie rapide des splats sélectionnés avec décalage de position ajustable.
120. **Instanciation liée** : Créer un mécanisme pour lier des groupes de splats dupliqués afin que toute modification sur l'un soit répercutée sur les autres.
121. **Duplication le long d'une courbe** : Coder un outil pour distribuer automatiquement des instances de splats le long d'un node `Path3D`.
122. **Variations aléatoires** : Ajouter des curseurs pour introduire des variations aléatoires (teinte de couleur, échelle, rotation) lors de la duplication en série.

### 5.4 Nettoyage automatique des Splats
123. **Filtre de bruit spatial** : Implémenter un filtre statistique de suppression des points aberrants isolés (floaters) basé sur la distance moyenne aux voisins.
124. **Seuillage d'opacité** : Créer un outil automatique pour supprimer les splats dont l'opacité est inférieure à un seuil défini (ex. < 0.05).
125. **Filtrage par taille** : Détecter et supprimer les splats anormalement grands qui masquent le reste de la scène de manière inesthétique.
126. **Nettoyage des bordures** : Développer un algorithme de détection de contours pour lisser les bords déchiquetés d'une zone de reconstruction.

### 5.5 Outils de fusion, découpe et fusion coplanaire
127. **Plan de coupe interactif** : Coder un outil permettant de trancher un nuage de splats en utilisant un plan 3D manipulable.
128. **Fusion de nuages de splats** : Permettre de fusionner deux ressources `.fovea` distinctes en recalculant leurs repères spatiaux locaux.
129. **Extraction de sous-selection** : Sauvegarder la sélection actuelle dans une nouvelle ressource `.fovea` indépendante en extrayant les données.
130. **Fusion coplanaire (Optimization)** : Implémenter `FoveaSplatCleaner.merge_coplanar()` pour regrouper les splats alignés et les fusionner en un splat unique.

### 5.6 SplatBrush (Pinceau d'édition)
131. **Architecture du pinceau** : Implémenter le node `FoveaSplatBrush` gérant le rayon d'action, la force d'application et le profil de pinceau.
132. **Mode Peinture de couleur** : Permettre de peindre directement de nouvelles couleurs sur les splats existants avec mélange de teintes ajustable.
133. **Mode Gomme** : Développer un mode d'effacement progressif réduisant l'opacité des splats sous le pinceau jusqu'à leur suppression.
134. **Mode Déformation (Sculpt)** : Pousser ou tirer la position des splats dans le rayon du pinceau pour corriger des erreurs géométriques de reconstruction.

### 5.7 Reprojection et Baking de lumière
135. **Baking d'ombres portées** : Calculer et figer (bake) les ombres de la scène dans l'attribut de couleur diffuse de chaque splat.
136. **Baking de l'occlusion ambiante** : Estimer l'occlusion ambiante locale par splat et l'appliquer comme facteur d'atténuation de luminosité.
137. **Reprojection d'images de référence** : Aligner et projeter des photographies haute définition sur des splats mal définis pour restaurer du détail.
138. **Baking d'illumination globale (GI)** : Capturer la lumière indirecte des VoxelGI ou LightmapGI de Godot et l'encoder dans les harmoniques sphériques.

---

## 6. Pipeline de Reconstruction StudioTo3D (139-163)

### 6.1 Extraction vidéo et détection de flou
139. **Intégration FFmpeg** : Implémenter dans `StudioProcessor.gd` l'extraction de trames d'images à partir de fichiers vidéo via des appels système FFmpeg asynchrones.
140. **Contrôle du framerate d'extraction** : Permettre à l'utilisateur de spécifier le nombre d'images à extraire par seconde de vidéo (ex. 2 fps, 5 fps).
141. **Détection de flou par Laplacien** : Coder l'algorithme de calcul de la variance du Laplacien pour estimer le flou de bougé de chaque trame.
142. **Filtrage automatique des images** : Éliminer les trames trop floues ou trop sombres du jeu d'images final pour optimiser le calcul SfM.
143. **Rapport de qualité** : Générer un fichier log listant les trames conservées, rejetées et le score de qualité moyen de la capture vidéo.

### 6.2 Outil de détourage et masquage d'arrière-plan
144. **Génération de masques d'arrière-plan** : Développer un pipeline pour créer des masques binaires (noir/blanc) isolant le sujet principal.
145. **Seuillage de couleur (Chroma Key)** : Implémenter un outil de détourage basé sur la détection de couleurs d'arrière-plan uniformes (fond vert/bleu).
146. **Prévisualisation en temps réel** : Afficher instantanément le résultat du masquage sur l'image sélectionnée lors du changement des paramètres.
147. **Exportation des masques pour COLMAP** : Enregistrer les masques générés au format PNG dans un répertoire structuré attendu par le moteur SfM.

### 6.3 Définition visuelle de la Région d'Intérêt (ROI)
148. **Panneau de sélection ROI** : Créer un outil de dessin de rectangle (Bounding Box 2D) sur la première trame vidéo pour définir la zone utile.
149. **Outil Lasso ROI** : Développer un outil de dessin à main levée pour définir des formes complexes de découpage de la zone de reconstruction.
150. **Coordonnées normalisées** : Convertir les coordonnées de la ROI dessinée en pixels absolus selon la résolution native de la vidéo.
151. **Application temporelle** : Étendre le découpage ROI sur l'ensemble de la séquence d'images extraite en conservant les proportions.

### 6.4 Moteurs SfM (Structure from Motion)
152. **Gestionnaire de processus COLMAP** : Implémenter l'exécution asynchrone des commandes d'extraction de caractéristiques et de mise en correspondance.
153. **Pont WorldMirror 2.0** : Intégrer `worldmirror_bridge.py` pour lancer une reconstruction rapide sans pose via un modèle de diffusion.
154. **Intégration Déjà View (DVLT)** : Connecter le backend DVLT via le script de liaison DiffSynth pour raffiner la géométrie en K étapes.
155. **Suivi de progression SfM** : Parser le flux de sortie standard (stdout) des processus SfM pour mettre à jour la barre de progression de l'éditeur.

### 6.5 Pipeline d'entraînement 3DGS
156. **Script d'entraînement 3DGS** : Développer un gestionnaire pour lancer l'entraînement Python de Gaussian Splatting (3000 à 30 000 itérations).
157. **Allocation dynamique des ressources CUDA** : Configurer les arguments système pour limiter l'utilisation VRAM de l'entraînement selon le GPU de l'utilisateur.
158. **Surveillance des métriques d'apprentissage** : Lire et afficher en temps réel les valeurs de perte (L1 Loss, SSIM) pendant l'entraînement.
159. **Exportation automatique du PLY final** : Copier le fichier PLY généré à l'issue de l'entraînement vers le dossier de ressources Godot.

### 6.6 Session et gestion d'état
160. **Sérialisation de session** : Implémenter la sauvegarde de l'état complet de la reconstruction (`ReconstructionSession`) dans un fichier JSON local.
161. **Restauration de session** : Permettre de reprendre une reconstruction interrompue en rechargeant l'état JSON et les fichiers temporaires existants.
162. **Nettoyage automatique du cache** : Supprimer les fichiers temporaires volumineux (images de travail, bases de données intermédiaires) après réussite de l'importation.
163. **Gestion des erreurs matérielles** : Intercepter les pannes CUDA (Out Of Memory) et suggérer des résolutions (réduction de résolution, sous-échantillonnage).

---

## 7. Intégration Godot, VR/XR & Performance (164-188)

### 7.1 Nodes personnalisés (FoveaSplatNode)
164. **Création de la classe principale** : Développer `FoveaSplatNode` héritant de `VisualInstance3D` pour s'intégrer proprement dans l'arbre de scène Godot.
165. **Gestion des transformations spatiales** : Synchroniser la matrice de transformation locale (Node3D transform) avec les buffers de rendu GPU.
166. **Support des calques de rendu** : Permettre d'assigner le node de splat à des calques de rendu (Visual Layers) spécifiques de Godot.
167. **Détection de visibilité caméra** : Connecter l'événement `visibility_changed` pour couper le rendu et libérer la bande passante si le node est masqué.

### 7.2 Ressources Godot (FoveaSplatResource)
168. **Classe de Ressource personnalisée** : Implémenter `FoveaSplatResource` héritant de `Resource` pour gérer les données de splats sauvegardées.
169. **Gestionnaire d'importation Godot** : Créer `EditorImportPlugin` pour que Godot traite automatiquement les fichiers `.fovea` et `.ply` comme des ressources valides.
170. **Sauvegarde personnalisée** : Implémenter l'écriture des fichiers ressources dans les formats natifs de Godot (`.tres` ou `.res`) pour la persistance des données.
171. **Gestion des dépendances internes** : Enregistrer le shader et le style par défaut comme dépendances de la ressource de splats.

### 7.3 Interface Inspecteur et Panels personnalisés
172. **Custom Editor Inspector** : Développer un plugin d'inspecteur Godot pour proposer une interface utilisateur ergonomique lors de la sélection du Node.
173. **Contrôles de shader interactifs** : Ajouter des curseurs, des roues de couleurs et des boutons radio pour modifier à chaud les paramètres esthétiques.
174. **Visualiseur de ressources d'albedo** : Afficher une vignette 2D de la palette de couleurs générée ou de la texture de covariance dans l'inspecteur.
175. **Bouton d'action rapide** : Ajouter un bouton "Optimiser l'Asset" directement dans l'inspecteur pour exécuter la fusion coplanaire sans ouvrir de menu.

### 7.4 Intégration OpenXR et VR Rig
176. **Initialisation OpenXR** : Développer `FoveaXRInitializer.gd` pour activer et configurer l'interface OpenXR au lancement de l'application.
177. **Support du rendu Stéréo** : Adapter le compute shader de tri et de culling pour traiter simultanément les caméras de l'œil gauche et de l'œil droit.
178. **Optimisation Single-Pass Instancing** : Configurer le shader pour afficher les splats dans les deux yeux en un seul appel de dessin (draw call) pour soulager le CPU.
179. **VR Rig de démonstration** : Concevoir le template de scène `fovea_vr_rig.tscn` contenant les nodes `XROrigin3D`, `XRCamera3D` et les contrôleurs.

### 7.5 Foveated Rendering & Variable Rate Shading (VRS)
180. **Suivi oculaire (Gaze Tracking)** : Connecter le plugin aux extensions OpenXR `XR_EXT_eye_gaze_interaction` pour récupérer l'orientation du regard.
181. **Générateur de texture VRS** : Créer une texture de shading dynamique dont la résolution décroît de manière concentrique à partir du point de regard.
182. **Culling fovéal** : Intégrer l'angle de regard dans le compute shader de culling pour réduire la densité des splats dans la périphérie de vision.
183. **Ajustement LOD fovéal** : Augmenter la taille des splats en périphérie de champ de vision pour masquer la perte de détails due au LOD inférieur.

### 7.6 Contrôleurs XR & Haptique
184. **Cartographie d'actions XR** : Configurer le fichier `xr_action_map.tres` pour assigner les boutons des contrôleurs (Oculus, Index, HTC).
185. **Interactions spatiales en VR** : Implémenter la sélection et la manipulation des splats dans l'espace 3D à l'aide des faisceaux des contrôleurs (Raycasts).
186. **Haptique de peinture** : Déclencher des impulsions haptiques modulées sur la manette lorsque l'utilisateur applique de la matière avec le SplatBrush.
187. **Menu VR flottant** : Concevoir une interface utilisateur 3D projetée dans l'espace (CanvasLayer3D) pour contrôler le plugin sans retirer le casque.
188. **Fallback Desktop VR** : Implémenter un mode émulateur de casque VR utilisant les touches du clavier et la souris pour simplifier le debug sur PC.

---

## 8. Outillage, API Cloud & Tests Automatisés (189-213)

### 8.1 CLI Converter autonome
189. **Outil en ligne de commande Rust** : Compiler un binaire autonome `fovea-converter` pour Windows, Linux et macOS.
190. **Conversion en lot (Batch)** : Permettre de convertir tout un répertoire de fichiers `.ply` en `.fovea` en une seule ligne de commande.
191. **Arguments de conversion** : Gérer les options en ligne de commande pour spécifier le niveau de compression, la quantification et la ROI.
192. **Intégration dans le pipeline CI/CD** : Rédiger un fichier d'exemple pour intégrer le convertisseur dans des pipelines automatisés (GitHub Actions).

### 8.2 Générateur de previews et vignettes
193. **Capture d'écran automatique** : Créer un outil qui positionne une caméra virtuelle autour de l'asset splat et prend un cliché de rendu opaque.
194. **Génération de vignettes animées** : Créer de courtes séquences GIF ou WebP montrant l'asset splat en rotation pour un aperçu rapide dans l'éditeur.
195. **Thumbnails Godot FileSystem** : Intégrer le générateur de preview avec le système de vignettes natif de l'explorateur de fichiers de Godot.
196. **Génération asynchrone** : S'assurer que le calcul des previews s'effectue en tâche de fond pour ne pas figer l'interface de l'éditeur de fichiers.

### 8.3 Ponts IA (ComfyUI, Auto-ROI local via ONNX)
197. **Pont réseau ComfyUI** : Coder `neural_style_bridge.gd` pour communiquer en HTTP/WebSocket avec une instance ComfyUI locale ou distante.
198. **Envoi de requêtes de génération** : Envoyer des images de référence et des prompts pour générer des textures artistiques de splats via Stable Diffusion.
199. **ONNX Runtime natif** : Intégrer le support de chargement de modèles ONNX via GDExtension pour exécuter des calculs IA locaux.
200. **Auto-Segmentation d'arrière-plan** : Utiliser un modèle de segmentation (comme MobileNet) au format ONNX pour détourer le sujet principal sans cloud.

### 8.4 Benchmarks de performance automatisés
201. **Outil d'évaluation des performances** : Implémenter un script exécutable qui instancie des scènes de complexités croissantes (1M, 5M, 10M de splats).
202. **Mesure de framerate et frame time** : Enregistrer de manière précise les temps de rendu GPU et les goulets d'étranglement de tri par frame.
203. **Exportation des résultats de test** : Sauvegarder les métriques du benchmark sous la forme de fichiers structurés JSON et CSV.
204. **Graphique de performances intégré** : Développer un panneau affichant un graphique comparatif des performances selon les différentes versions du plugin.

### 8.5 Framework de tests unitaires et intégration
205. **Tests unitaires GDScript** : Rédiger des tests de validation pour s'assurer que les calculs de conversion géométrique renvoient des résultats précis.
206. **Tests de charge mémoire** : Écrire des scénarios vérifiant l'absence de fuites de mémoire (memory leaks) lors du chargement répété d'assets.
207. **Tests d'intégration de scènes** : Valider que l'ajout, la modification et la suppression de nodes dans l'arbre de scène Godot s'effectuent sans erreur.
208. **Mocks de périphériques de rendu** : Écrire un système d'émulation pour simuler la présence de compute shaders sur des machines de test headless.

### 8.6 Tests de non-régression visuelle
209. **Capture et comparaison d'images** : Coder un utilitaire comparant pixel à pixel une capture de rendu de splats avec une image de référence validée.
210. **Calcul de l'indice SSIM local** : Implémenter la comparaison SSIM (Structural Similarity) pour valider que le rendu stylisé reste conforme.
211. **Détection d'artefacts visuels** : Signaler automatiquement l'apparition de pixels aberrants (NaNs ou couleurs extrêmes) dans les images de test.
212. **Tests multi-résolutions** : Valider la stabilité du tri et de l'affichage sur des résolutions allant du 720p au double écran VR 4K.
213. **Automatisation du pipeline de test** : Lancer l'ensemble de la suite de tests à chaque modification du dépôt Git via des Webhooks locaux.

---

## 9. Documentation, Roadmap & Packaging (214-235)

### 9.1 Guides utilisateurs
214. **Guide de démarrage rapide** : Écrire `manual_installation.md` pour guider l'utilisateur de l'installation du plugin à sa première scène 3D.
215. **Manuel d'édition spatiale** : Rédiger un guide sur l'utilisation du pinceau SplatBrush, des sélections volumétriques et des outils de nettoyage.
216. **Guide du pipeline StudioTo3D** : Expliquer pas à pas comment filmer un objet, configurer la reconstruction SfM et générer l'asset.
217. **Optimisation pour la réalité virtuelle** : Rédiger un document détaillant les meilleures configurations de projet pour optimiser Fovéa Engine en VR.

### 9.2 Guides de développement et API Reference
218. **Manuel d'architecture interne** : Rédiger `plans/foveacore-architecture.md` détaillant le fonctionnement interne du culling et du tri GPU.
219. **Guide de compilation native** : Expliquer comment configurer son environnement de dev (Rust, SCons, compilateurs) pour recompiler la GDExtension.
220. **Documentation des shaders** : Documenter les paramètres exposés des shaders d'anisotropie, d'art et de particules fluides.
221. **Générateur automatique d'API** : Utiliser un script pour générer un fichier d'API de référence au format Markdown à partir des docstrings de code.

### 9.3 Scènes d'exemples et templates de projets
222. **Scène Galerie Artistique** : Fournir une scène d'exemple pré-configurée mettant en avant les différents styles artistiques et shaders de stylisation.
223. **Projet Exemple VR** : Livrer un template de projet Godot configuré pour OpenXR, contenant le rig de caméra VR et des interactions physiques basiques.
224. **Assets de démonstration** : Inclure deux fichiers `.fovea` de haute qualité et libres de droits pour permettre aux nouveaux utilisateurs de tester le rendu.
225. **Template de reconstruction par turntable** : Fournir un modèle de configuration de capture vidéo et un script d'automatisation d'extraction.

### 9.4 Optimisations mobiles et portage WebAssembly/WebGPU
226. **Compatibilité Vulkan Mobile** : Adapter les compute shaders pour se conformer aux limitations de bande passante et de registres des puces mobiles ARM.
227. **Optimisations Meta Quest 3** : Configurer des préréglages graphiques optimisés pour le matériel VR autonome, ciblant une fréquence d'affichage stable de 90 Hz.
228. **Compilation WebAssembly** : Configurer la chaîne de compilation Rust pour cibler WASM, permettant au code natif de Fovéa Engine de tourner sur le web.
229. **Portage WGSL (WebGPU)** : Réécrire les shaders GLSL de tri et de rendu en format WGSL pour assurer la compatibilité avec le renderer WebGPU de Godot.
230. **Optimisation d'autonomie énergétique** : Réduire le nombre de dispatches GPU sur mobile en désactivant le tri sur les objets statiques lorsque la caméra ne bouge pas.

### 9.5 Packaging, CI/CD et publication Godot Asset Library
231. **Vérification réglementaire de licence** : Ajouter les fichiers de licence (MIT/Apache) et s'assurer que toutes les dépendances open-source sont créditées.
232. **Script de packaging automatique** : Écrire un script Python qui extrait uniquement les fichiers nécessaires au plugin (en excluant les sources C++/Rust et tests).
233. **Configuration CI/CD GitHub Actions** : Automatiser la création de releases Git contenant les binaires GDExtension précompilés pour toutes les plateformes.
234. **Soumission à la Godot Asset Library** : Préparer la fiche de soumission avec descriptions, captures d'écran, tags pertinents et lien vers le dépôt.
235. **Publication finale** : Soumettre et valider la publication du package Fovéa Engine sur la bibliothèque officielle d'assets de Godot.

---

## 🚀 Conclusion & Roadmap Finale

Ce backlog de **235 tâches précises et actionnables** constitue la feuille de route exhaustive pour le développement de Fovéa Engine de A à Z. 

### Étapes clés de validation :
- **Milestone 1 (MVP)** : Validation de l'import PLY natif en Rust, affichage avec le shader d'anisotropie et tri bitonique opérationnel.
- **Milestone 2 (StudioTo3D)** : Pipeline complet vidéo -> trames -> masques -> SfM -> entraînement -> format `.fovea` intégré à l'éditeur Godot.
- **Milestone 3 (VR/XR & Optimisation)** : Support complet d'OpenXR avec suivi oculaire, rendu stéréo single-pass, et streaming out-of-core.
- **Milestone 4 (Production)** : Outils d'édition spatiale (pinceau SplatBrush, fusion, nettoyage) finalisés, suite de tests de non-régression validée, et publication sur la Godot Asset Library.
