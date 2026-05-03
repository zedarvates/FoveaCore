# Benchmark Format Couleur: RGB565 vs Palette 8-bit + Dithering

## Vue d'ensemble

Ce benchmark compare les performances et la qualité de deux formats de couleur pour le rendu GPU :
- **RGB565** : Format 16-bit natif (5 bits rouge, 6 bits vert, 5 bits bleu)
- **Palette 8-bit + Dithering** : Format 8-bit avec palette de 256 couleurs et tramage Floyd-Steinberg

## Objectifs

1. **Mesurer le temps de rendu GPU** (ms par frame)
2. **Mesurer l'utilisation VRAM** (bytes)
3. **Mesurer la bande passante CPU→GPU** (KB/s)
4. **Calculer la qualité visuelle** (PSNR, SSIM)
5. **Analyser les artefacts de banding**
6. **Comparer les deux formats** avec différentes scènes de test

## Scènes de Test

### 1. Gradients Continus
- Dégradés de couleurs lisses sans banding artificiel
- Teste la capacité à rendre des transitions douces
- Résolution : 512×512 pixels

### 2. Transparence et Alpha Blending
- Dégradé de transparence (alpha)
- Teste la gestion des canaux alpha dans les différents formats
- Résolution : 256×256 pixels

### 3. Mélanges de Couleurs Complexes
- Cercles de couleurs avec dégradés radiaux
- Teste la reproduction des couleurs subtiles
- Résolution : 300×300 pixels

## Architecture

```
addons/foveacore/test/
├── color_format_benchmark.gd          # Benchmark principal
├── test_color_format_benchmark.gd     # Tests unitaires
├── benchmark_report.gd                # Générateur de rapports
├── run_color_benchmark.gd             # Orchestrateur
├── color_format_test_scene.tscn       # Scène de test visuel
└── BENCHMARK_COLOR_FORMAT.md          # Cette documentation
```

## Utilisation

### Exécution Complète

```gdscript
# Charger et exécuter le benchmark complet
var runner = preload("res://addons/foveacore/test/run_color_benchmark.gd").new()
add_child(runner)
runner.run_full_execution()
```

### Benchmark Seul

```gdscript
# Exécuter seulement le benchmark comparatif
var benchmark = preload("res://addons/foveacore/test/color_format_benchmark.gd").new()
add_child(benchmark)

benchmark.test_duration = 10.0          # Secondes par test
benchmark.test_resolutions = [640, 1280, 1920]
benchmark.use_dithering = true
benchmark.save_results = true

benchmark.start_benchmark()
```

### Tests Unitaires Seuls

```gdscript
# Exécuter seulement les tests unitaires
var tests = preload("res://addons/foveacore/test/test_color_format_benchmark.gd").new()
add_child(tests)
# Les tests démarrent automatiquement
```

## Métriques

### 1. Temps de Rendu GPU
Mesure le temps pris pour convertir et rendre chaque frame.
- **RGB565** : Conversion simple, temps constant
- **Palette 8-bit** : Conversion + Dithering, temps variable

### 2. Utilisation VRAM
Taille des données d'image en mémoire vidéo.
- **RGB565** : `largeur × hauteur × 2 bytes`
- **Palette 8-bit** : `largeur × hauteur × 1 byte`
- **Économie attendue** : ~50%

### 3. Bande Passante CPU→GPU
Volume de données transféré par seconde.
- Calculé à partir de la VRAM et du temps de frame
- Impact direct sur les performances globales

### 4. Qualité Visuelle (PSNR/SSIM)

#### PSNR (Peak Signal-to-Noise Ratio)
```
PSNR = 10 × log10(MAX² / MSE)
```
- > 40 dB : Excellente qualité
- 30-40 dB : Bonne qualité
- 20-30 dB : Qualité acceptable
- < 20 dB : Mauvaise qualité

#### SSIM (Structural Similarity Index)
- Plage : [-1, 1]
- > 0.9 : Excellente similarité structurelle
- 0.8-0.9 : Bonne similarité
- < 0.8 : Perte de structure visible

### 5. Artefacts de Banding
Détection de sauts de couleur dans les gradients supposés lisses.
- Score de 0.0 : Aucun banding détecté
- Score > 0.0 : Présence de banding
- Le dithering devrait réduire ce score

## Algorithme de Dithering

### Floyd-Steinberg
```
Pour chaque pixel (x, y) :
  1. Quantifier la couleur (256 couleurs)
  2. Calculer l'erreur = couleur_originale - couleur_quantifiée
  3. Diffuser l'erreur aux pixels voisins :
     - (x+1, y)   : 7/16 × erreur
     - (x-1, y+1) : 3/16 × erreur
     - (x, y+1)   : 5/16 × erreur
     - (x+1, y+1) : 1/16 × erreur
```

## Résultats Attendus

### Scénario 1: Haute Résolution (1920×1080)
- **RGB565** : ~60 FPS, 4 MB VRAM
- **Palette** : ~70 FPS, 2 MB VRAM
- **PSNR** : 25-30 dB (qualité réduite mais acceptable)

### Scénario 2: Résolution Moyenne (1280×720)
- **RGB565** : ~90 FPS, 1.8 MB VRAM
- **Palette** : ~110 FPS, 0.9 MB VRAM
- **PSNR** : 28-33 dB (bon compromis)

### Scénario 3: Basse Résolution (640×360)
- **RGB565** : ~144 FPS, 0.45 MB VRAM
- **Palette** : ~155 FPS, 0.23 MB VRAM
- **PSNR** : 30-35 dB (excellente qualité)

## Interprétation

### Quand utiliser RGB565 ?
- Qualité visuelle primordiale
- Pas de contrainte VRAM stricte
- Pas de besoin de hautes performances
- Scènes avec dégradés très subtils

### Quand utiliser Palette 8-bit ?
- Contraintes VRAM strictes (mobile, VR)
- Besoin de performances maximales
- Qualité "acceptable" suffisante
- Scènes avec couleurs limitées
- Le dithering masque bien les artefacts

## Optimisations

### Pour RGB565
- Utiliser le GPU pour la conversion
- Minimiser les transferts CPU→GPU
- Batching des draw calls

### Pour Palette 8-bit
- Pré-calculer la palette optimale
- Utiliser des textures palettisées natives
- Optimiser l'algorithme de dithering (SIMD)
- Palette adaptative par scène

## Limitations

1. **Palette 8-bit**
   - Maximum 256 couleurs simultanées
   - Banding possible dans les dégradés subtils
   - Moins adapté pour les photos réalistes

2. **RGB565**
   - Banding inhérent (5-6 bits par canal)
   - Moins précis que RGBA8/16-bit
   - Conversion nécessaire depuis RGBA8

## Références

- Floyd-Steinberg Dithering: https://en.wikipedia.org/wiki/Floyd%E2%80%93Steinberg_dithering
- PSNR: https://en.wikipedia.org/wiki/Peak_signal-to-noise_ratio
- SSIM: https://en.wikipedia.org/wiki/Structural_similarity
- Godot Viewports: https://docs.godotengine.org/en/stable/tutorials/viewports/index.html

## Dépannage

### Le benchmark est trop lent
- Réduire `test_duration`
- Réduire les résolutions testées
- Désactiver le dithering

### Les résultats varient beaucoup
- Fermer les applications en arrière-plan
- Vérifier la température GPU
- Augmenter `test_duration`

### La qualité est mauvaise
- Vérifier que le dithering est activé
- Ajuster les paramètres de la palette
- Considérer RGB565 si la qualité est critique

## Licence

Code open source - utilisable librement dans vos projets.