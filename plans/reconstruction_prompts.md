# 🚀 Prompts de Test pour FoveaEngine (StudioTo3D)

Ces prompts sont optimisés pour générer des vidéos 360° sur fond blanc utilisables immédiatement pour la reconstruction Gaussian Splatting.

## 🌳 Catégorie : Végétation (Style Ghibli / Réaliste)
**Prompt :**
> A single ancient bonsai tree with glowing bioluminescent leaves, sitting on a seamless pure white studio background, 360-degree slow orbit camera, ultra-detailed bark texture, photorealistic, 8k, soft shadows only on the ground, centered in frame.
**Usage :** Idéal pour tester la finesse des splats sur les feuilles.

## 🗿 Catégorie : Sculpture & Statues (Détails Géométriques)
**Prompt :**
> A weathered stone gargoyle statue with moss growing in crevices, seamless white studio background, 360-degree steady rotation, cinematically lit, sharp highlights, no floor edges, perfectly centered.
**Usage :** Idéal pour tester le **Mesh Simplifier** et la génération de **PhysicsProxy**.

## 🧥 Catégorie : Personnage Stylisé (Peinture Numérique)
**Prompt :**
> A stylized fantasy warrior character in ornate golden armor, digital painting style with visible brushstrokes, standing on white void, 360 orbit camera, saturated colors, high contrast, clean silhouette.
**Usage :** Idéal pour tester le **NeuralStyleBridge** et l'esthétique "Peinture" du moteur.

## 📦 Catégorie : Props de Jeu (Interaction)
**Prompt :**
> An intricate steampunk treasure box with rotating gears and brass fittings, crystal glowing inside, white studio backdrop, 360-degree view, macro photography detail, no background clutter.
**Usage :** Idéal pour tester la gestion des reflets (Specular) dans les splats.

---

### 💡 Conseils pour de meilleurs résultats :
1. **Format** : Toujours demander "360-degree orbit" ou "turntable".
2. **Fond** : Le "Seamless white studio" est le plus facile à détourer avec mon mode **Smart Studio**.
3. **Mouvement** : Évitez les "Camera shake" ou les zooms brusques.
