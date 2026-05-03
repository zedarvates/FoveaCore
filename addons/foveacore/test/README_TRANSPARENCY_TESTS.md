# Tests de Transparence et Mélange de Splats - FoveaEngine

## Vue d'ensemble

Ce dossier contient les tests de validation pour le rendu des Gaussian Splats avec transparence et palette 8-bit.

## Fichiers de Test

### 1. `transparency_blend_test.gd`
Script principal de test automatisé. Valide 5 aspects critiques :

#### Test 1: Superposition de splats semi-transparents
- Crée 5 couches de splats avec alpha = 0.3
- Valide l'accumulation correcte de la transparence
- Teste le blending additif vs alpha blending
- **Critère de succès**: Pas d'artefacts de z-fighting, alpha cumulé correct

#### Test 2: Mélange de couleurs avec opacité variable
- Dégradé rouge→bleu avec alpha croissant (0.2 → 1.0)
- Mélange de couleurs complémentaires (RGB, CMY) avec alpha = 0.5-0.7
- Rampe d'opacité sur même couleur (8 étapes)
- **Critère de succès**: Transition douce, pas de banding

#### Test 3: Effets de profondeur (z-ordering)
- 7 splats à différentes profondeurs (z = -3 à +3)
- Test de chevauchement complexe (4 splats entrelacés)
- **Critère de succès**: Respect strict de l'ordre Z, pas de flickering

#### Test 4: Artefacts de transparence avec palette limitée
- Dégradé continu (32 étapes) vs palette 16 couleurs
- Couleurs limites (noir/blanc purs avec alpha)
- Test de banding artificiel (16 niveaux de gris)
- **Critère de succès**: Banding minimal, respect des limites de palette

#### Test 5: Comparaison visuelle RGB565 vs Palette 8-bit
- 8 couleurs de test (primaires, secondaires, gris)
- Comparaison RGB565 (5-6-5 bits) vs Palette (8-bit indexé)
- Test avec transparence (4 niveaux d'alpha)
- **Critère de succès**: Erreur de couleur acceptable (< 5%)

### 2. `transparency_blend_scene.tscn`
Scène Godot prête à l'emploi pour exécution interactive.

### 3. `color_format_benchmark.gd` (existant)
Benchmark de performance RGB565 vs Palette.
Mesure FPS, VRAM, bande passante, PSNR, SSIM.

## Exécution

### Mode Automatisé
```gdscript
# Depuis l'éditeur Godot
var test = preload("res://addons/foveacore/test/transparency_blend_test.gd").new()
add_child(test)
# Les tests s'exécutent automatiquement au _ready()
```

### Mode Scène Interactive
1. Ouvrir `transparency_blend_scene.tscn`
2. Exécuter la scène (F6)
3. Observer les 5 zones de test

### Mode Benchmark
```gdscript
var bench = preload("res://addons/foveacore/test/color_format_benchmark.gd").new()
add_child(bench)
bench.start_benchmark()
```

## Résultats Attendus

### Transparence (Test 1)
- **Alpha blending**: `blend_mix` dans le shader
- **Cumul alpha**: `alpha_total = 1 - (1 - alpha)^n`
- **Profondeur**: `depth_draw_never` + tri CPU

### Mélange de Couleurs (Test 2)
- **Espace couleur**: Linéaire (non sRGB)
- **Interpolation**: LERP dans l'espace RGB
- **Précision**: 32-bit float interne → 8-bit final

### Z-Ordering (Test 3)
- **Tri**: MultiMesh trié par profondeur (distance caméra)
- **Stabilité**: Pas de flickering à ±0.001 unité
- **Performance**: O(n log n) avec n = splat_count

### Artefacts Palette (Test 4)
- **Dithering**: Floyd-Steinberg optionnel
- **Banding**: Détection par gradient local
- **Limite**: 16 couleurs = 4 bits par canal

### RGB565 vs Palette (Test 5)
| Format | Bits/Pixel | Canal R | Canal G | Canal B | Alpha |
|--------|-----------|---------|---------|---------|-------|
| RGB565 | 16 | 5 bits | 6 bits | 5 bits | Non |
| Palette| 8+ | 8 bits* | 8 bits* | 8 bits* | 8 bits |

*Via table de correspondance (256 entrées max)

## Métriques de Qualité

### PSNR (Peak Signal-to-Noise Ratio)
- > 40 dB: Excellent (indiscernable)
- 30-40 dB: Bon (léger bruit)
- 20-30 dB: Acceptable (bruit visible)
- < 20 dB: Mauvais (distorsion forte)

### SSIM (Structural Similarity)
- > 0.98: Excellent
- 0.95-0.98: Bon
- 0.90-0.95: Acceptable
- < 0.90: Mauvais

### Banding Score
- < 0.01: Aucun artefact
- 0.01-0.05: Léger
- 0.05-0.10: Modéré
- > 0.10: Sévère

## Optimisations

### Shader (`splat_render_triangle.gdshader`)
- `blend_mix`: Alpha blending standard
- `depth_draw_never`: Pas d'écriture Z (tri CPU)
- `cull_disabled`: Désactivé pour transparence
- `unshaded`: Pas d'ombrage (couleurs pures)

### Pipeline de Rendu
1. Tri CPU des splats par profondeur
2. Upload MultiMesh (GPU)
3. Shader vertex: Étirement ellipse
4. Shader fragment: Alpha + couleur
5. Blending hardware

## Problèmes Connus

1. **Z-fighting**: À moins de 0.001 unité de profondeur
   - Solution: Légère perturbation aléatoire

2. **Banding 8-bit**: Sur gradients continus
   - Solution: Dithering Floyd-Steinberg

3. **Overdraw**: Multiples couches transparentes
   - Solution: Limiter à ~10 couches

4. **Précision RGB565**: Perte sur rouge/bleu
   - Solution: Palette 8-bit pour qualité

## Références

- [Gaussian Splatting Paper](https://arxiv.org/abs/2303.00788)
- Godot 4.x: Viewport, MultiMesh, ShaderMaterial
- Floyd-Steinberg Dithering: [Wiki](https://en.wikipedia.org/wiki/Floyd%E2%80%93Steinberg_dithering)