# 🎭 Markerless Motion Capture & Dynamic Splats Integration Plan — FoveaEngine

> **Date :** 2026-06-22 | **Auteurs :** Antigravity & FoveaEngine Team
>
> Ce document définit l'architecture technique pour intégrer un pipeline complet de capture de mouvement sans marqueurs (Markerless Mocap) pour corps et visage, permettant d'animer des avatars 3D Gaussian Splatting (3DGS) en temps réel à 90 FPS en réalité virtuelle sous Godot.

---

## 1. CONTEXTE ET OBJECTIF

La mise à jour **Unreal Engine 5.8 (MetaHuman Markerless Mocap)** démontre la puissance de la capture de mouvement basée sur une simple vidéo monoculaire pour animer des visages et des corps haute fidélité. 

Actuellement, FoveaEngine dispose d'un système d'animation squelettique très basique dans `FoveaSplatAnimator.cs` :
- **Calcul CPU** : Les transformations squelettiques sont appliquées en C# sur le CPU pour chaque splat par frame.
- **Skinning rigide** : Chaque splat est lié à 100% à l'os le plus proche (pas de transition fluide entre les articulations).
- **Limitation** : Ce goulot d'étranglement CPU empêche d'animer des avatars complexes de millions de splats en VR (framerate < 30 FPS).

### Objectif du plan :
1. Déporter tout le calcul de déformation (Skinning et Blendshapes) sur le **GPU via des Compute Shaders GLSL/Rust GDExtension**.
2. Développer un **Bridge Mocap Python** (MediaPipe/RTMPose) pour extraire squelette et blendshapes depuis une vidéo.
3. Implémenter un protocole **Live Link pour Godot** afin d'ingérer du tracking en direct (webcam ou smartphone).
4. Créer un **système de rigging automatique** pour lier intelligemment les splats 3DGS au squelette de jeu.

---

## 2. ARCHULTURE GLOBALE DU PIPELINE

```
  [Source Vidéo / Webcam] ou [Smartphone (ARKit)]
            │
            ▼
  ┌──────────────────────────────────────────┐
  │  Python Mocap Bridge (mocap_bridge.py)   │  ◄── Extraction Face/Body
  └──────────────────────────────────────────┘
            │
            ├─→ Live Stream (UDP/WebSockets JSON)
            │     │
            │     ▼
            │  ┌────────────────────────────────────┐
            │  │ Godot Live Link (UDP Receiver)     │  ◄── Ingestion en direct
            │  └────────────────────────────────────┘
            │                     │
            ▼                     ▼
  ┌──────────────────────────────────────────┐
  │  Godot Animation / Skeleton3D Pipeline   │  ◄── Retargeting & Calibration
  └──────────────────────────────────────────┘
            │
            ▼
  ┌──────────────────────────────────────────┐
  │ GPU Compute Shader (Skinning & Morph)    │  ◄── Déformation temps réel
  └──────────────────────────────────────────┘
            │
            ▼
  ┌──────────────────────────────────────────┐
  │ GPU Rasterizer (FoveaSplatDispatcher)    │  ◄── Rendu final (VR 90 FPS)
  └──────────────────────────────────────────┘
```

---

## 3. COMPOSANTS ARCHITECTURAUX

### A. Python Mocap Bridge (`mocap_bridge.py`)
Ce script Python autonome servira de passerelle d'extraction. Il utilisera **MediaPipe Holistic** (ou **RTMPose** en option haute fidélité) pour extraire deux flux de données :
1. **Pose Squelettique (Body Mocap)** : Positions et rotations 3D de 33 points clés du corps, convertis en coordonnées locales pour le squelette Godot.
2. **Blendshapes Faciaux (Face Mocap)** : Extraction de 52 coefficients de déformation faciale compatibles avec le standard **Apple ARKit (Face Blendshapes)** grâce à un résolveur géométrique de landmarks faciaux.

