# 🚀 Prompts de Test pour FoveaEngine (StudioTo3D)

Ces prompts sont optimisés pour générer des vidéos 360° sur fond blanc ou des vidéos de survol drone utilisables immédiatement pour la reconstruction Gaussian Splatting (3DGS) avec une rigidité et une stabilité géométrique optimales.

---

## 🌊 1. Catégorie : Dynamique & Fluides (Rivière & Cascade)
*Idéal pour tester la reconstruction d'écoulements fluides (STAR 4D/Vista4D), la translucidité de l'eau, les éclaboussures et la séparation entre éléments fixes (roches) et mobiles (eau).*

### Option A : Survol rectiligne d'un canyon avec cascades (Écoulement constant)
*La caméra avance en ligne droite à vitesse constante, parfait pour reconstituer l'écoulement temporel d'une cascade dans son canyon.*
> **Prompt :** A photorealistic, high-resolution aerial drone video flying slowly and steadily forward down a rocky forest canyon, tracking a river with active waterfalls. The surrounding basalt cliffs, canyon walls, pine trees, and large mossy rocks are completely static and rigid. Only the water in the river is flowing naturally, cascading over rocks with consistent white water and mist. Overcast daylight with soft, diffuse, shadowless lighting. Extremely stable flight, no camera wobble, no morphing of rocks, 4k.

### Option B : Orbite circulaire autour d'une cascade principale
*Met l'accent sur une seule grande cascade en orbite 360° pour tester la cohérence de la reconstruction de l'eau sous différents angles.*
> **Prompt :** A stable aerial drone video performing a smooth, continuous 360-degree orbit around a large waterfall pouring into a deep pool. The surrounding mossy cliffs and rocky terrain are completely rigid and stationary, showing zero deformation. The water flows and splashes consistently. The drone flies at a constant speed, altitude, and distance, keeping the waterfall centered. Consistent natural daylight, sharp focus on the water spray and wet rock textures, no camera shake, photorealistic, 4k.

---

## 🏰 2. Catégorie : Survol Drone (Château Médiéval)
*Idéal pour tester la reconstruction d'environnements à grande échelle, de textures de pierre complexes, de reliefs de terrain et d'éclairages extérieurs.*

### Option A : Orbite complète par temps nuageux (Recommandé pour NeRF)
*L'éclairage diffus (overcast) supprime les ombres portées dures et mouvantes, ce qui facilite grandement la reconstruction 3D.*
> **Prompt :** A photorealistic, high-resolution aerial drone video performing a smooth, continuous 360-degree orbit around a static medieval stone castle perched on a rocky hill. The weather is overcast with soft, diffuse, shadowless daylight. The camera moves slowly at a constant speed, altitude, and distance, keeping the entire castle perfectly centered. The entire environment is completely static, with no moving trees, no wind, no clouds moving, and no people. High detail, crisp stone textures, stable gimbal, 4k.

### Option B : Spirale descendante rapprochée (Détails des Tours et Cour)
*Permet de capturer à la fois les façades extérieures et les détails intérieurs de la cour.*
> **Prompt :** A stable aerial drone footage executing a slow, steady descending spiral trajectory around a medieval castle's central tower and inner courtyard. Complete physical rigidity, no morphing of structures. Bright, consistent daylight. The drone maintains a smooth, locked flight path with no sudden camera turns or adjustments. Every brick, battlement, and wooden drawbridge is static and sharp. No camera shake, high-end drone gimbal capture, photorealistic, 4k.

---

## 🧸 3. Catégorie : Jouets & Objets Réels (Style Furby)
*Idéal pour valider la reconstruction de formes douces, de textures de fourrure/tissu et de couleurs vives.*

**Prompt :**
> A photorealistic plush toy (similar to a Furby) standing completely static and rigid in the center of the frame. Pure, seamless, uniform white studio background with soft neutral lighting. The camera performs a slow, smooth, continuous 360-degree horizontal orbit around the plush toy at a constant speed and distance, keeping it perfectly centered for a full rotation. No morphing, no shape changes, no camera shake, sharp focus, 4k.

---

## 🏺 4. Catégorie : Sculpture & Céramique (Détails Géométriques)
*Idéal pour valider la reconstruction de formes solides, de reliefs et de matériaux rugueux.*

**Prompt :**
> A highly detailed marble sculpture of a classical bust, completely static and rigid. The sculpture is alone in the center of a pure, seamless white studio background with soft neutral lighting. The camera performs a smooth, continuous 360-degree orbit around the bust at a constant height and distance, keeping the sculpture perfectly centered. Extremely consistent geometry, no morphing, no shape warping, photorealistic, sharp focus.

---

## 📷 5. Catégorie : Props Métalliques (Détails Mécaniques / Réflectivité)
*Idéal pour tester la gestion de la spécularité et de la réflectivité des splats.*

**Prompt :**
> A vintage mechanical camera with brass and black leather details, sitting completely static and rigid. The camera is alone in the center of a pure, seamless white studio background. Soft neutral studio lighting with minimal reflection shifts. The camera performs a slow, continuous 360-degree horizontal orbit around the vintage camera at a constant distance, keeping it perfectly centered. Rigid body, no warping, photorealistic, macro details.

---

## 🚫 Paramètres Négatifs (si disponibles)
> morphing, changing shape, warping, deformation, camera shake, zoom in, zoom out, moving lights, shifting reflections, shadows moving on the background, background details, floor lines, horizon lines, moving clouds, wind blowing tree branches too heavily.
