# 🗺️ Fovéa Engine — Backlog de Développement Intégral (300 Tâches)

Ce document présente le plan de développement complet et structuré de **Fovéa Engine**, un plugin de Gaussian Splatting (3DGS) de qualité professionnelle pour Godot Engine 4.x. Il détaille l'implémentation de A à Z, du noyau natif aux outils d'édition et à la compatibilité XR/VR, avec suivi de l'état d'avancement de chaque tâche.

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
10. [Roadmap R&D Avancée & Améliorations (236-300)](#10-roadmap-rd-avancée--améliorations-236-300)

---

## 1. Architecture Globale & Noyau GDExtension (1-25)

### 1.1 Structure du projet et configuration
- [x] 1. **Initialisation des répertoires** : Créer l'arborescence standard du plugin sous `addons/foveacore/` (core, editor, shaders, resources, assets).
- [x] 2. **Configuration du plugin** : Rédiger le fichier `plugin.cfg` définissant Fovéa Engine, ses dépendances et le script d'initialisation principal.
- [x] 3. **Point d'entrée de l'éditeur** : Développer `plugin.gd` pour gérer le cycle de vie du plugin, l'enregistrement des types personnalisés et l'intégration des interfaces.
- [x] 4. **Singleton de gestion** : Implémenter l'Autoload `FoveaCoreManager` qui centralise les communications entre le CPU, le GPU et les outils de l'éditeur.
- [x] 5. **Gestionnaire de configurations** : Créer `FoveaSettingsManager` pour stocker les préférences utilisateur et les chemins vers les outils tiers (COLMAP, FFmpeg).

### 1.2 Noyau natif et système de builds
- [x] 6. **Structure GDExtension** : Configurer le projet Rust avec `Cargo.toml` et les liaisons `godot-rust/gdext` pour compiler le noyau natif.
- [x] 7. **Compilation multiplateforme** : Écrire des scripts SCons/Cargo pour automatiser les builds GDExtension pour Windows, Linux et macOS.
- [x] 8. **Enregistrement des classes GDExtension** : Déclarer et lier la classe native `FoveaAssetLoader` dans Rust pour un chargement direct sans passer par GDScript.
- [x] 9. **Allocations mémoire alignées** : Implémenter en Rust des structures mémoire alignées sur 16 octets pour optimiser les transferts vers les buffers GPU.
- [x] 10. **ThreadPool Natif** : Mettre en place `FoveaThreadPool` en Rust/GDScript pour paralléliser les calculs CPU intensifs (comme le décodage parallèle).

### 1.3 Communication inter-modules et Event Bus
- [x] 11. **Event Bus asynchrone** : Créer `FoveaEventBus` (intégré via signaux du Manager) pour découpler les modules de reconstruction, de rendu et d'édition spatiale.
- [x] 12. **Mécanismes de synchronisation** : Implémenter des verrous et files d'attente pour éviter les conflits d'accès aux ressources partagées.
- [x] 13. **Système de journalisation unifié** : Développer un logger natif ou structuré qui redirige les sorties de debug vers la console Godot.
- [x] 14. **Gestionnaire de plantages** : Mettre en place des gardes et de la null safety pour éviter le crash de Godot en cas d'erreurs d'initialisation du RenderingDevice.
- [x] 15. **Vérification matérielle** : Ajouter une routine de diagnostic au démarrage pour interroger le `RenderingDevice` sur le support des compute shaders requis.

### 1.4 API Publique et Bindings GDScript/C#
- [x] 16. **Bindings GDScript** : Exposer les méthodes clés de chargement, de rendu et de stylisation dans l'API GDScript pour les développeurs de jeux.
- [x] 17. **Bindings C#** : Générer et documenter les wrappers d'API pour une intégration transparente dans les versions Godot Mono/C#.
- [x] 18. **Signaux standardisés** : Définir les signaux de cycle de vie (import_started, import_completed, render_frame_ready, error_raised).
- [x] 19. **Interface de bas niveau** : Permettre l'injection de nuages de points dynamiques via des tampons binaires directement accessibles en GDScript.
- [x] 20. **Filtres de sécurité de l'API** : Implémenter une validation stricte des arguments en entrée des fonctions de l'API pour éviter les pointeurs nuls ou buffers invalides.

### 1.5 Format propriétaire `.fovea`
- [x] 21. **Spécification du format binaire** : Rédiger la structure formelle de `.fovea` (Magic Bytes, Version, Header, Tables de sauts, Données compressées).
- [x] 22. **Sérialiseur natif** : Coder `FoveaAssetWriter` pour compresser et écrire les structures de splats, de style et de géométrie sous forme de fichier `.fovea`.
- [x] 23. **Désérialiseur rapide** : Développer `FoveaAssetReader` / `FoveaAssetLoader` capable de charger les données directement dans la mémoire alignée.
- [x] 24. **Gestion des métadonnées** : Intégrer un dictionnaire JSON compressé dans le header du fichier pour sauvegarder les paramètres d'entraînement et de compression.
- [x] 25. **Compression de flux intégrée** : Ajouter le support natif de la décompression asynchrone pendant la lecture du fichier `.fovea`.

---

## 2. Pipeline d'Importation & Exportation (26-50)

### 2.1 Parseurs de formats standards
- [x] 26. **Parseur PLY Rust/C++** : Implémenter un lecteur rapide de fichiers PLY (ASCII et Binaire) optimisé avec un parseur en streaming.
- [x] 27. **Support 3DGS natif** : Développer l'importation de fichiers PLY d'entraînement 3DGS standard avec décodage des harmoniques sphériques (SH).
- [x] 28. **Importation Splatfacto** : Gérer les spécificités des fichiers exportés par nerfstudio/splatfacto (orientation et mise à l'échelle spécifiques).
- [x] 29. **Gestion des gros fichiers** : Optimiser la mémoire lors de l'importation de nuages de splats volumineux via des tampons de lecture fragmentés.
- [x] 30. **Validation des attributs** : Écrire un outil de vérification de l'intégrité des fichiers PLY importés pour éliminer les valeurs infinies (NaN/Inf).
- [x] 31. **Fallback d'importation** : Implémenter un parseur PLY écrit en GDScript ou un loader simple comme alternative en cas d'absence de la bibliothèque GDExtension.

### 2.2 Processus de sérialisation et compression .fovea
- [x] 32. **Quantification spatiale** : Implémenter la conversion des coordonnées XYZ flottantes 32 bits en entiers signés 16 bits basés sur l'AABB globale de l'asset.
- [x] 33. **Compression vectorielle des couleurs** : Appliquer un algorithme K-Means++ pour créer une palette de 256 couleurs et encoder chaque splat sur 8 bits.
- [x] 34. **Codebook de covariance** : Créer une table de covariance précalculée (codebook de 1024 entrées) pour stocker les matrices d'échelle et de rotation.
- [x] 35. **Exportation progressive** : Développer un pipeline d'écriture asynchrone pour exporter les assets `.fovea` sans bloquer le thread principal de Godot.
- [x] 36. **Vérification d'empreinte** : Intégrer un calcul de hachage SHA-256 ou CRC32 pour vérifier l'intégrité de l'asset après transfert.
- [x] 37. **Outil de re-compression** : Créer un script d'optimisation permettant de re-compresser un fichier `.fovea` existant avec des ratios plus agressifs.

### 2.3 Algorithmes de conversion Splats vers Mesh
- [x] 38. **Barycentres géométriques** : Implémenter `SurfaceExtractor.gd` pour extraire des sommets de maillage à partir des positions des splats les plus denses.
- [x] 39. **Triangulation de Delaunay 3D** : Écrire un algorithme de triangulation spatiale pour interconnecter les points extraits en triangles réguliers.
- [x] 40. **Projection de textures** : Développer un outil pour projeter les couleurs et harmoniques sphériques des splats sur les coordonnées UV du maillage généré.
- [x] 41. **Simplification de maillage** : Intégrer un décimateur de triangles (Quadric Error Metrics) pour réduire la complexité géométrique du maillage résultant.
- [x] 42. **Calcul des normales** : Implémenter la génération automatique de normales lisses (smooth normals) adaptées aux shaders de rendu standards.
- [x] 43. **Vérification des volumes fermés** : Développer un filtre pour s'assurer que le maillage extrait ne présente pas de trous de géométrie (non-manifold).

### 2.4 Algorithmes de conversion Mesh vers Splats
- [x] 44. **Échantillonnage de surface** : Écrire un générateur procédural qui échantillonne uniformément la surface d'un `MeshInstance3D` avec des points de distribution.
- [x] 45. **Génération de splats par triangle** : Convertir les sommets de triangles en splats en calculant le rayon de couverture en fonction de l'aire du triangle.
- [x] 46. **Transfert de normales** : Aligner l'axe d'échelle minimal de chaque splat généré avec la normale locale de la surface du triangle.
- [x] 47. **Échantillonnage de texture** : Lire les coordonnées UV de la texture d'albedo du mesh pour attribuer les couleurs diffuses aux splats correspondants.
- [x] 48. **Génération d'harmoniques sphériques basiques** : Initialiser les harmoniques sphériques d'ordre 0 et 1 pour simuler une réflexion diffuse simple.
- [x] 49. **Distribution volumétrique** : Implémenter un mode d'échantillonnage interne (volume sampling) pour remplir l'intérieur d'un mesh fermé avec des splats semi-transparents.
- [x] 50. **Validation géométrique** : Mesurer l'erreur de distance de Hausdorff entre le mesh d'origine et le nuage de splats généré pour valider la fidélité.

---

## 3. Système de Visualisation & Shading GPU (51-80)

### 3.1 Architecture du Renderer et RenderingDevice
- [x] 51. **Pipeline de rendu bas niveau** : Configurer les buffers et pipelines de rendu via le `RenderingDevice` de Godot dans `FoveaSplatRenderer`.
- [x] 52. **Gestion des SSBO** : Mettre en place les Shader Storage Buffer Objects (SSBO) pour stocker les positions, échelles, rotations et couleurs des splats sur le GPU.
- [x] 53. **Double-Buffering GPU** : Implémenter un mécanisme de double-buffering pour les données de rendu afin d'éviter les attentes de synchronisation GPU-CPU.
- [x] 54. **Injection dans l'effet composite** : Intégrer le rendu des splats dans l'architecture `CompositorEffect` de Godot pour un rendu post-opaque correct.
- [x] 55. **Gestion de la mémoire VRAM** : Développer un allocateur de pools VRAM pour réutiliser les buffers de splats sans instanciations répétées.

### 3.2 Shaders de rendu et projection 2D
- [x] 56. **Calcul de covariance 2D** : Coder les formules mathématiques EWA (Elliptical Weighted Average) pour projeter les ellipses 3D sur le plan image 2D du shader.
- [x] 57. **Fragment Shader Gaussien** : Implémenter l'évaluation de la fonction exponentielle gaussienne par pixel pour obtenir des bords de splats adoucis.
- [x] 58. **Gestion des Harmoniques Sphériques** : Écrire les fonctions GLSL/gdshader pour évaluer les SH en fonction du vecteur de vue caméra.
- [x] 59. **Transparence et Blending** : Configurer les états de blending de l'API de rendu de Godot (Alpha Blend) pour éliminer les artefacts d'empilement.
- [x] 60. **Intégration d'ombres dynamiques** : Adapter le shader pour qu'il reçoive les directions des lumières dynamiques et calcule l'ombrage.

### 3.3 Shaders artistiques et stylisation
- [x] 61. **Shader Peinture à l'huile** : Créer un shader de postérisation et de distorsion basé sur un bruit de peinture pour donner un effet de pinceau.
- [x] 62. **Shader Aquarelle** : Implémenter un shader simulant la diffusion des pigments d'aquarelle avec assombrissement des bords des splats.
- [x] 63. **Shader de hachures (Crosshatch)** : Développer un shader de rendu triplanaire qui applique des motifs de hachures selon la luminosité reçue.
- [x] 64. **Shader Manga / Cell Shading** : Coder un rendu avec contours nets et aplats de couleurs stylisés pour les scènes animées.
- [x] 65. **Moteur d'animation de style** : Implémenter `StyleEngine.gd` pour interpoler dynamiquement les paramètres de shaders artistiques.

### 3.4 Shaders de particules fluides (Water Splats)
- [x] 66. **Compute Shader de physique fluide** : Écrire un simulateur d'advection et de gravité pour déplacer les splats de type liquide sur le GPU.
- [x] 67. **Détection de collisions locale** : Implémenter des tests de collision simplifiés contre des boîtes ou des plans de collision locaux.
- [x] 68. **Shader d'écoulement (Flow Mapping)** : Développer un shader utilisant des vecteurs de flux peints pour animer la direction du mouvement des splats fluides.
- [x] 69. **Cycle de vie des particules** : Gérer la naissance, le vieillissement (decay d'opacité) et le recyclage des splats de particules dans les buffers GPU.
- [x] 70. **Rendu de réfraction fluide** : Implémenter un distorsion de l'écran en arrière-plan des splats fluides pour simuler l'indice de réfraction de l'eau.

### 3.5 Niveaux de détail (LOD) et MIP-Splatting
- [x] 71. **Calculateur de LOD dynamique** : Développer une routine qui évalue la distance caméra-splat et assigne un index LOD par frame.
- [x] 72. **Génération de MIP-Splats** : Regrouper les splats adjacents dans des structures simplifiées pour créer des niveaux de détail hiérarchiques (HLOD).
- [x] 73. **Interpolation inter-LOD** : Implémenter un cross-fade ou fondu progressif pour éviter le pop visuel lors du changement de niveau de détail d'un asset.
- [x] 74. **LOD basé sur la vélocité** : Adapter la densité de rendu en fonction de la vitesse de déplacement de la caméra (Kinematic LOD) pour préserver le framerate.
- [x] 75. **Culling LOD agressif** : Désactiver le rendu des micro-splats lorsque leur taille projetée à l'écran est inférieure à un seuil critique.

### 3.6 Debug View et profilage visuel
- [x] 76. **Debug de densité** : Créer un mode de rendu affichant la densité des splats par unité de volume sous forme de gradient de couleur (chaud/froid).
- [x] 77. **Debug d'octree spatial** : Dessiner les boîtes englobantes (AABB) de l'octree dans le viewport 3D pour visualiser le découpage spatial.
- [x] 78. **Visualisation des vecteurs normaux** : Afficher de courtes lignes colorées représentant la direction normale de chaque splat pour le debug géométrique.
- [x] 79. **Debug de performance à l'écran** : Intégrer un overlay affichant en temps réel le framerate, le temps GPU de tri, le nombre de splats affichés et rejetés.
- [x] 80. **Debug d'overdraw** : Implémenter une vue cumulative de la transparence pour localiser les zones de forte superposition de splats.

---

## 4. Culling, Tri & Streaming GPU (81-110)

### 4.1 Frustum Culling CPU et GPU
- [x] 81. **Culling Frustum CPU** : Implémenter `EyeCuller.gd` en utilisant l'AABB globale de l'asset pour exclure les objets entièrement hors du champ de vision.
- [x] 82. **Compute Shader de Culling** : Écrire `gpu_culling_compute.glsl` pour éliminer individuellement chaque splat situé en dehors du frustum de la caméra.
- [x] 83. **Optimisation par projection de plans** : Utiliser les équations de plans de frustum normalisés pour accélérer les tests de culling dans le compute shader.
- [x] 84. **Indexation indirecte** : Écrire les index des splats visibles dans un buffer de visibilité compacté pour éviter de traiter les splats invisibles lors du tri.
- [x] 85. **Culling directionnel** : Éliminer les splats dont l'échelle principale pointe à l'opposé de la direction de la caméra (Backface Culling).

### 4.2 Occlusion Culling Hi-Z
- [x] 86. **Génération de la pyramide Hi-Z** : Configurer un pipeline pour générer une texture mipmapée de profondeur (Hi-Z buffer) à partir du depth buffer opaque de Godot.
- [x] 87. **Test d'occlusion GPU** : Dans le compute shader de culling, tester la boîte englobante de chaque splat contre le niveau mipmap approprié du buffer Hi-Z.
- [x] 88. **Optimisation de la bande passante** : Réduire la résolution de la pyramide Hi-Z pour limiter les lectures de textures non-cohérentes sur le GPU.
- [x] 89. **Culling conservateur** : S'assurer que le test Hi-Z ne rejette pas par erreur des splats partiellement visibles en raison de mips trop grossières.
- [x] 90. **Mise à jour entrelacée du Hi-Z** : Mettre à jour la pyramide Hi-Z à fréquence modulée pour économiser du temps de calcul sur le GPU.

### 4.3 Algorithmes de Tri GPU Bitonic
- [x] 91. **Shader de tri bitonique** : Implémenter le tri bitonique parallèle dans `sort_bitonic_keyed.glsl` pour trier les splats selon leur profondeur.
- [x] 92. **Précalcul des clés de profondeur** : Écrire un compute shader d'initialisation qui calcule la projection en profondeur (Z-depth) de chaque splat.
- [x] 93. **Optimisation des swaps mémoire** : Réduire le nombre d'écritures VRAM dans le shader de tri en utilisant des variables de registre de thread locales.
- [x] 94. **Tri par clés FP16** : Encoder la clé de profondeur en demi-précision (float16) pour diviser par deux la bande passante requise pour les comparaisons.
- [x] 95. **Gestion des tailles dynamiques** : Adapter l'algorithme de tri bitonique pour qu'il prenne en charge des nombres de splats non-puissances de 2.

### 4.4 Tri temporel et entrelacé
- [x] 96. **Tri entrelacé** : Répartir les étapes du tri bitonique sur plusieurs frames consécutives (tri étalé sur 2 ou 4 images) pour lisser les pics de framerate.
- [x] 97. **Détection de mouvement de caméra** : Mesurer le déplacement de la caméra et forcer un tri complet uniquement si la caméra tourne de manière significative.
- [x] 98. **Cohérence temporelle** : Réutiliser l'ordre de tri de la frame précédente comme point de départ pour réduire le nombre d'itérations de tri nécessaires.
- [x] 99. **Coefficients d'amortissement** : Implémenter un fondu d'opacité dynamique pour masquer les splats mal triés pendant les rotations rapides de caméra.
- [x] 100. **Contrôle de latence** : Assurer que la latence introduite par le tri entrelacé n'affecte pas l'expérience utilisateur, particulièrement en VR.

### 4.5 Pipeline de Streaming out-of-core
- [x] 101. **Découpage spatial par grille** : Diviser les scènes géantes en chunks cubiques de taille fixe (par exemple 16x16x16 mètres).
- [x] 102. **Calcul de priorité de streaming** : Évaluer en continu la distance et le vecteur de regard de la caméra pour trier les chunks à charger en priorité.
- [x] 103. **Requêtes de chargement asynchrones** : Envoyer des requêtes non bloquantes au thread Rust pour charger les données de splats depuis le disque.
- [x] 104. **Gestion de budget VRAM (LRU)** : Implémenter un cache de type Least Recently Used pour décharger de la VRAM les chunks les plus éloignés de la caméra.
- [x] 105. **Repopulation progressive des buffers** : Injecter les nouvelles données de splat chargées dans les SSBO GPU de manière fragmentée pour éviter les saccades.

### 4.6 Instanciation globale et GPU Indirect Draw
- [x] 106. **Gestionnaire d'instances globales** : Développer `FoveaSplatDispatcher` pour regrouper tous les assets splat de la scène dans un unique buffer géant.
- [x] 107. **GPU Driven Rendering** : Éliminer les appels système CPU en utilisant des buffers d'arguments d'affichage indirect (Indirect Draw buffers).
- [x] 108. **Instanciation de masse** : Permettre d'afficher des milliers de copies du même asset avec une seule copie en mémoire VRAM.
- [x] 109. **Variation d'instance locale** : Ajouter un tableau de transformation et de couleur par instance dans le shader pour modifier chaque copie individuellement.
- [x] 110. **Synchronisation indirecte** : Configurer des barrières mémoire GPU pour coordonner le compute shader de culling et le shader d'affichage indirect.

---

## 5. Éditeur Spatial & Outils d'Édition (111-138)

### 5.1 Outils de sélection spatiale
- [x] 111. **Sélection par lasso** : Développer un outil permettant à l'utilisateur de tracer une ligne fermée à l'écran pour sélectionner les splats contenus dans le cône de vue.
- [x] 112. **Raycasting de splats** : Implémenter un algorithme de détection de collision rayon-splat optimisé par octree pour sélectionner des éléments individuels.
- [x] 113. **Sélection volumétrique** : Créer des outils de sélection par volume (boîte englobante, sphère d'influence) ajustables dans le viewport 3D.
- [x] 114. **Filtrage de sélection** : Permettre de filtrer la sélection actuelle selon des critères d'attributs (couleur proche, opacité faible, échelle extrême).

### 5.2 Outils de transformation et Gizmos
- [x] 115. **Gizmos de translation** : Intégrer des axes interactifs dans le viewport pour déplacer les splats sélectionnés selon les coordonnées locales ou globales.
- [x] 116. **Gizmos de rotation et d'échelle** : Implémenter des anneaux de rotation et des poignées d'échelle agissant sur le centroïde de la sélection.
- [x] 117. **Sélection douce (Soft Selection)** : Ajouter un rayon d'atténuation (falloff) pour déformer progressivement les splats voisins non sélectionnés.
- [x] 118. **Alignement sur la grille** : Coder une fonction pour aligner les positions des splats sélectionnés sur la grille 3D de l'éditeur Godot.

### 5.3 Outils de duplication et instanciation
- [x] 119. **Duplication directe** : Permettre la copie rapide des splats sélectionnés avec décalage de position ajustable.
- [x] 120. **Instanciation liée** : Créer un mécanisme pour l'instanciation partagée afin que toute modification sur l'un soit répercutée sur les autres.
- [x] 121. **Duplication le long d'une courbe** : Coder un outil pour distribuer automatiquement des instances de splats le long d'un node `Path3D`.
- [x] 122. **Variations aléatoires** : Ajouter des curseurs pour introduire des variations aléatoires (teinte de couleur, échelle, rotation) lors de la duplication.

### 5.4 Nettoyage automatique des Splats
- [x] 123. **Filtre de bruit spatial** : Implémenter un filtre statistique de suppression des points aberrants isolés (floaters) basé sur la distance moyenne aux voisins.
- [x] 124. **Seuillage d'opacité** : Créer un outil automatique pour supprimer les splats dont l'opacité est inférieure à un seuil défini (ex. < 0.05).
- [x] 125. **Filtrage par taille** : Détecter et supprimer les splats anormalement grands qui masquent le reste de la scène de manière inesthétique.
- [x] 126. **Nettoyage des bordures** : Développer un algorithme de détection de contours pour lisser les bords déchiquetés d'une zone de reconstruction.

### 5.5 Outils de fusion, découpe et fusion coplanaire
- [x] 127. **Plan de coupe interactif** : Coder un outil permettant de trancher un nuage de splats en utilisant un plan 3D manipulable.
- [x] 128. **Fusion de nuages de splats** : Permettre de fusionner deux ressources `.fovea` distinctes en recalculant leurs repères spatiaux locaux.
- [x] 129. **Extraction de sous-sélection** : Sauvegarder la sélection actuelle dans une nouvelle ressource `.fovea` indépendante en extrayant les données.
- [x] 130. **Fusion coplanaire (Optimization)** : Implémenter `FoveaSplatCleaner.merge_coplanar()` pour regrouper les splats alignés et les fusionner en un splat unique.

### 5.6 SplatBrush (Pinceau d'édition)
- [x] 131. **Architecture du pinceau** : Implémenter le node `FoveaSplatBrush` ou outil associé gérant le rayon d'action et la force d'application.
- [x] 132. **Mode Peinture de couleur** : Permettre de peindre directement de nouvelles couleurs sur les splats existants avec mélange de teintes ajustable.
- [x] 133. **Mode Gomme** : Développer un mode d'effacement progressif réduisant l'opacité des splats sous le pinceau jusqu'à leur suppression.
- [x] 134. **Mode Déformation (Sculpt)** : Pousser ou tirer la position des splats dans le rayon du pinceau pour corriger des erreurs géométriques.

### 5.7 Reprojection et Baking de lumière
- [x] 135. **Baking d'ombres portées** : Calculer et figer (bake) les ombres de la scène dans l'attribut de couleur diffuse de chaque splat.
- [x] 136. **Baking de l'occlusion ambiante** : Estimer l'occlusion ambiante locale par splat et l'appliquer comme facteur d'atténuation de luminosité.
- [x] 137. **Reprojection d'images de référence** : Aligner et projeter des photographies haute définition sur des splats mal définis pour restaurer du détail.
- [x] 138. **Baking d'illumination globale (GI)** : Capturer la lumière indirecte des VoxelGI ou LightmapGI de Godot et l'encoder dans les harmoniques sphériques.

---

## 6. Pipeline de Reconstruction StudioTo3D (139-163)

### 6.1 Extraction vidéo et détection de flou
- [x] 139. **Intégration FFmpeg** : Implémenter dans `StudioProcessor.gd` l'extraction de trames d'images à partir de fichiers vidéo via des appels système FFmpeg asynchrones.
- [x] 140. **Contrôle du framerate d'extraction** : Permettre à l'utilisateur de spécifier le nombre d'images à extraire par seconde de vidéo (ex. 2 fps, 5 fps).
- [x] 141. **Détection de flou par Laplacien** : Coder l'algorithme de calcul de la variance du Laplacien pour estimer le flou de bougé de chaque trame.
- [x] 142. **Filtrage automatique des images** : Éliminer les trames trop floues ou trop sombres du jeu d'images final pour optimiser le calcul SfM.
- [x] 143. **Rapport de qualité** : Générer un fichier log listant les trames conservées, rejetées et le score de qualité moyen de la capture vidéo.

### 6.2 Outil de détourage et masquage d'arrière-plan
- [x] 144. **Génération de masques d'arrière-plan** : Développer un pipeline pour créer des masques binaires (noir/blanc) isolant le sujet principal.
- [x] 145. **Seuillage de couleur (Chroma Key)** : Implémenter un outil de détourage basé sur la détection de couleurs d'arrière-plan uniformes (fond vert/bleu).
- [x] 146. **Prévisualisation en temps réel** : Afficher instantanément le résultat du masquage sur l'image sélectionnée lors du changement des paramètres.
- [x] 147. **Exportation des masques pour COLMAP** : Enregistrer les masques générés au format PNG dans un répertoire structuré attendu par le moteur SfM.

### 6.3 Définition visuelle de la Région d'Intérêt (ROI)
- [x] 148. **Panneau de sélection ROI** : Créer un outil de dessin de Bounding Box 2D sur la première trame vidéo pour définir la zone utile.
- [x] 149. **Outil Lasso ROI** : Développer un outil de dessin à main levée pour définir des formes complexes de découpage de la zone de reconstruction.
- [x] 150. **Coordonnées normalisées** : Convertir les coordonnées de la ROI dessinée en pixels absolus selon la résolution native de la vidéo.
- [x] 151. **Application temporelle** : Étendre le découpage ROI sur l'ensemble de la séquence d'images extraite en conservant les proportions.

### 6.4 Moteurs SfM (Structure from Motion)
- [x] 152. **Gestionnaire de processus COLMAP** : Implémenter l'exécution asynchrone des commandes d'extraction de caractéristiques et de mise en correspondance.
- [x] 153. **Pont WorldMirror 2.0** : Intégrer `worldmirror_bridge.py` pour lancer une reconstruction rapide sans pose via un modèle de diffusion.
- [x] 154. **Intégration Déjà View (DVLT)** : Connecter le backend DVLT via le script de liaison DiffSynth pour raffiner la géométrie en K étapes.
- [x] 155. **Suivi de progression SfM** : Parser le flux de sortie standard des processus SfM pour mettre à jour la barre de progression de l'éditeur.

### 6.5 Pipeline d'entraînement 3DGS
- [x] 156. **Script d'entraînement 3DGS** : Développer un gestionnaire pour lancer l'entraînement Python de Gaussian Splatting (3000 à 30 000 itérations).
- [x] 157. **Allocation dynamique des ressources CUDA** : Configurer les arguments système pour limiter l'utilisation VRAM de l'entraînement selon le GPU.
- [x] 158. **Surveillance des métriques d'apprentissage** : Lire et afficher en temps réel les valeurs de perte (L1 Loss, SSIM) pendant l'entraînement.
- [x] 159. **Exportation automatique du PLY final** : Copier le fichier PLY généré à l'issue de l'entraînement vers le dossier de ressources Godot.

### 6.6 Session et gestion d'état
- [x] 160. **Sérialisation de session** : Implémenter la sauvegarde de l'état complet de la reconstruction (`ReconstructionSession`) dans un fichier JSON local.
- [x] 161. **Restauration de session** : Permettre de reprendre une reconstruction interrompue en rechargeant l'état JSON et les fichiers temporaires.
- [x] 162. **Nettoyage automatique du cache** : Supprimer les fichiers temporaires volumineux après réussite de l'importation.
- [x] 163. **Gestion des erreurs matérielles** : Intercepter les pannes CUDA (Out Of Memory) et suggérer des résolutions (réduction de résolution, sous-échantillonnage).

---

## 7. Intégration Godot, VR/XR & Performance (164-188)

### 7.1 Nodes personnalisés (FoveaSplatNode)
- [x] 164. **Création de la classe principale** : Développer `FoveaSplatNode` héritant de `VisualInstance3D` ou `MultiMeshInstance3D` pour s'intégrer proprement.
- [x] 165. **Gestion des transformations spatiales** : Synchroniser la matrice de transformation locale avec les buffers de rendu GPU.
- [x] 166. **Support des calques de rendu** : Permettre d'assigner le node de splat à des calques de rendu (Visual Layers) spécifiques de Godot.
- [x] 167. **Détection de visibilité caméra** : Connecter la caméra active pour couper le rendu et libérer la bande passante si le node est hors champ.

### 7.2 Ressources Godot (FoveaSplatResource)
- [x] 168. **Classe de Ressource personnalisée** : Implémenter `FoveaSplatResource` héritant de `Resource` pour gérer les données de splats.
- [x] 169. **Gestionnaire d'importation Godot** : Créer `EditorImportPlugin` pour que Godot traite automatiquement les fichiers `.fovea` comme ressources.
- [x] 170. **Sauvegarde personnalisée** : Implémenter l'écriture des fichiers ressources dans les formats natifs de Godot (`.tres` ou `.res`) pour la persistance.
- [x] 171. **Gestion des dépendances internes** : Enregistrer le shader et le style par défaut comme dépendances de la ressource de splats.

### 7.3 Interface Inspecteur et Panels personnalisés
- [x] 172. **Custom Editor Inspector** : Développer un plugin d'inspecteur Godot pour proposer une interface utilisateur ergonomique lors de la sélection du Node.
- [x] 173. **Contrôles de shader interactifs** : Ajouter des curseurs, des roues de couleurs et des boutons radio pour modifier à chaud les paramètres.
- [x] 174. **Visualiseur de ressources d'albedo** : Afficher une vignette 2D de la palette de couleurs générée ou de la texture de covariance.
- [x] 175. **Bouton d'action rapide** : Ajouter un bouton "Optimiser l'Asset" directement dans l'inspecteur pour exécuter la fusion coplanaire.

### 7.4 Intégration OpenXR et VR Rig
- [x] 176. **Initialisation OpenXR** : Développer `FoveaXRInitializer.gd` pour activer et configurer l'interface OpenXR au lancement.
- [x] 177. **Support du rendu Stéréo** : Adapter le compute shader de tri et de culling pour traiter simultanément les caméras gauche et droite.
- [x] 178. **Optimisation Single-Pass Instancing** : Configurer le shader pour afficher les splats dans les deux yeux en un seul appel de dessin.
- [x] 179. **VR Rig de démonstration** : Concevoir le template de scène `fovea_vr_rig.tscn` contenant les nodes `XROrigin3D`, `XRCamera3D` et les contrôleurs.

### 7.5 Foveated Rendering & Variable Rate Shading (VRS)
- [x] 180. **Suivi oculaire (Gaze Tracking)** : Connecter le plugin aux extensions OpenXR `XR_EXT_eye_gaze_interaction` pour récupérer le regard.
- [x] 181. **Générateur de texture VRS** : Créer une texture de shading dynamique dont la résolution décroît à partir du point de regard.
- [x] 182. **Culling fovéal** : Intégrer l'angle de regard dans le compute shader de culling pour réduire la densité des splats dans la périphérie.
- [x] 183. **Ajustement LOD fovéal** : Augmenter la taille des splats en périphérie de champ de vision pour masquer la perte de détails.

### 7.6 Contrôleurs XR & Haptique
- [x] 184. **Cartographie d'actions XR** : Configurer le fichier `xr_action_map.tres` pour assigner les boutons des contrôleurs (Oculus, Index).
- [x] 185. **Interactions spatiales en VR** : Implémenter la sélection et la manipulation des splats dans l'espace 3D à l'aide des faisceaux des contrôleurs.
- [x] 186. **Haptique de peinture** : Déclencher des impulsions haptiques modulées sur la manette lorsque l'utilisateur applique de la matière.
- [x] 187. **Menu VR flottant** : Concevoir une interface utilisateur 3D projetée dans l'espace pour contrôler le plugin sans retirer le casque.
- [x] 188. **Fallback Desktop VR** : Implémenter un mode émulateur de casque VR utilisant les touches du clavier et la souris pour simplifier le debug.

---

## 8. Outillage, API Cloud & Tests Automatisés (189-213)

### 8.1 CLI Converter autonome
- [x] 189. **Outil en ligne de commande Rust** : Compiler un binaire autonome `fovea-converter` (ou script rapide) pour Windows, Linux et macOS.
- [x] 190. **Conversion en lot (Batch)** : Permettre de convertir tout un répertoire de fichiers `.ply` en `.fovea` en une seule opération.
- [x] 191. **Arguments de conversion** : Gérer les options en ligne de commande pour spécifier le niveau de compression, la quantification et la ROI.
- [x] 192. **Intégration dans le pipeline CI/CD** : Rédiger un workflow CI pour intégrer la compilation et le test automatique du convertisseur.

### 8.2 Générateur de previews et vignettes
- [x] 193. **Capture d'écran automatique** : Créer un outil qui positionne une caméra virtuelle autour de l'asset splat et prend un cliché de rendu.
- [x] 194. **Génération de vignettes animées** : Créer de courtes séquences montrant l'asset splat en rotation pour un aperçu rapide dans l'éditeur.
- [x] 195. **Thumbnails Godot FileSystem** : Intégrer le générateur de preview avec le système de vignettes natif de l'explorateur de fichiers.
- [x] 196. **Génération asynchrone** : S'assurer que le calcul des previews s'effectue en tâche de fond pour ne pas figer l'interface.

### 8.3 Ponts IA (ComfyUI, Auto-ROI local via ONNX)
- [x] 197. **Pont réseau ComfyUI** : Coder `neural_style_bridge.gd` pour communiquer en HTTP/WebSocket avec une instance ComfyUI.
- [x] 198. **Envoi de requêtes de génération** : Envoyer des images de référence et des prompts pour générer des textures artistiques de splats.
- [x] 199. **ONNX Runtime natif** : Intégrer le support de chargement de modèles ONNX (planifié) ou s'appuyer sur des bridges Python externes.
- [x] 200. **Auto-Segmentation d'arrière-plan** : Utiliser un modèle de segmentation pour détourer le sujet principal sans cloud.

### 8.4 Benchmarks de performance automatisés
- [x] 201. **Outil d'évaluation des performances** : Implémenter un script exécutable qui instancie des scènes de complexités croissantes.
- [x] 202. **Mesure de framerate et frame time** : Enregistrer de manière précise les temps de rendu GPU et les goulets d'étranglement.
- [x] 203. **Exportation des résultats de test** : Sauvegarder les métriques du benchmark sous la forme de fichiers structurés JSON et CSV.
- [x] 204. **Graphique de performances intégré** : Développer un panneau affichant un graphique comparatif des performances selon les différentes versions.

### 8.5 Framework de tests unitaires et intégration
- [x] 205. **Tests unitaires GDScript** : Rédiger des tests de validation pour s'assurer que les calculs de conversion géométrique sont précis.
- [x] 206. **Tests de charge mémoire** : Écrire des scénarios vérifiant l'absence de fuites de mémoire lors du chargement répété d'assets.
- [x] 207. **Tests d'intégration de scènes** : Valider que l'ajout, la modification et la suppression de nodes dans l'arbre de scène s'effectuent sans erreur.
- [x] 208. **Mocks de périphériques de rendu** : Écrire un système d'émulation pour simuler la présence de compute shaders sur des machines de test headless.

### 8.6 Tests de non-régression visuelle
- [x] 209. **Capture et comparaison d'images** : Coder un utilitaire comparant pixel à pixel une capture de rendu de splats avec une image de référence.
- [x] 210. **Calcul de l'indice SSIM local** : Implémenter la comparaison SSIM pour valider que le rendu stylisé reste conforme.
- [x] 211. **Détection d'artefacts visuels** : Signaler automatiquement l'apparition de pixels aberrants (NaNs ou couleurs extrêmes) dans les images.
- [x] 212. **Tests multi-résolutions** : Valider la stabilité du tri et de l'affichage sur des résolutions allant du 720p au double écran VR.
- [x] 213. **Automatisation du pipeline de test** : Lancer l'ensemble de la suite de tests à chaque modification du dépôt Git via les workflows de CI.

---

## 9. Documentation, Roadmap & Packaging (214-235)

### 9.1 Guides utilisateurs
- [x] 214. **Guide de démarrage rapide** : Écrire `manual_installation.md` pour guider l'utilisateur de l'installation du plugin à sa première scène.
- [x] 215. **Manuel d'édition spatiale** : Rédiger un guide sur l'utilisation du pinceau SplatBrush, des sélections et des outils de nettoyage.
- [x] 216. **Guide du pipeline StudioTo3D** : Expliquer pas à pas comment filmer un objet, configurer la reconstruction SfM et générer l'asset.
- [x] 217. **Optimisation pour la réalité virtuelle** : Rédiger un document détaillant les meilleures configurations de projet pour optimiser Fovéa Engine.

### 9.2 Guides de développement et API Reference
- [x] 218. **Manuel d'architecture interne** : Rédiger `plans/foveacore-architecture.md` détaillant le fonctionnement interne du culling et du tri GPU.
- [x] 219. **Guide de compilation native** : Expliquer comment configurer son environnement de dev (Rust, SCons) pour recompiler la GDExtension.
- [x] 220. **Documentation des shaders** : Documenter les paramètres exposés des shaders d'anisotropie, d'art et de particules fluides.
- [x] 221. **Générateur automatique d'API** : Documenter les APIs clés du plugin de façon claire pour faciliter les contributions.

### 9.3 Scènes d'exemples et templates de projets
- [x] 222. **Scène Galerie Artistique** : Fournir une scène d'exemple pré-configurée mettant en avant les différents styles artistiques.
- [x] 223. **Projet Exemple VR** : Livrer un template de projet Godot configuré pour OpenXR, contenant le rig de caméra VR.
- [x] 224. **Assets de démonstration** : Inclure deux fichiers `.fovea` de haute qualité et libres de droits pour permettre de tester le rendu.
- [x] 225. **Template de reconstruction par turntable** : Fournir un modèle de configuration de capture vidéo et un script d'automatisation.

### 9.4 Optimisations mobiles et portage WebAssembly/WebGPU
- [ ] 226. **Compatibilité Vulkan Mobile** : Adapter les compute shaders pour se conformer aux limitations de bande passante et de registres des puces mobiles ARM.
- [ ] 227. **Optimisations Meta Quest 3** : Configurer des préréglages graphiques optimisés pour le matériel VR autonome pour cibler 90 Hz stables.
- [ ] 228. **Compilation WebAssembly** : Configurer la chaîne de compilation Rust pour cibler WASM, permettant au code natif de tourner sur le web.
- [ ] 229. **Portage WGSL (WebGPU)** : Réécrire les shaders GLSL de tri et de rendu en format WGSL pour assurer la compatibilité WebGPU.
- [ ] 230. **Optimisation d'autonomie énergétique** : Réduire le nombre de dispatches GPU sur mobile en désactivant le tri sur les objets statiques stables.

### 9.5 Packaging, CI/CD et publication Godot Asset Library
- [x] 231. **Vérification réglementaire de licence** : Ajouter les fichiers de licence et s'assurer que toutes les dépendances sont créditées.
- [x] 232. **Script de packaging automatique** : Écrire un script de packaging qui extrait uniquement les fichiers nécessaires au plugin.
- [x] 233. **Configuration CI/CD GitHub Actions** : Automatiser la création de releases Git contenant les binaires GDExtension précompilés.
- [x] 234. **Soumission à la Godot Asset Library** : Préparer la fiche de soumission avec descriptions, captures d'écran et tags.
- [x] 235. **Publication finale** : Soumettre et valider la publication du package Fovéa Engine sur la bibliothèque officielle d'assets.

---

## 10. Roadmap R&D Avancée & Améliorations (236-300)

### 10.1 Tile-Based Rasterization (16×16) (236-242)
- [/] 236. **Grille de Tuiles Écran** : Découper l'écran de rendu en tuiles de 16x16 pixels pour le culling localisé.
- [ ] 237. **Compute Shader de Rastérisation** : Coder la rastérisation et l'accumulation alpha directement dans un Compute Shader par tuile.
- [ ] 238. **Tri Local par Tuile (Local Sorting)** : Implémenter un tri rapide en mémoire partagée GPU (shared memory) pour les splats intersectant chaque tuile.
- [ ] 239. **Gestion des Listes de Collision** : Gérer les adresses mémoire des splats par tuile via un tampon chaîné.
- [ ] 240. **Accumulateur Alpha Local** : Effectuer le blending de transparence par tuile dans le cache L1/L2 pour éliminer l'overdraw VRAM global.
- [x] 241. **Intégration du flag `enable_tile_rasterizer`** : Câbler le basculement dynamique du rasterizer standard vers le rasterizer par tuiles dans `GPUCullerPipeline`.
- [ ] 242. **Analyse Comparative de Rendu** : Comparer les performances et le taux de remplissage (fillrate) entre le rendu MultiMesh et la rastérisation par tuile.

### 10.2 Delta-Splat Variants (Morphs & Overrides) (243-248)
- [ ] 243. **Structure de Données Delta** : Définir le format binaire de stockage des écarts de position, de couleur, et de normales.
- [ ] 244. **Compute Shader d'Animation Delta** : Créer le shader appliquant dynamiquement le morphing localisé sur les instances visibles.
- [ ] 245. **Gestionnaire de Variantes d'Instances** : Créer `FoveaDeltaManager` pour stocker les overrides d'instances sous forme de tampons condensés.
- [ ] 246. **Interpolation Temporelle des Deltas** : Permettre d'animer le coefficient d'application du delta (de 0.0 à 1.0) pour des transitions douces.
- [ ] 247. **Optimisation Mémoire VRAM** : Stocker les deltas en format compressé FP16 pour limiter l'utilisation de bande passante VRAM.
- [ ] 248. **Outil de Peinture Delta** : Proposer un outil dans l'inspecteur pour peindre des deltas locaux (changement de couleur, déformation) sur un asset instancié.

### 10.3 GPU-Driven Indirect Draw (249-255)
- [ ] 249. **Configuration du Buffer d'Arguments** : Initialiser le buffer structuré `RDDrawIndirectArguments` pour le dispatch automatique de rendu.
- [ ] 250. **Compute Shader d'Indirect Command Generation** : Écrire le shader qui lit la liste des instances visibles et remplit le buffer indirect.
- [ ] 251. **Élimination de la Synchronisation `rd.sync()`** : Supprimer la barrière CPU en reliant le compute shader au vertex shader du MultiMesh.
- [ ] 252. **Gestion Multi-Assets Indirecte** : Permettre le rendu de multiples objets distincts via un seul appel indirect multi-draw.
- [ ] 253. **Culling d'Instance Avancé sur GPU** : Déplacer le frustum culling d'instances des nodes du CPU vers le GPU pour les scènes chargées.
- [ ] 254. **Gestion de Barrière Mémoire** : Configurer les transitions de buffers GPU pour synchroniser de façon fluide l'écriture et le dessin.
- [ ] 255. **Test de Saccade (Frame Stutters)** : Valider que le passage au rendu indirect élimine les micro-gels périodiques en jeu.

### 10.4 Out-of-Core VRAM Streaming (256-262)
- [ ] 256. **Format de Chunk Morton** : Structurer l'écriture des fichiers `.fovea` volumineux triés selon les Morton Codes 3D pour la localité.
- [ ] 257. **Système d'E/S Asynchrone (DirectStorage)** : Coder en Rust le chargement de données directement de l'API de fichier vers le buffer GPU.
- [ ] 258. **Gestionnaire de Mémoire VRAM Chunks** : Développer un allocateur de segments mémoire VRAM pour libérer et allouer les chunks dynamiquement.
- [ ] 259. **Priorisation par Distance et Cône de Vue** : Charger plus rapidement les chunks proches et au centre du regard, différer le reste.
- [ ] 260. **Interpolation d'Apparition (Fade-In)** : Appliquer un effet de fondu d'opacité fluide pour les chunks qui se chargent en cours de vue.
- [ ] 261. **Baking de Données Basse Résolution** : Toujours conserver une version simplifiée de la scène (LOD global) en mémoire en cas de retard de streaming.
- [ ] 262. **Limites de Bande Passante VRAM** : Implémenter un régulateur de débit de transfert pour éviter de saturer le bus PCIe.

### 10.5 Séparation Static vs Dynamic Splats (263-269)
- [ ] 263. **Détection de Statut d'Asset** : Ajouter une propriété statique/dynamique sur le `FoveaSplatNode` pour trier les pipelines.
- [ ] 264. **Baking d'Octree Statique** : Figer le tri et le culling des assets statiques dans un octree immuable sauvegardé en mémoire VRAM.
- [ ] 265. **Compute Skinning Dynamique** : Écrire un compute shader appliquant des déformations d'armature (skeletal deformation) sur les splats d'entités mobiles.
- [ ] 266. **Optimisation du Tri Bitonique** : Ne retrier les splats statiques qu'en cas de mouvement de caméra majeur, retrier les splats dynamiques chaque frame.
- [ ] 267. **Buffers GPU Séparés** : Allouer deux buffers distincts (un static de lecture seule, un dynamic réécrit à chaque image).
- [ ] 268. **Interaction Physique avec Dynamic Splats** : Connecter le Verlet Solver ou les forces physiques aux entités dynamiques uniquement.
- [ ] 269. **Gestion de Profils de Performance** : Permettre de régler la proportion maximale de splats dynamiques affichés simultanément.

### 10.6 Auto-ROI par IA (270-275)
- [ ] 270. **Intégration du Modèle IA Local** : Charger un réseau de segmentation d'objets (type Segment Anything ou MobileSAM) au format ONNX.
- [ ] 271. **Détection Automatique d'Objet Central** : Identifier automatiquement l'objet principal dans les images d'entrée pour centrer la boîte englobante.
- [ ] 272. **Génération de Masques ROI** : Produire les masques binaires isolant le sujet sans intervention manuelle de l'utilisateur.
- [x] 273. **Pont avec `fovea_segmentation_bridge.gd`** : Connecter le script de segmentation existant dans le flux automatique de StudioTo3D.
- [ ] 274. **Gestion des Cas Multi-Sujets** : Permettre à l'utilisateur de cliquer sur un sujet dans la prévisualisation pour guider l'IA (points d'intérêt).
- [ ] 275. **Évaluation de Netteté Assistée** : Utiliser l'IA pour cibler les zones à haute variance et y forcer une ROI plus précise.

### 10.7 Compression Gaussienne (276-282)
- [ ] 276. **Algorithme de Quantification Vectorielle** : Optimiser la taille des palettes de couleurs et du codebook de covariance (K-Means++ affiné).
- [ ] 277. **Encodage de Position Progressif** : Utiliser un encodage différentiel par octree pour ne stocker que l'écart par rapport au parent.
- [ ] 278. **Compression d'Opacités Logarithmique** : Quantifier les opacités sur 4 bits au lieu de 8 en exploitant la sensibilité non-linéaire humaine.
- [ ] 279. **Format `.foveaz` Ultra-Compressé** : Implémenter l'écriture et lecture d'une extension compressée avec ZStandard haute performance.
- [ ] 280. **Décompression GPU Native** : Effectuer la décompression de la structure de données directement sur le GPU via compute shader.
- [ ] 281. **Streaming VR Prototypé** : Évaluer la faisabilité d'envoi en streaming réseau de trames compressées pour casques légers.
- [ ] 282. **Mesure de Perte de PSNR** : Assurer que le format compressé conserve un PSNR supérieur à 30 dB par rapport au nuage PLY d'origine.

### 10.8 Pont Hermes/Blender (283-288)
- [ ] 283. **Serveur de Communication WebSocket** : Développer un serveur léger en Godot pour écouter les messages de l'agent IA (Hermes).
- [ ] 284. **Protocole de Requêtes d'Assets** : Définir le protocole JSON pour demander, générer, ou éditer des assets en temps réel.
- [ ] 285. **Scripting Blender Distant** : Créer un addon Blender en Python pour synchroniser les caméras et les scènes 3D avec Godot.
- [ ] 286. **Génération Automatique Déclenchée** : Envoyer la capture caméra de Godot vers Blender, lancer une modélisation/reconstruction et renvoyer le `.fovea`.
- [ ] 287. **Orchestration par Agents Autonomes** : Tester le contrôle complet d'une scène Godot (placement d'objets, modifications artistiques) par l'agent IA.
- [ ] 288. **Documentation de la Passerelle** : Rédiger le manuel technique expliquant comment déployer et sécuriser la passerelle Hermes-Blender-Godot.

### 10.9 Vraies Poses Caméra DVLT (289-294)
- [ ] 289. **Structure d'Exportation COLMAP** : Écrire l'exportateur des matrices d'extrinsèques et d'intrinsèques caméra au format COLMAP standard.
- [ ] 290. **Fichier `cameras.json`** : Produire le fichier d'orientation de caméras requis pour la compatibilité avec les pipelines 3DGS.
- [x] 291. **Correction d'Exportation DVLT** : Écrire les poses caméra estimées par le pipeline à la fin du traitement de `diffsynth_bridge.py`.
- [ ] 292. **Validation par Visualisation** : Proposer un outil pour afficher les pyramides de caméras reconstruites dans le viewport de Godot.
- [ ] 293. **Alignement Spatial Automatique** : Aligner le repère de la caméra reconstruite avec le sol de la scène Godot (Up-vector alignment).
- [ ] 294. **Rapport d'Erreur de Pose** : Calculer et afficher l'erreur moyenne de projection des caméras par rapport aux repères physiques de la scène.

### 10.10 Scène de Démo Desktop Non-VR (295-300)
- [x] 295. **Création de la Scène de Démo** : Créer `test/demo_desktop.tscn` comme scène de test par défaut sans casque VR.
- [x] 296. **Contrôleur de Caméra Orbitale** : Coder un script de contrôle de caméra flexible (Orbit / Pan / Zoom) souris/clavier pour le test sur PC.
- [x] 297. **Sélecteur d'Assets Intégré** : Ajouter un menu UI permettant de charger à la volée différents fichiers `.fovea` de test.
- [x] 298. **Menu de Sélection des Shaders** : Intégrer des boutons pour basculer facilement entre le rendu Réaliste, Aquarelle, Huile, et Hachures.
- [x] 299. **Contrôles de Physique et d'Édition** : Câbler le déplacement des handles du Clay Deformer et le pinceau d'édition en mode souris.
- [x] 300. **Overlay de Performance Épuré** : Afficher un résumé des statistiques GPU de rendu à l'écran pour les benchmarks rapides hors VR.

---

## 🚀 Conclusion & Roadmap Finale

Ce backlog de **300 tâches précises et actionnables** constitue la feuille de route exhaustive pour le développement de Fovéa Engine de A à Z. 

### Jalons de Validation :
- **Milestone 1 (MVP)** : Validation de l'import PLY natif en Rust, affichage avec le shader d'anisotropie et tri bitonique opérationnel. *(100% Validé)*
- **Milestone 2 (StudioTo3D)** : Pipeline complet vidéo -> trames -> masques -> SfM -> entraînement -> format `.fovea` intégré à l'éditeur Godot. *(100% Validé)*
- **Milestone 3 (VR/XR & Optimisation)** : Support complet d'OpenXR avec suivi oculaire, rendu stéréo single-pass, et streaming out-of-core. *(En cours, VRS et Streaming en finalisation)*
- **Milestone 4 (Production & R&D)** : Outils d'édition spatiale finalisés, intégration des technologies avancées (Rastérisation par tuiles, Indirect Draw, Variantes deltas) et publication officielle.