Le script pourra fonctionner en deux modes :
- **Mode Batch** : Analyse d'un fichier vidéo et export d'un fichier `.json` / `.anim` d'animation.
- **Mode Stream** : Capture webcam en temps réel et envoi des frames JSON par paquets UDP à Godot.

---

### B. Godot Live Link Receiver (`fovea_live_link_receiver.gd`)
Un nœud serveur UDP/WebSocket léger en GDScript qui tourne en arrière-plan dans Godot :
- Ingestion des données à haute fréquence (30-60 Hz).
- Décodage des rotations d'os (Quaternions) et application directe au `Skeleton3D` de l'avatar.
- Décodage des poids de blendshapes faciaux et envoi au contrôleur d'expressions de l'avatar.
- **Buffer de jitter** pour lisser les saccades de tracking réseau.

---

### C. Déformation sur GPU (Compute Shaders)

Pour atteindre les performances VR requises, les déformations géométriques doivent s'exécuter sur le GPU juste avant l'étape de tri bitonique et de rendu. Nous introduisons deux Compute Shaders :

#### 1. Skinning Squelettique GPU (`gpu_skinning_compute.glsl`)
Le shader applique le **Linear Blend Skinning (LBS)** ou le **Dual Quaternion Skinning (DQS)**. Chaque splat supporte jusqu'à 4 influences d'os.

```glsl
// gpu_skinning_compute.glsl
layout(local_size_x = 256) in;

struct SplatBaseData {
    vec4 position_scaleX; // Position base (xyz) + Scale X
    vec4 rotation_scaleYZ; // Quaternion base (xyzw) + Scale YZ
};

struct BoneInfluence {
    uvec4 bone_indices;  // Index de 4 os influents
    vec4 bone_weights;   // Poids de ces 4 os (somme = 1.0)
};

layout(binding = 0, std430) readonly buffer BaseSplatBuffer { SplatBaseData splats[]; };
layout(binding = 1, std430) readonly buffer SkinWeightsBuffer { BoneInfluence influences[]; };
layout(binding = 2, std430) readonly buffer BoneMatrices { mat4 bones[]; };

layout(binding = 3, std430) writeonly buffer DeformedSplatBuffer {
    vec4 def_positions[]; // Positions transformées
    vec4 def_rotations[]; // Quaternions transformés
};

void main() {
    uint idx = gl_GlobalInvocationID.x;
    if (idx >= splats.length()) return;

    vec3 pos = splats[idx].position_scaleX.xyz;
    uvec4 b_idx = influences[idx].bone_indices;
    vec4 b_weights = influences[idx].bone_weights;

    // Calcul de la matrice de skinning pondérée (LBS)
    mat4 skin_matrix = bones[b_idx.x] * b_weights.x +
                       bones[b_idx.y] * b_weights.y +
                       bones[b_idx.z] * b_weights.z +
                       bones[b_idx.w] * b_weights.w;

    // Transformation de la position et de l'orientation
    vec4 deformed_pos = skin_matrix * vec4(pos, 1.0);
    mat3 skin_rot = mat3(skin_matrix);
    
    // Convertir la rotation résultante en quaternion et sauvegarder
    // ...
    def_positions[idx] = vec4(deformed_pos.xyz, splats[idx].position_scaleX.w);
}
```

> [!TIP]
> **Dual Quaternion Skinning (DQS)** sera implémenté en option pour éviter l'effet "tuyau de poêle essoré" (perte de volume) aux articulations complexes (coudes, épaules).

#### 2. Morphing Facial GPU (`gpu_blendshapes_compute.glsl`)
Pour le visage, les splats varient autour d'une forme neutre en fonction des 52 blendshapes ARKit.
- Un buffer de deltas stocke les déplacements `(delta_pos, delta_rot, delta_scale)` pour chaque blendshape actif.
- Le Compute Shader additionne les deltas pondérés par les coefficients du Live Link :
  $$\text{Pos}_{\text{finale}} = \text{Pos}_{\text{neutre}} + \sum_{i=1}^{52} W_i \cdot \Delta\text{Pos}_i$$

