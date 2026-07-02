# 🤖 Pont Hermes & Blender Bridge Design — FoveaEngine

> **Date :** 2026-06-22 | **Auteurs :** Antigravity & FoveaEngine Team
>
> Ce document définit l'architecture système de la passerelle entre l'agent autonome **Hermes** (LLM orchestrateur), l'environnement de modélisation 3D **Blender**, et le moteur de rendu temps réel **Godot (FoveaEngine)**. Ce pont permet la génération et le placement d'assets 3D en temps réel à la voix ou en langage naturel.

---

## 1. VISION D'ENSEMBLE

L'agent autonome Hermes agit comme le "cerveau". Lorsqu'un utilisateur formule une requête en langage naturel (par exemple: *"Ajoute une chaise en bois médiévale et place-la près de la table"*), l'agent :
1. Détermine s'il faut générer un modèle géométrique ou lancer une reconstruction photogrammétrique.
2. Écrit et envoie un script d'automatisation Python à Blender pour modéliser/assembler l'objet et l'exporter.
3. Indique à Godot d'importer l'asset et de le placer précisément dans la scène active avec les propriétés physiques appropriées.

```
  ┌─────────────────┐
  │  Agent HERMES   │ (LLM / Orchestrateur)
  └────────┬────────┘
           │
           │ JSON-RPC sur WebSockets
           ▼
  ┌────────────────────────────────────────────────────────┐
  │           Fovea Bridge Router (Port 8765)              │
  │     (Géré par FoveaCoreManager / WebSocketServer)       │
  └────────┬───────────────────────────────┬───────────────┘
           │                               │
           ▼ (Contrôle Script Python)       ▼ (Commandes de Scène)
  ┌─────────────────┐            ┌──────────────────┐
  │ Blender Process │            │   Godot Engine   │ (FoveaEngine)
  │ (Générateur 3D) │            │ (VR Simulation)  │
  └────────┬────────┘            └────────▲─────────┘
           │                              │
           └──── Export .PLY / .FOVEA ────┘
```

---

## 2. SPÉCIFICATIONS DU PROTOCOLE (JSON-RPC 2.0)

La communication s'effectue via un serveur WebSocket hébergé par FoveaEngine dans Godot. Les messages échangés utilisent le format JSON-RPC 2.0 standard.

### Exemples de requêtes

#### 1. Commande de génération envoyée à Blender
```json
{
  "jsonrpc": "2.0",
  "method": "blender.generate_mesh",
  "params": {
    "prompt": "medieval wooden chest",
    "export_format": "ply",
    "destination_path": "res://reconstructions/chest.ply",
    "poly_count_target": 5000
  },
  "id": 101
}
```

#### 2. Commande d'importation envoyée à Godot
```json
{
  "jsonrpc": "2.0",
  "method": "fovea.instantiate_asset",
  "params": {
    "file_path": "res://reconstructions/chest.ply",
    "position": [1.5, 0.0, -2.0],
    "rotation": [0.0, 45.0, 0.0],
    "scale": [1.0, 1.0, 1.0],
    "enable_physics": true,
    "physics_preset": "wood"
  },
  "id": 102
}
```

#### 3. Requête d'analyse spatiale envoyée par Hermes
```json
{
  "jsonrpc": "2.0",
  "method": "fovea.get_scene_layout",
  "params": {},
  "id": 103
}
```
**Réponse de Godot :**
```json
{
  "jsonrpc": "2.0",
  "result": {
    "scene_name": "VR_Living_Room",
    "objects": [
      {
        "name": "Medieval_Table",
        "class": "StaticBody3D",
        "aabb": {"center": [0.0, 0.5, -2.0], "size": [2.0, 1.0, 1.0]}
      }
    ]
  },
  "id": 103
}
```

---

## 3. COMPOSANTS LOGICIELS

### A. Routeur WebSocket Godot (`fovea_hermes_bridge.gd`)
Ce script s'enregistre comme un service réseau persistant (Autoload) dans Godot.
- **Gestionnaire de connexions** : Écoute sur `ws://localhost:8765`.
- **Analyseur de commandes** : Valide le schéma des messages JSON-RPC entrants et redirige les requêtes.
- **Sécurité** : Filtre les chemins de fichiers pour s'assurer qu'ils restent dans le dossier du projet (`res://` ou `user://`).

### B. Addon d'automatisation Blender (`fovea_blender_listener.py`)
Un script Python exécuté en arrière-plan dans Blender (`blender --background --python fovea_blender_listener.py`) :
- Se connecte en tant que client WebSocket au routeur de Godot.
- Exécute des scripts de création procédurale de géométries ou appelle des générateurs IA (comme Stable Projectils / DreamGaussian) installés localement.
- Gère l'export automatisé au format compatible `.ply` (couleurs par sommet) ou `.fovea` (via l'appel du compilateur CLI Rust).

---

## 4. CAS D'UTILISATION TYPIQUES

### Scénario : "Génération interactive à la volée"
1. L'utilisateur en VR prononce la phrase : *"Hermes, mets une petite tasse rouge sur la table devant moi."*
2. Godot envoie la position du regard et les coordonnées de la table à Hermes.
3. Hermes envoie à Blender la commande de générer une tasse avec la texture rouge correspondante.
4. Blender modélise l'objet en 2 secondes, l'exporte en `res://user/tasse_rouge.ply`.
5. Hermes commande à Godot de charger `tasse_rouge.ply`, de la convertir en splats et de la placer sur la table à l'aide de la physique intégrée pour qu'elle repose naturellement sur sa surface.

---

## 5. PHASES D'IMPLÉMENTATION

1. **Jalon 1 (Réseau)** : Écriture du serveur WebSocket dans `fovea_hermes_bridge.gd` et validation des requêtes ping/pong avec un script de test Python.
2. **Jalon 2 (Blender Automation)** : Écriture de `fovea_blender_listener.py` et validation de la génération procédurale d'un objet simple exporté directement dans Godot.
3. **Jalon 3 (Orchestration LLM)** : Connexion de l'agent Hermes au serveur WebSocket pour valider l'analyse de scène Godot en direct.

---

*Spécification adoptée le 2026-06-22 pour guider la conception de l'infrastructure d'agents autonomes.*
