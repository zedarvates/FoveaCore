# 🗺️ FoveaEngine — Les 400 Prochaines Tâches (2026-07-09)

> Décomposition au niveau implémentation des ~98 chantiers ouverts de
> `TOP_TASKS.md`. Là où `TOP_TASKS.md` dit "Portage GPU compute du flow field",
> ce fichier liste les 10 étapes concrètes pour y arriver. Traçabilité :
> `[T-##]` = tâche parente dans `TOP_TASKS.md`, `[BL-###]` = item d'origine
> dans `ROADMAP_COMPLETE_BACKLOG.md`. Ordre global ≈ ordre d'exécution
> recommandé (les sections 1 à 7 conditionnent la valeur de tout le reste).

---

## Section 1 — Vérification & consolidation post-Phase 7 (1-15) `[T-1..6]` 🔴

- [ ] 1. Exécuter `test_animation_subsystem.gd` dans Godot et corriger toute erreur.
- [ ] 2. Exécuter `test_flow_field_animator.gd` et corriger.
- [ ] 3. Exécuter `test_morph_covariance_animator.gd` et corriger.
- [ ] 4. Exécuter `test_material_oscillation.gd` et corriger.
- [ ] 5. Exécuter `test_lod_stretch_animator.gd` et corriger.
- [ ] 6. Exécuter `test_flipbook_animator.gd` et corriger.
- [ ] 7. Exécuter `test_neural_offset_field.gd` et corriger.
- [ ] 8. Exécuter `test_bone_skin_animation.gd` — valider chaque appel `Skeleton3D` (risque max du batch).
- [ ] 9. Ouvrir le projet dans l'éditeur et vérifier la compilation de `splat_render_triangle.gdshader` (branche `layer_type == 7u`).
- [ ] 10. Vérifier qu'aucun script Phase 7 ne génère de warning de parse au chargement du projet.
- [ ] 11. Lancer `run_all_tests.gd` complet pour vérifier zéro régression sur les tests pré-existants.
- [ ] 12. Ouvrir `test/demo_desktop.tscn` et valider visuellement le rendu de base inchangé.
- [ ] 13. Tester à la main un `FoveaFlowFieldAnimator` (preset WIND) sur un asset `.fovea` réel et confirmer le mouvement visible.
- [ ] 14. Committer la Phase 7 en commits logiques par sous-phase (7.0 → 7.6 + docs).
- [ ] 15. Mettre à jour `CHANGELOG.md` avec l'entrée Phase 7 "Dynamic Splat Animation (CPU foundation)".

## Section 2 — Infrastructure GPU d'animation `splat_animate.glsl` (16-45) `[T-10,13,17,25,29]` 🟡