---

### D. Outil d'Auto-Rigging et de Peinture de Poids

Pour animer un modèle 3DGS reconstruit à partir d'une photo/vidéo (par exemple via WorldMirror 2.0), nous devons lui associer des poids de skinning.
1. **Auto-Rigger Volumétrique** :
   - Import du squelette d'avatar standard (ex: Mixamo / Godot Humanoid).
   - Calcul des influences via une recherche KD-Tree : recherche des $K$ os les plus proches pour chaque splat avec une fonction d'atténuation basée sur la distance géodésique ou volumétrique.
   - Algorithme de diffusion des poids pour assurer des transitions lisses au niveau des articulations.
2. **Éditeur de Peinture de Poids (Weight Painting)** :
   - Intégration d'un pinceau 3D (SplatBrush étendu) dans l'éditeur de Godot pour peindre manuellement l'influence d'un os sélectionné directement sur le nuage de splats.

---

## 4. IMPACT SUR LE FORMAT DE FICHIER (`.fovea`)

Le format `.fovea` actuel (vq-compressé) doit être enrichi pour stocker les métadonnées d'animation sans alourdir le fichier de base :
- **En-tête facultatif d'animation** : Présence ou non de données de skinning.
- **Section Skinning** : Stockage des indices d'os (2 ou 4 octets par splat) et des poids quantifiés (4 octets par splat sous forme de `uint32` compressé).
- **Section Blendshapes** : Stockage compressé des buffers de deltas pour les zones du visage.

---

## 5. PHASES D'IMPLÉMENTATION ET ÉCHÉANCIER

| Phase | Description technique | Durée estimée | Risques & Complexité |
|---|---|---|---|
| **Phase A** | **Backend Python Mocap Bridge**<br>Écriture de `mocap_bridge.py` avec MediaPipe Holistic. Export JSON et flux UDP Live Link. | 3 jours | Faible. API MediaPipe très stable. |
| **Phase B** | **Récepteur Live Link Godot (C#)**<br>Création de `FoveaLiveLinkReceiver.cs`, réception réseau, décodage et retargeting sur un squelette de test Godot. | 3 jours | Moyen. Gestion de la gigue (jitter) et du filtrage temporel. |
| **Phase C** | **Compute Shaders GPU (Rust GDExtension)**<br>Implémentation du Compute Pipeline sous Godot (LBS/DQS) en GLSL. Liaison avec le dispatcher de rendu. | 5 jours | **Élevé**. Synchronisation mémoire GPU, mise à jour des matrices d'os sans bloquer le pipeline graphique. |
| **Phase D** | **Outil d'Auto-Rigging**<br>Création de la classe d'association géométrique Splat-Squelette. Algorithme de diffusion des poids. | 4 jours | Moyen. Obtenir des transitions lisses sans artefacts visuels. |
| **Phase E** | **Interface Éditeur & Enregistrement**<br>Panel de contrôle dans Godot pour calibrer la pose de départ (T-pose/A-pose), enregistrer la mocap et l'exporter en `.anim`. | 3 jours | Faible. Intégration d'UI standard Godot. |

---

## 6. CRITÈRES DE VALIDATION ET PERFORMANCE

1. **Performances VR** : Rendu d'un modèle de 1.5 million de splats animés par squelette complet sous Meta Quest 3 à une fréquence minimale et stable de **90 FPS**.
2. **Latence du Live Link** : Latence de bout en bout (caméra → processing Python → rendu Godot) inférieure à **60 ms** en réseau local.
3. **Précision du Retargeting** : Pas de distorsion majeure ou d'étirement aberrant des ellipses des splats lors des rotations d'articulations (validation via le Dual Quaternion Skinning).

---

*Ce plan sert de base de développement technique pour l'intégration de la capture temps réel dans l'écosystème FoveaEngine.*
