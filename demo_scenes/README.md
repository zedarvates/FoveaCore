# FoveaEngine — Demo Scenes (Section 20)

## Available Demos

### 1. Forêt Vivante (item 351)
Animated foliage with flow field WIND + LEAVES layer.
Setup: `FoveaFlowFieldAnimator` preset WIND on tree splats.

### 2. Rideau au Vent (item 352)
Cloth curtain driven by flow + cloth simulation.
Setup: `FoveaFlowFieldAnimator` + cloth Verlet solver.

### 3. Blob Organique (item 353)
Morph covariance BREATHE animation on organic shape.
Setup: `FoveaMorphCovarianceAnimator` morph_type BREATHE.

### 4. Surface d'Eau (item 354)
Water surface with WOBBLE + water splats.
Setup: `FoveaMorphCovarianceAnimator` morph_type WOBBLE.

### 5. Flamme Volumétrique (item 355)
Flipbook animation with emission overlay.
Setup: `FoveaFlipbookAnimator` + emission material.

### 6. Sort Magique VR (item 356)
Flipbook + emission for magic spell effects.
Setup: VR scene with `FoveaFlipbookAnimator`.

### 7. Créature Riggée (item 357)
Skinned character with idle/walk animation.
Setup: `FoveaCharacterWizard` + skeleton animation.

### 8. Scène Scannée Vivante (item 358)
StudioTo3D reconstruction + neural offset breathing.
Setup: Neural offset field on captured scene.

## Hub (item 359-360)
Open `demo_desktop.tscn` and use the scene selector
to switch between demos.
