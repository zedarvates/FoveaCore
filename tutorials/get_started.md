# Tutoriel : Premiers Pas avec FoveaEngine 🚀

Ce guide vous explique comment configurer votre première scène VR, rendre vos objets "splattables" et utiliser le pipeline de reconstruction.

---

## 1. Configuration de la Scène VR

Pour commencer, vous avez besoin du rig VR configuré pour FoveaCore.

1.  Créez une nouvelle scène 3D (`Node3D`).
2.  Instanciez le rig VR : `res://addons/foveacore/scenes/fovea_vr_rig.tscn`.
3.  Assurez-vous que le **FoveaXRInitializer** est présent sous le rig. Il gère l'initialisation d'OpenXR et le Foveated Rendering.

## 2. Rendre un objet "Splattable"

Le "splatting" transforme vos meshes 3D en une nuée de points (Gaussians) optimisée pour la VR.

1.  Ajoutez un `MeshInstance3D` à votre scène (par exemple, un Cube ou une Sphère).
2.  Attachez-lui le script : `res://addons/foveacore/scripts/fovea_splattable.gd`.
3.  Dans l'inspecteur, vous pouvez régler :
    *   **Splat Density** : Plus il y a de splats, plus c'est beau, mais plus c'est lourd.
    *   **Style** : Choisissez un style (Procedural ou Neural) via le StyleEngine.

## 3. Utiliser le StudioTo3D (Reconstruction)

Si vous voulez transformer une vidéo réelle en objet 3D utilisable dans le moteur :

1.  Ouvrez le panneau **StudioTo3D** dans l'éditeur (ou instanciez `res://addons/foveacore/scenes/reconstruction/studio_to_3d_panel.tscn`).
2.  **Video Input** : Sélectionnez votre fichier vidéo.
3.  **Pipeline Actions** :
    *   Cliquez sur **1. Extract & Mask** pour préparer les images.
    *   Cliquez sur **2. Run COLMAP** pour calculer la position de la caméra (SfM).
    *   Cliquez sur **3. Train 3DGS** pour générer les Gaussian Splats.
4.  Une fois terminé, l'objet apparaîtra dans votre dossier `res://reconstructions/`.

## 4. Optimisation : Le ProxyFaceRenderer

Pour les environnements complexes (forêts, villes), utilisez les Proxies pour maintenir 90+ FPS.

1.  Pour un objet éloigné, ajoutez un nœud **ProxyFaceRenderer**.
2.  Réglez le **switch_to_proxy_below** (distance à laquelle l'objet devient un simple plan/proxy).
3.  Cela permet de n'afficher que "ce qui est vu" par l'œil, réduisant drastiquement l'overdraw.

## 5. Tester les Performances

Utilisez le script de benchmark pour valider vos gains de FPS :

1.  Ajoutez le script `res://addons/foveacore/test/performance_benchmark.gd` à un nœud dans votre scène.
2.  Lancez la scène.
3.  Le benchmark testera différentes distances et niveaux de fovéation, puis sauvegardera les résultats dans `user://proxy_performance_results.csv`.

---

**Astuce** : Surveillez la console Godot pour voir le nombre de splats rendus par frame en temps réel !