- [ ] 16. Concevoir le layout du buffer d'animation GPU : document de spec (offsets, formats, bits `anim_flags`) dans `docs/developer_reference.md`.
- [ ] 17. Réserver 4 bits du padding de `data3` pour `anim_flags` (type d'animation par splat) et documenter le masque.
- [ ] 18. Écrire le squelette de `shaders/splat_animate.glsl` : pass compute no-op qui copie `splat_buffer_base` → `splat_buffer_animated`.
- [ ] 19. Créer le double buffer dans `gpu_culler_pipeline.gd` : buffer base immuable + buffer animé réécrit chaque frame.
- [ ] 20. Faire lire le buffer animé (et non le base) par `gpu_culling_compute.glsl`.
- [ ] 21. Faire lire le buffer animé par `depth_precompute.glsl` (les clés de profondeur doivent refléter les positions animées).
- [ ] 22. Intégrer le dispatch de `splat_animate.glsl` dans le graphe de soumissions groupées existant (grouping D2, zéro `rd.sync` supplémentaire).
- [ ] 23. Pousser les uniforms globaux `anim_time`, `anim_global_intensity`, `anim_enabled` depuis `FoveaAnimationSubsystem`.
- [ ] 24. Court-circuit : si `anim_enabled == false`, bypasser le pass et pointer le culling directement sur le buffer base (zéro coût).
- [ ] 25. Garde null : désactivation propre du pass si `RenderingDevice` indisponible (Compatibility/headless).
- [ ] 26. Ajouter des timestamps GPU (`rd.capture_timestamp`) autour du pass d'animation.
- [ ] 27. Créer `test/test_splat_animate_pass.gd` : vérifier copie bit-exacte en mode no-op sur un buffer synthétique.
- [ ] 28. Vérifier le budget : pass no-op < 0,1 ms pour 1M splats (mesure timestamps).
- [ ] 29. Brancher le toggle à chaud sans réallocation de buffers (test aller-retour on/off/on).
- [ ] 30. Exposer les stats du pass (temps GPU, splats animés) dans le panneau `FoveaStats` existant.
- [ ] 31. Implémenter le mode `ANIM_FLOW` dans `splat_animate.glsl` : `Δpos = f(pos, time)` en curl-noise (portage de la logique CPU 7.1).
- [ ] 32. Porter la modulation par `layer_id` (poids par layer) dans le shader.
- [ ] 33. Créer un uniform buffer de paramètres par-animateur (amplitude, fréquence, preset) partagé CPU→GPU.
- [ ] 34. Valider la parité CPU/GPU : même splat, même temps → offsets identiques à ε près (test dédié).
- [ ] 35. Implémenter le mode `ANIM_STRETCH` (pulsation log-space de la taille) dans le shader.
- [ ] 36. Implémenter la phase per-splat par hash de position dans le shader (parité avec le CPU).
- [ ] 37. Gérer la cohérence du tri : re-tri complet tous les N frames quand l'animation est active, tri partiel sinon.
- [ ] 38. Mesurer l'impact du re-tri sous animation active sur 100k/500k/1M splats et documenter.
- [ ] 39. Ajouter la coupure fovéatée GPU : lire `fovea_gaze_left/right` dans `splat_animate.glsl` et atténuer l'amplitude hors zone de regard.
- [ ] 40. Test visuel de l'animation fovéatée : amplitude pleine au centre du regard, nulle en périphérie.
- [ ] 41. Chemin de repli : si le pass GPU échoue à l'init, retomber automatiquement sur les animateurs CPU existants.
- [ ] 42. Sélecteur `animation_backend` (`CPU`/`GPU`/`AUTO`) exporté sur `FoveaAnimationSubsystem`.
- [ ] 43. Vérifier le fonctionnement stéréo VR (les deux vues lisent le même buffer animé, une seule exécution du pass par frame).
- [ ] 44. Benchmark final infra : 1M splats animés en `ANIM_FLOW` ≤ 0,5 ms GPU (objectif roadmap), rapport dans `docs/benchmark.md`.
- [ ] 45. Documenter l'architecture du pass dans `docs/ANIMATED_SPLATS.md` (nouveau fichier, section GPU).

## Section 3 — Portage GPU des animateurs restants (46-90) `[T-10,13,17,25,29]` 🟡

- [ ] 46. Morph Covariance GPU : étendre le codebook `covar_texture` pour référencer deux entrées (Σ_base, Σ_target) par splat.
- [ ] 47. Ajouter le side-channel 16 bits/splat (index Σ_target + phase) au format de buffer.
- [ ] 48. Écrire `slerp_covariance()` dans `splat_math.gdshaderinc` : slerp quaternion + lerp log-space du scale.
- [ ] 49. Test unitaire GLSL-parité : vérifier via readback que `slerp_covariance` ne produit jamais de scale ≤ 0.
- [ ] 50. Implémenter `PULSE` GPU (facteur log-space uniforme sur Σ).
- [ ] 51. Implémenter `BREATHE` GPU (axe dominant étendu, axes secondaires contractés).
- [ ] 52. Implémenter `WOBBLE` GPU (jitter quaternion per-splat, axe hashé).
- [ ] 53. Mettre à jour `splat_render.gdshader` et `splat_render_triangle.gdshader` pour lire la covariance interpolée.
- [ ] 54. Valider visuellement la non-dégénérescence à amplitude extrême (0.9) sur 100k splats.
- [ ] 55. Benchmark Morph Covariance GPU : surcoût ≤ 0,15 ms à 1M splats.
- [ ] 56. Flipbook GPU : pousser `anim_time`/`flipbook_fps` en uniform de `gpu_culling_compute.glsl`.
- [ ] 57. Encoder `flipbook_frame` (8 bits) et `flipbook_frame_count` (8 bits) dans le format de splat packé (spec Section 2, item 16).
- [ ] 58. Culler les frames inactives directement dans le compute (compteur atomique inchangé, splat rejeté avant tri).
- [ ] 59. Implémenter le crossfade GPU optionnel (opacité complémentaire entre frame i et i+1).
- [ ] 60. Test : un flipbook 8 frames de 10k splats chacun ne rend que ~10k splats par frame (vérif compteur).
- [ ] 61. Neural Offset GPU : convertir `FoveaNeuralOffsetField` en `Texture3D` RGBA16F à la création de la ressource.
- [ ] 62. Échantillonner la texture 3D en trilinéaire natif dans `splat_animate.glsl` (mode `ANIM_NEURAL`).
- [ ] 63. Gérer la dimension temporelle : atlas de textures 3D ou texture 3D array par frame bakée.
- [ ] 64. Test de parité : sample GPU vs `FoveaNeuralOffsetField.sample()` CPU identiques à ε près.
- [ ] 65. Benchmark Neural Offset GPU vs CPU : documenter le gain (attendu > 100×).
- [ ] 66. Skinning GPU : concevoir le buffer de bones (matrices `pose * rest⁻¹` par bone, uploadé chaque frame).
- [ ] 67. Encoder `bone_indices` (4×u8) et `bone_weights` (4×u8 normalisés) dans le buffer de splats riggés.
- [ ] 68. Implémenter le LBS dans `splat_animate.glsl` : `pos = Σ wᵢ (Bᵢ · bind_pos)`.
- [ ] 69. Implémenter la transformation de covariance GPU : rotation blended appliquée à Σ (`Σ' = R Σ Rᵀ` via le quaternion du skin transform).
- [ ] 70. Upload des matrices de bones : extraire depuis `Skeleton3D` en `PackedFloat32Array` bulk, une écriture par frame.
- [ ] 71. Test de parité skinning CPU/GPU : même pose, même splat → position identique à ε près.
- [ ] 72. Benchmark skinning GPU : 500k splats riggés sur 64 bones ≤ 0,3 ms.
- [ ] 73. Gérer les splats non riggés dans le même buffer (poids nuls → branche early-out).
- [ ] 74. Valider la stéréo VR avec personnage riggé (pas de divergence œil gauche/droit).
- [ ] 75. Cloth GPU : porter le solveur Verlet de `fovea_splat_cloth.gd` en compute shader (positions + prev_positions en SSBO).
- [ ] 76. Implémenter les contraintes de ressorts en passes itératives GPU (N itérations paramétrables).
- [ ] 77. Porter la déchirure (tearing) : désactivation de ressorts via flag atomique quand `rest_len` dépassé.
- [ ] 78. Porter le squish & bounce (Poisson ratio) en GPU.
- [ ] 79. Conserver le mode CPU comme repli et pour les petites simulations (< 1k points).
- [ ] 80. Test cloth GPU : drapeau 32×32 stable à 90 Hz, pas d'explosion numérique sur 10k frames.
- [ ] 81. Flow field peint GPU : définir le format de la texture 3D de flux (32³/64³ RGBA16F, choix par qualité).
- [ ] 82. Écrire le compute de rasterisation des strokes → texture 3D (splatting de capsules orientées).
- [ ] 83. Échantillonner la texture de flux dans le mode `ANIM_FLOW` (branche `CURRENT`).
- [ ] 84. Sérialiser la texture de flux dans le `.fovea` (nouvelle section optionnelle du format).
- [ ] 85. Test : un stroke peint produit un déplacement colinéaire à sa direction dans un rayon donné.
- [ ] 86. Ordonnancement inter-modes : définir l'ordre d'application quand plusieurs `anim_flags` sont actifs sur un même splat (flow → morph → stretch → skin).
- [ ] 87. Test de composition : flow + morph simultanés ne divergent pas sur 1000 frames.
- [ ] 88. Profiler l'ensemble : scène mixte (flow + morph + flipbook + 1 personnage riggé) ≤ 1,0 ms GPU total.
- [ ] 89. Passer les animateurs CPU en mode "authoring only" quand le backend GPU est actif (éviter le double calcul).
- [ ] 90. Documentation complète des modes GPU dans `docs/ANIMATED_SPLATS.md`.

## Section 4 — Outils auteur Phase 7 (91-125) `[T-9,12,19,20,21]` 🟡

- [ ] 91. SplatBrush mode "Flow Paint 3D" : étendre `splat_brush_engine.gd` pour écrire dans la texture 3D de flux (et plus seulement `splat.normal`).
- [ ] 92. Prévisualisation du champ de flux : gizmo de flèches 3D échantillonnant la texture dans le viewport éditeur.
- [ ] 93. Gomme de flux (effacer/atténuer une zone peinte).
- [ ] 94. Undo/redo des strokes de flux via le `UndoRedo` existant du SplatBrush.
- [ ] 95. Support VR du Flow Paint (contrôleur XR = direction du stroke, gâchette = intensité).
- [ ] 96. SplatBrush mode "Covariance Target" : capturer Σ_target après sculpture au clay deformer.
- [ ] 97. UI de morphing : slider de preview interpolant Σ_base → Σ_target en éditeur.
- [ ] 98. Sauvegarder les paires (Σ_base, Σ_target, phase) dans le `.fovea` (section optionnelle).
- [ ] 99. Bouton "Reset Morph" restaurant Σ_base (non-destructivité prouvée par test).
- [ ] 100. Presets nommés Material Oscillation : "Living Watercolor" (config exportée).
- [ ] 101. Preset "Pulsing Metal".
- [ ] 102. Preset "Breathing Wood".
- [ ] 103. Dropdown de presets dans l'inspecteur custom de `FoveaStyle` existant.
- [ ] 104. Live-preview de l'oscillation sur la sphère de preview de l'inspecteur.
- [ ] 105. Brancher `FoveaLodStretchAnimator` dans `fovea_hybrid_lod_controller.gd` (amplitude pilotée par le niveau de LOD).
- [ ] 106. Courbe d'amplitude par distance exportée (`Curve` Godot) pour le LOD stretch.
- [ ] 107. Injecter la caméra active dans `FoveaAnimationSubsystem.apply()` pour la variante CPU de l'animation fovéatée.
- [ ] 108. Panneau éditeur "Animation" : dock listant les animateurs actifs, leurs cibles et leurs coûts mesurés.
- [ ] 109. Boutons play/pause/scrub du temps d'animation global en éditeur (hors runtime).
- [ ] 110. Gizmo par animateur : volume d'influence visualisé (sphère BREATHE, AABB du neural field, etc.).
- [ ] 111. Inspector plugin pour `FoveaNeuralOffsetField` : visualisation des vecteurs de la grille.
- [ ] 112. Éditeur de `layer_weights` ergonomique (liste layer → slider) au lieu du Dictionary brut.
- [ ] 113. Templates de nodes : "Add Wind Zone", "Add Breathing Zone" dans le menu de création de nodes.
- [ ] 114. Duplication d'animateur avec offsets (pour peupler une forêt de zones de vent variées).
- [ ] 115. Randomisation par seed exportée sur les animateurs (reproductibilité des démos).
- [ ] 116. Documentation utilisateur de chaque outil auteur (section dans `docs/ANIMATED_SPLATS.md`).
- [ ] 117. Import flipbook : dialogue "Import Splat Sequence" acceptant un dossier de `.ply`/`.fovea`.
- [ ] 118. Tagger automatiquement `flipbook_frame`/`flipbook_frame_count` au chargement de la séquence.
- [ ] 119. Tri des frames par nom de fichier naturel (frame_001, frame_002…).
- [ ] 120. Validation d'homogénéité de la séquence (nombre de splats comparable entre frames, warning sinon).
- [ ] 121. Préréglage fps du flipbook déduit des métadonnées si présentes, sinon 12 fps.
- [ ] 122. Preview du flipbook en éditeur (lecture dans le viewport sans lancer le jeu).
- [ ] 123. Export d'un flipbook assemblé en un seul `.fovea` multi-frames (nouvelle section du format).
- [ ] 124. Chargement du `.fovea` multi-frames par `fovea_asset_loader.gd` (et le fast-path Rust).
- [ ] 125. Test d'aller-retour : import dossier → export `.fovea` → rechargement → frames identiques.

## Section 5 — Pipeline neural offline (126-145) `[T-22,23,24]` 🟡

- [ ] 126. Spécifier le format d'échange du champ d'offsets baké (JSON/NPZ → `FoveaNeuralOffsetField.tres`).
- [ ] 127. Script Python `tools/bake_offset_field.py` : convertit un champ de vecteurs NumPy en ressource Godot.
- [ ] 128. Étendre `neural_style_bridge.gd` : requête ComfyUI "generate motion field" avec workflow JSON dédié.
- [ ] 129. Workflow ComfyUI de référence produisant un champ de flux 2.5D depuis une image (depth + optical flow estimé).
- [ ] 130. Relèvement 2.5D → 3D : projeter le flux image dans la grille 3D via la depth map.
- [ ] 131. Import automatique : le bridge dépose le `.tres` et l'assigne à un `FoveaNeuralOffsetAnimator`.
- [ ] 132. Distillation STAR : script Python extrayant le mouvement inter-frames du cache temporel causal existant.
- [ ] 133. Conversion du mouvement STAR en frames de `FoveaNeuralOffsetField` (grille + N frames temporelles).
- [ ] 134. Test end-to-end : vidéo courte → STAR → champ baké → scène Godot animée.
- [ ] 135. Paramètres de baking exposés (résolution de grille, nombre de frames, lissage).
- [ ] 136. Lissage temporel du champ baké (filtre gaussien sur l'axe temps) pour éviter le jitter.
- [ ] 137. Compression du champ baké (quantification FP16) avant sérialisation.
- [ ] 138. Documentation du pipeline de baking dans `docs/ANIMATED_SPLATS.md`.
- [ ] 139. Runtime MLP — étude : choisir l'encodage (hash-grid réduit vs Fourier features) et dimensionner le réseau (2-3 couches).
- [ ] 140. Implémenter l'évaluation du MLP en compute shader (poids en uniform buffer, ~4-16 Ko).
- [ ] 141. Script d'entraînement Python du MLP sur les champs STAR distillés (supervision = champ baké).
- [ ] 142. Export des poids entraînés vers le format uniform buffer.
- [ ] 143. Comparaison qualité/coût : MLP runtime vs texture bakée (PSNR du champ, ms GPU).
- [ ] 144. Décision documentée : garder le MLP runtime ou rester en baké selon les résultats.
- [ ] 145. Article court "AI-driven splat motion in Godot" si les résultats sont probants.

## Section 6 — Flipbook 4D & pont StudioTo3D (146-160) `[T-15,16]` 🟡

- [ ] 146. Mode "4D Capture" dans le panel StudioTo3D : case à cocher "reconstruire chaque frame".
- [ ] 147. Boucle de reconstruction par frame via le backend existant (WorldMirror/DVLT), sortie = dossier de `.ply` numérotés.
- [ ] 148. Estimation du coût et warning UI (N frames × temps de reconstruction unitaire).
- [ ] 149. Alignement inter-frames : recaler chaque reconstruction sur la première (ICP simplifié ou poses caméra partagées).
- [ ] 150. Nettoyage batch : appliquer `FoveaSplatCleaner` sur chaque frame automatiquement.
- [ ] 151. Assemblage automatique en flipbook (réutilise l'import Section 4, items 117-124).
- [ ] 152. Déduplication temporelle : détecter les splats statiques entre frames et les sortir du flipbook (couche BASE fixe + couche ANIM).
- [ ] 153. Mesurer le gain de la déduplication (mémoire et splats rendus/frame).
- [ ] 154. Preview 4D dans le panel : scrub de la timeline de reconstruction.
- [ ] 155. Export final `.fovea` multi-frames depuis le panel.
- [ ] 156. Test end-to-end : vidéo turntable 2 s → flipbook 24 frames lisible en VR.
- [ ] 157. Gestion des échecs partiels (frame N échoue → interpolation ou trou signalé).
- [ ] 158. Documentation du workflow 4D dans `tutorials/`.
- [ ] 159. Vidéo de démonstration du pipeline vidéo → splats animés.
- [ ] 160. Benchmark VR : flipbook 24 frames × 50k splats à 90 Hz sur desktop.

## Section 7 — Personnages riggés : pipeline complet (161-180) `[T-26,27,30]` 🟡

- [ ] 161. Import GLB riggé : détecter `Skeleton3D` + meshes skinnés dans la scène importée.
- [ ] 162. Splatter le mesh riggé en pose de repos via `textured_splat_generator.gd`.
- [ ] 163. Appeler `FoveaSplatSkinBinder.bind_splats()` automatiquement post-génération.
- [ ] 164. Transférer les poids de skinning du mesh source (au lieu de l'heuristique distance) quand disponibles.
- [ ] 165. Comparer binding heuristique vs poids transférés sur un personnage test (artefacts aux articulations).
- [ ] 166. Wizard "Convert Rigged Character to Splats" (menu contextuel sur le nœud importé).
- [ ] 167. Lecture des `AnimationPlayer`/`AnimationTree` standards : vérifier que le skinning suit toute animation Godot sans code dédié.
- [ ] 168. Gérer les blend shapes : ignorer proprement (warning) en v1, roadmap v2.
- [ ] 169. Binding heat-diffusion (amélioration de l'heuristique distance) pour les zones concaves.
- [ ] 170. LOD hybride : mesh riggé rendu en proche, splats riggés au-delà d'une distance exportée.
- [ ] 171. Transition fondu mesh↔splats sans pop (crossfade d'opacité sur 2 m).
- [ ] 172. Vêtements : binder les splats de tissu au cloth GPU (Section 3, items 75-80) au lieu des bones.
- [ ] 173. Test personnage complet : corps skinné + cape en cloth simultanés.
- [ ] 174. Compatibilité SplatBrush : sculpter les splats d'un personnage pendant qu'il s'anime (édition sur bind pose, replay du skinning).
- [ ] 175. Multi-personnages : N squelettes distincts dans le même buffer GPU (offset de bones par asset).
- [ ] 176. Benchmark : 10 personnages × 50k splats riggés à 90 Hz.
- [ ] 177. Ragdoll : blend `skin_weight` piloté par la physique (chute = LBS → simulation).
- [ ] 178. Scène de démo créature stylisée riggée + animation idle/walk.
- [ ] 179. GIF/vidéo de la créature pour le marketing (l'argument "personne ne fait ça").
- [ ] 180. Documentation du pipeline personnage dans `docs/ANIMATED_SPLATS.md` + tutoriel.

## Section 8 — Dette technique & typage (181-190) `[T-7,8]` 🟠

- [ ] 181. Typage strict : traiter `scripts/reconstruction/` (~lot de 200 variables).
- [ ] 182. Typage strict : traiter `scripts/editor/` et le panel StudioTo3D.
- [ ] 183. Typage strict : traiter `scripts/materials/` et `scripts/mocap/`.
- [ ] 184. Typage strict : traiter `scripts/vr/` et les scènes de test.
- [ ] 185. Typage strict : traiter le reste de `scripts/advanced/` non couvert.
- [ ] 186. Vérifier le typage complet des 12 nouveaux fichiers Phase 7 (règle CLAUDE.md).
- [ ] 187. Script CI de comptage des `var x = ` non typés avec seuil décroissant (gate anti-régression).
- [ ] 188. Nettoyer les `# TODO`/`# FIXME` accumulés depuis l'audit 100 (nouveau grep complet).
- [ ] 189. Supprimer les fichiers `.uid` orphelins et les scripts morts identifiés au passage.
- [ ] 190. Revalider les règles CLAUDE.md sur tout le code Phase 7 (pas de `_ready()` bloquant, pas de boucles `set_instance_*`, gardes null Vulkan).

## Section 9 — Tile rasterizer & indirect draw : affinage (191-205) `[BL-238,239,242,252-255]` 🔵

- [ ] 191. [BL-238] Tri local par tuile en shared memory GPU pour les splats intersectant chaque tuile 16×16.
- [ ] 192. [BL-239] Tampon chaîné des listes de splats par tuile (adresses mémoire).
- [ ] 193. Gestion du débordement de liste par tuile (cap + compteur de splats perdus).
- [ ] 194. [BL-242] Benchmark comparatif MultiMesh vs tile rasterizer (fillrate, ms/frame, 3 scènes types).
- [ ] 195. Décision documentée : quel chemin par défaut selon la densité de scène.
- [ ] 196. Compatibilité du tile rasterizer avec le buffer animé de la Section 2.
- [ ] 197. Compatibilité du tile rasterizer avec le layered splatting (poids par layer dans le tile pass).
- [ ] 198. [BL-252] Multi-draw indirect : rendre plusieurs assets distincts en un seul appel indirect.
- [ ] 199. [BL-253] Frustum culling d'instances déplacé du CPU vers le GPU.
- [ ] 200. [BL-254] Barrières mémoire : transitions de buffers propres entre écriture compute et draw.
- [ ] 201. [BL-255] Test de saccade : capturer 10 000 frames et vérifier l'absence de micro-gels périodiques.
- [ ] 202. Profil Vulkan validation layers : zéro erreur/warning sur la scène de démo.
- [ ] 203. Chemin de repli non-indirect pour le mode Compatibility.
- [ ] 204. Stats indirect draw dans le panneau `FoveaStats`.
- [ ] 205. Documentation de l'architecture GPU-driven mise à jour dans `docs/ARCHITECTURE.md`.

## Section 10 — Delta-Splat Variants (206-217) `[BL-243..248]` 🔵

- [ ] 206. [BL-243] Spécifier le format binaire delta (écarts position/couleur/normales, en-tête, index d'instance).
- [ ] 207. [BL-244] Compute shader appliquant les deltas aux instances visibles.
- [ ] 208. [BL-245] `FoveaDeltaManager` : stockage des overrides en tampons condensés.
- [ ] 209. [BL-246] Coefficient d'application animable 0→1 (transitions douces) — brancher sur `FoveaAnimationSubsystem`.
- [ ] 210. [BL-247] Compression FP16 des deltas.
- [ ] 211. [BL-248] Outil de peinture delta dans l'inspecteur (tint/déformation locale par instance).
- [ ] 212. Sérialisation des deltas dans le `.fovea` (section variantes).
- [ ] 213. API GDScript : `set_instance_delta(instance_id, delta_resource)`.
- [ ] 214. Test : forêt de 1000 instances du même arbre avec 5 variantes de teinte, une seule copie VRAM du base.
- [ ] 215. Interaction deltas × animation : un delta de déformation se compose avec le flow field sans conflit.
- [ ] 216. Benchmark : surcoût du pass delta ≤ 0,1 ms à 1000 instances.
- [ ] 217. Documentation des Delta Variants.

## Section 11 — Out-of-Core VRAM Streaming (218-235) `[BL-256..262]` 🔵

- [ ] 218. [BL-256] Format de chunk Morton : écrire les gros `.fovea` en chunks triés Morton 3D avec table d'index.
- [ ] 219. Lecteur de table d'index des chunks (offsets fichier, AABB par chunk).
- [ ] 220. [BL-257] E/S asynchrone en Rust : lecture fichier → buffer staging → upload GPU sans passer par GDScript.
- [ ] 221. File de requêtes de chargement thread-safe côté Rust.
- [ ] 222. [BL-258] Allocateur de segments VRAM : pool de slots de chunks avec free-list.
- [ ] 223. Éviction LRU des chunks hors frustum depuis > N secondes.
- [ ] 224. [BL-259] Priorisation distance + cône de regard (réutiliser `fovea_gaze_*`) dans la file de chargement.
- [ ] 225. [BL-260] Fade-in d'opacité des chunks fraîchement chargés (0→1 sur 0,3 s).
- [ ] 226. [BL-261] LOD global basse résolution résident en permanence (macro-splats du HLOD existant).
- [ ] 227. Substitution automatique LOD global ↔ chunk plein selon l'état de chargement.
- [ ] 228. [BL-262] Régulateur de bande passante : budget Mo/frame configurable pour les uploads.
- [ ] 229. Étendre `fovea_streaming_manager.gd` pour orchestrer le tout (état par chunk : resident/loading/evicted).
- [ ] 230. Outil de génération : convertir un `.fovea` monolithique en `.fovea` chunké (CLI Rust).
- [ ] 231. Scène de test "grande scène" (> 10M splats) générée procéduralement pour valider.
- [ ] 232. Test : traversée de la grande scène sans dépasser un budget VRAM fixé (mesure `FoveaStats`).
- [ ] 233. Test : aucun hitch > 4 ms pendant le streaming (frame time capturé).
- [ ] 234. Interaction streaming × animation : les chunks streamés rejoignent le buffer animé sans re-création du pipeline.
- [ ] 235. Documentation du streaming out-of-core (`docs/vram_streaming_compression_concept.md` à mettre à jour).

## Section 12 — Static vs Dynamic Splats (236-247) `[BL-263..269]` 🔵

- [ ] 236. [BL-263] Propriété `motion_class` (STATIC/DYNAMIC) sur `FoveaSplattable` et dans le format packé.
- [ ] 237. [BL-264] Baking d'octree statique immuable en VRAM pour le décor.
- [ ] 238. [BL-266] Re-tri des statiques seulement sur mouvement caméra majeur (seuil d'angle/distance).
- [ ] 239. Re-tri des dynamiques chaque frame (petit buffer, coût borné).
- [ ] 240. [BL-267] Buffers GPU séparés : statique lecture-seule + dynamique réécrit chaque frame.
- [ ] 241. Fusion des deux buffers au moment du rendu (draw en deux passes ou index combiné).
- [ ] 242. Classification automatique : les splats ciblés par un animateur Phase 7 passent DYNAMIC automatiquement.
- [ ] 243. [BL-268] Verlet/forces physiques connectés aux entités dynamiques uniquement.
- [ ] 244. [BL-269] Profil de performance : proportion max de splats dynamiques exposée et enforced.
- [ ] 245. [BL-265] Mutualiser le compute skinning avec la Section 3 (items 66-74) — vérifier qu'aucun doublon de shader n'existe.
- [ ] 246. Benchmark : scène 80 % statique / 20 % dynamique — gain de tri mesuré vs tout-dynamique.
- [ ] 247. Documentation de la séparation static/dynamic.

## Section 13 — Compression Gaussienne `.foveaz` (248-261) `[BL-276..282]` 🔵

- [ ] 248. [BL-276] Affiner K-Means++ (init améliorée, itérations adaptatives) pour palettes et codebook covariance.
- [ ] 249. [BL-277] Encodage de position différentiel par octree (stocker l'écart au parent).
- [ ] 250. [BL-278] Quantification logarithmique des opacités sur 4 bits.
- [ ] 251. [BL-279] Écriture `.foveaz` : conteneur ZStandard par-dessus le `.fovea` chunké.
- [ ] 252. Lecture `.foveaz` avec décompression streaming (chunk par chunk).
- [ ] 253. [BL-280] Décompression GPU native du payload en compute shader (au moins la dé-quantification).
- [ ] 254. Intégration fast-path Rust : décompression zstd côté Rust avant upload.
- [ ] 255. [BL-282] Harnais de mesure PSNR automatisé (rendu référence PLY vs rendu `.foveaz`).
- [ ] 256. Gate qualité : PSNR > 30 dB requis, sinon warning à l'export.
- [ ] 257. Benchmarks de taille : ratio de compression sur 5 assets réels documenté.
- [ ] 258. [BL-281] Prototype streaming réseau de trames compressées (localhost, mesure débit requis).
- [ ] 259. Étude faisabilité casque léger (Quest standalone) consommant le flux.
- [ ] 260. Option d'export `.foveaz` dans le panel StudioTo3D et le menu contextuel `FoveaSplattable`.
- [ ] 261. Documentation du format `.foveaz` (spec binaire complète).

## Section 14 — Auto-ROI par IA (262-271) `[BL-270..275]` 🔵

- [ ] 262. [BL-270] Intégrer un modèle de segmentation ONNX local (MobileSAM) via le runtime déjà packagé.
- [ ] 263. [BL-271] Détection automatique de l'objet central sur la première frame.
- [ ] 264. [BL-272] Génération de masques binaires pour toutes les frames sans intervention.
- [ ] 265. Propagation temporelle du masque (tracking inter-frames au lieu d'une segmentation par frame).
- [ ] 266. [BL-274] Mode multi-sujets : clic sur la préview = point d'intérêt guidant la segmentation.
- [ ] 267. [BL-275] Netteté assistée : cibler les zones haute variance pour affiner la ROI.
- [ ] 268. Bouton "Auto-ROI" dans le panel StudioTo3D (remplace le dessin manuel en un clic).
- [ ] 269. Comparaison qualité reconstruction avec/sans Auto-ROI sur 3 vidéos test.
- [ ] 270. Repli propre si ONNX indisponible (message + ROI manuelle).
- [ ] 271. Documentation Auto-ROI dans les tutoriels.

## Section 15 — Pont Hermes/Blender (272-283) `[BL-283..288]` 🔵

- [ ] 272. [BL-283] Serveur WebSocket léger en Godot (port configurable, auth par token).
- [ ] 273. [BL-284] Protocole JSON versionné : requêtes generate/edit/query d'assets.
- [ ] 274. Validation stricte des messages entrants (schéma + limites de taille).
- [ ] 275. [BL-285] Addon Blender Python : connexion au serveur, synchro caméra Godot↔Blender.
- [ ] 276. Synchro de scène : export léger de la hiérarchie Godot vers Blender.
- [ ] 277. [BL-286] Flux complet : capture caméra Godot → job Blender → `.fovea` renvoyé et chargé à chaud.
- [ ] 278. File de jobs avec statut (queued/running/done/failed) exposée au protocole.
- [ ] 279. [BL-287] Test d'orchestration : un agent place et stylise 5 objets dans une scène via le protocole seul.
- [ ] 280. Sandbox de sécurité : liste blanche des opérations permises à l'agent.
- [ ] 281. [BL-288] Manuel technique de déploiement et sécurisation de la passerelle.
- [ ] 282. Exemple de client Python minimal (20 lignes) dans `tools/`.
- [ ] 283. Démo vidéo agent → scène générée.

## Section 16 — Vraies poses caméra DVLT (284-291) `[BL-289..294]` 🔵

- [ ] 284. [BL-289] Exportateur d'extrinsèques/intrinsèques au format COLMAP (`images.txt`, `cameras.txt`).
- [ ] 285. [BL-290] Génération du `cameras.json` compatible pipelines 3DGS.
- [ ] 286. Brancher l'export sur la sortie du bridge DVLT (`diffsynth_bridge.py`).
- [ ] 287. [BL-292] Visualiseur de pyramides de caméras dans le viewport Godot (gizmos par pose).
- [ ] 288. [BL-293] Alignement up-vector automatique du repère reconstruit avec le sol de la scène.
- [ ] 289. [BL-294] Rapport d'erreur de pose (erreur moyenne de reprojection, affiché dans le panel).
- [ ] 290. Test : poses DVLT → entraînement 3DGS externe réussi sans édition manuelle.
- [ ] 291. Documentation du flux de poses dans `docs/star_integration.md`.

## Section 17 — Mobile, Quest & WebGPU (292-309) `[BL-226..230]` 🔵

- [ ] 292. [BL-226] Audit des compute shaders : usages de registres/bande passante incompatibles ARM listés.
- [ ] 293. Variantes de shaders "mobile" (workgroups réduits, FP16 partout où possible).
- [ ] 294. Chemin sans `usampler2D`/features non portées pour les GPU mobiles.
- [ ] 295. [BL-227] Préréglage "Quest 3" : caps de splats, tri interleavé ×4, foveation agressive.
- [ ] 296. Build Android/OpenXR du projet de démo et premier lancement sur Quest 3.
- [ ] 297. Profiling Quest 3 : identifier le goulot (tri, fillrate, bande passante) sur la scène de démo.
- [ ] 298. Itération jusqu'à 90 Hz stables sur une scène de 200k splats sur Quest 3.
- [ ] 299. [BL-230] Désactivation du tri sur objets statiques stables (mutualiser avec Section 12, item 238).
- [ ] 300. Gestion thermique : downgrade automatique du preset quand le SoC throttle.
- [ ] 301. [BL-228] Chaîne de compilation Rust → WASM du fast-path loader.
- [ ] 302. Repli GDScript pur quand le WASM n'est pas disponible.
- [ ] 303. [BL-229] Porter `sort_bitonic_keyed.glsl` en WGSL.
- [ ] 304. Porter `gpu_culling_compute.glsl` en WGSL.
- [ ] 305. Porter les shaders de rendu splat en WGSL.
- [ ] 306. Build export Web du projet de démo et test dans 2 navigateurs.
- [ ] 307. Benchmark Web : combien de splats à 60 fps dans Chrome (documenter).
- [ ] 308. Page web de démo publique (hébergement GitHub Pages).
- [ ] 309. Documentation des cibles supportées et de leurs limites.

## Section 18 — Tests, CI & qualité (310-334) 🟠

- [ ] 310. Enregistrer les 8 tests Phase 7 dans `run_all_tests.gd`.
- [ ] 311. Job CI dédié "animation" exécutant les tests Phase 7 en headless.
- [ ] 312. Vérifier le 1er run complet du CI réécrit (D4) : nom de l'asset Godot 4.7-dev5 et SDK NuGet corrects.
- [ ] 313. Test de compilation de tous les shaders en CI (chargement headless de chaque `.gdshader`/`.glsl`).
- [ ] 314. Tests de non-régression visuelle : capture de 5 scènes de référence et diff d'images en CI (seuil de tolérance).
- [ ] 315. Test de fuite mémoire : charger/décharger 100× un asset et vérifier la stabilité RAM/VRAM.
- [ ] 316. Test de stress animation : 10 animateurs simultanés pendant 10 000 frames sans NaN ni dérive.
- [ ] 317. Test du format `.fovea` : round-trip complet avec toutes les sections optionnelles nouvelles (flipbook, morph, flux, deltas).
- [ ] 318. Tests du fast-path Rust : corpus de fichiers malformés (fuzzing léger) sans crash.
- [ ] 319. Test multi-résolution : rendu correct en 720p/1440p/4K (pas de dépendance viewport cachée).
- [ ] 320. Test mode Compatibility : le projet démarre et rend (dégradé) sans Vulkan.
- [ ] 321. Test headless : tous les subsystems se désactivent proprement sans DisplayServer.
- [ ] 322. Couverture des utilitaires critiques : `FoveaMultiMeshBulk`, `SpatialHashGrid`, `color_quantization`.
- [ ] 323. Test de sérialisation `GaussianSplat.to_dict()/from_dict()` exhaustif (tous les champs, dont Phase 7).
- [ ] 324. Linting GDScript automatisé en CI (gdlint ou équivalent) avec baseline.
- [ ] 325. Test des chemins d'erreur du panel StudioTo3D (FFmpeg absent, COLMAP absent, vidéo corrompue).
- [ ] 326. Test de charge du SplatBrush : 1000 strokes undo/redo sans corruption.
- [ ] 327. Test du clay deformer : déformation + reset = positions bit-exactes (non-destructivité).
- [ ] 328. Matrice de tests VR simulée : mocker `XRInterface` pour tester le chemin stéréo en CI.
- [ ] 329. Badge de statut CI dans le README.
- [ ] 330. Politique de branche : CI vert requis avant merge sur `main` (branch protection).
- [ ] 331. Nightly benchmark job : suivre les ms/frame des scènes de référence dans le temps (détection de régression perf).
- [ ] 332. Alerte automatique si une régression perf > 10 % est détectée en nightly.
- [ ] 333. Documenter la stratégie de test dans `CONTRIBUTING.md`.
- [ ] 334. Runbook de débogage GPU (RenderDoc + validation layers) dans `docs/developer_reference.md`.

## Section 19 — Benchmarks & performance (335-350) 🟠

- [ ] 335. Étalonner la suite de benchmark existante sur le matériel de référence (GPU desktop) et figer les chiffres de base.
- [ ] 336. Benchmark animation CPU : coût par animateur par 100k splats (tableau comparatif).
- [ ] 337. Benchmark animation GPU (après Section 2/3) : même tableau, gain documenté.
- [ ] 338. Profiler le hot path `_generate_and_filter()` : mesurer le coût de la reconstruction par frame des splats transitoires.
- [ ] 339. Étudier la mise en cache des splats transformés quand ni le node ni la caméra n'ont bougé (skip de la reconstruction).
- [ ] 340. Optimiser `FoveaAnimationSubsystem.apply()` : éviter l'appel `Callable` par splat (boucle inversée : modifier itère les splats).
- [ ] 341. Mesurer et documenter l'overdraw moyen par scène type (compteur fragment).
- [ ] 342. Optimiser le pire cas du tri bitonique sous animation (Section 2, item 37) après mesures réelles.
- [ ] 343. Budget mémoire documenté : octets/splat pour chaque combinaison de features (base, flipbook, riggé, delta).
- [ ] 344. Réduire l'empreinte des champs Phase 7 dans `GaussianSplat` (bone data en pools partagés plutôt que par instance si mesuré coûteux).
- [ ] 345. Frame pacing VR : mesurer la variance de frame time avec animation active, cible < 1 ms d'écart-type.
- [ ] 346. Étude single-pass stereo : vérifier que les passes compute ne tournent qu'une fois par frame (pas par œil).
- [ ] 347. Mesurer le coût de `_process()` des animateurs inactifs et le rendre nul (pas de `_process` si non enregistré).
- [ ] 348. Audit des allocations par frame (Object::new dans les hot paths) et élimination.
- [ ] 349. Rapport de performance consolidé dans `docs/benchmark.md` (avant/après Phase 7 GPU).
- [ ] 350. Définir les budgets officiels par plateforme (desktop VR, Quest, Web) dans la doc.

## Section 20 — Démos & contenu (351-370) ⚪

- [ ] 351. Scène démo "Forêt vivante" : feuillage en flow WIND + LEAVES layer.
- [ ] 352. Scène démo "Rideau au vent" : tissu en flow + cloth.
- [ ] 353. Scène démo "Blob organique" : morph covariance BREATHE.
- [ ] 354. Scène démo "Surface d'eau" : WOBBLE + water splats existants combinés.
- [ ] 355. Scène démo "Flamme volumétrique" : flipbook LAYER_ANIM.
- [ ] 356. Scène démo "Sort magique VR" : flipbook + emission.
- [ ] 357. Scène démo "Créature riggée" (dépend Section 7).
- [ ] 358. Scène démo "Scène scannée vivante" : reconstruction StudioTo3D + neural offset breathing.
- [ ] 359. Hub de démos : scène menu chargeant chacune des démos ci-dessus.
- [ ] 360. Intégrer le hub dans `demo_desktop.tscn` (sélecteur existant).
- [ ] 361. Asset pack de test libre de droits (3-5 `.fovea` variés) versionné en Git LFS ou release.
- [ ] 362. GIF de chaque démo (8 GIFs) pour README/boutique/réseaux.
- [ ] 363. Vidéo compilation 60 s "Animated Splats in Godot" pour YouTube.
- [ ] 364. Captures d'écran haute résolution pour la fiche Asset Library.
- [ ] 365. Tutoriel écrit "Votre première scène animée en 10 minutes".
- [ ] 366. Tutoriel écrit "Rigger un personnage en splats".
- [ ] 367. Projet template téléchargeable pré-configuré (plugin + démo minimale).
- [ ] 368. Vérifier chaque démo sur Quest 3 après la Section 17.
- [ ] 369. Page vitrine dans le README avec les 8 GIFs en tableau.
- [ ] 370. Soumettre une démo au showcase Godot officiel.

## Section 21 — Publication Godot Asset Library (371-385) `[T-86..95]` 🟣

- [ ] 371. Rédiger la description courte officielle de la fiche boutique.
- [ ] 372. Rédiger le README condensé (~10 lignes) dédié à la boutique.
- [ ] 373. Produire le logo carré 512×512 PNG depuis `icon.svg`.
- [ ] 374. Screenshot du rendu splatting (après démos Section 20).
- [ ] 375. Screenshot du panel StudioTo3D.
- [ ] 376. GIF du SplatBrush VR.
- [ ] 377. Fixer la version de publication (post-vérification P0, probablement `0.3.0-alpha` avec la Phase 7).
- [ ] 378. Vérifier la conformité du dossier `addons/foveacore/` seul (installable sans le reste du repo).
- [ ] 379. Tester l'installation propre dans un projet Godot vierge (checklist d'install).
- [ ] 380. Catégories (Rendering/Tools/VR/Import), licence MIT, compat Godot 4.6+ dans la fiche.
- [ ] 381. Tag "Early Access / Experimental" visible.
- [ ] 382. Soumettre à la Godot Asset Library.
- [ ] 383. Répondre aux retours de modération jusqu'à acceptation.
- [ ] 384. Texte d'annonce r/godot + Discord Godot + r/GaussianSplatting.
- [ ] 385. Publier l'annonce le jour de l'acceptation (coordonner avec les GIFs).

## Section 22 — Documentation & rayonnement (386-400) ⚪

- [ ] 386. Créer `docs/ANIMATED_SPLATS.md` : doc officielle complète de la Phase 7 (référencée par de nombreuses tâches ci-dessus).
- [ ] 387. Section "Animated Splats" dans le README principal avec liens vers les démos.
- [ ] 388. Mettre à jour `docs/ARCHITECTURE.md` avec le sous-système animation et le pass GPU.
- [ ] 389. Mettre à jour `docs/developer_reference.md` : layout `data3` final (opacité, layer, anim_flags, flipbook).
- [ ] 390. Documenter l'API publique de `FoveaAnimationSubsystem` (docstrings complets + exemple).
- [ ] 391. Rédiger l'article technique "Morph Covariance Animation: Animating the Gaussians Themselves" (après le portage GPU, item 46-55).
- [ ] 392. Publier l'article (blog/GitHub Pages) et le relayer (Reddit, HN, X).
- [ ] 393. Article court "Vector-field splat animation painted in VR" (après items 91-95).
- [ ] 394. Consolider les documents de suivi : archiver `AUDIT_COMPLET_2026-05-02.md`, `AUDIT_TODO_2026-06-11.md` et `AUDIT_AND_TASKS.md` dans `docs/audits/` (tâches faites), pointer tout vers `TOP_TASKS.md` + ce fichier.
- [ ] 395. Mettre à jour `ROADMAP.md` (77 lignes, haut niveau) avec la Phase 7 et les jalons 0.3/0.4/0.5.
- [ ] 396. Traduire les sections clés du README en `README_CN.md` (déjà existant, à synchroniser).
- [ ] 397. FAQ utilisateur (matériel requis, limites connues, compatibilité).
- [ ] 398. Guide de migration pour les utilisateurs de `.fovea` v1 vers le format étendu (flipbook/morph/deltas).
- [ ] 399. Vidéo développeur "architecture tour" de 10 min pour attirer des contributeurs.
- [ ] 400. Rétrospective écrite post-0.3.0 : ce qui a marché, les budgets tenus/ratés, priorités révisées pour 0.4.0.

---

## Récapitulatif

| Section | Tâches | Thème | Priorité |
|---|---|---|---|
| 1 | 1-15 | Vérification post-Phase 7 | 🔴 |
| 2 | 16-45 | Infrastructure GPU `splat_animate.glsl` | 🟡 |
| 3 | 46-90 | Portage GPU des animateurs | 🟡 |
| 4 | 91-125 | Outils auteur Phase 7 | 🟡 |
| 5 | 126-145 | Pipeline neural offline | 🟡 |
| 6 | 146-160 | Flipbook 4D & StudioTo3D | 🟡 |
| 7 | 161-180 | Personnages riggés | 🟡 |
| 8 | 181-190 | Dette technique & typage | 🟠 |
| 9 | 191-205 | Tile rasterizer & indirect draw | 🔵 |
| 10 | 206-217 | Delta-Splat Variants | 🔵 |
| 11 | 218-235 | Streaming out-of-core | 🔵 |
| 12 | 236-247 | Static vs Dynamic | 🔵 |
| 13 | 248-261 | Compression `.foveaz` | 🔵 |
| 14 | 262-271 | Auto-ROI IA | 🔵 |
| 15 | 272-283 | Pont Hermes/Blender | 🔵 |
| 16 | 284-291 | Poses caméra DVLT | 🔵 |
| 17 | 292-309 | Mobile, Quest & WebGPU | 🔵 |
| 18 | 310-334 | Tests, CI & qualité | 🟠 |
| 19 | 335-350 | Benchmarks & performance | 🟠 |
| 20 | 351-370 | Démos & contenu | ⚪ |
| 21 | 371-385 | Publication Asset Library | 🟣 |
| 22 | 386-400 | Documentation & rayonnement | ⚪ |

**400 tâches.** Jalons suggérés : Sections 1-4 → release **0.3.0 "Living Splats"** ·
Sections 5-7 → **0.4.0** (Morph GPU + personnages) · Sections 9-17 → **0.5.0**
(échelle : streaming, compression, mobile) · Sections 20-22 en continu.
