class_name FoveaMobilePresets
extends RefCounted

## FoveaMobilePresets : Fournit des préréglages graphiques et des optimisations pour Meta Quest 3 et mobile VR.
## Permet d'assurer un framerate stable à 90 Hz sur puces ARM/Adreno.

static func apply_quest3_presets(manager: Node) -> void:
	if not manager:
		push_warning("FoveaMobilePresets: Manager non valide fourni.")
		return
		
	print("FoveaMobilePresets: Application des préréglages Quest 3 / Mobile VR...")
	
	# 1. Optimisations des performances du pipeline Splatting
	if "global_splat_density" in manager:
		manager.global_splat_density = 0.6  # Réduire la densité de splats de base
	
	if "max_splats_per_frame" in manager:
		manager.max_splats_per_frame = 60000  # Limite raisonnable pour le fillrate mobile
		
	if "max_dynamic_splats" in manager:
		manager.max_dynamic_splats = 25000  # Limiter les splats animés à 25k max
		
	if "max_dynamic_splats_ratio" in manager:
		manager.max_dynamic_splats_ratio = 0.4
		
	# 2. Fréquence d'interlaçage du tri bitonique optimisée pour 90 Hz
	var renderer = manager.get_node_or_null("FoveaCoreSplatRenderer")
	if renderer:
		if "sort_interleave_factor" in renderer:
			renderer.sort_interleave_factor = 4  # Quarter: trier un quart des splats par frame
		if "enable_motion_lod" in renderer:
			renderer.enable_motion_lod = true  # Activer la dégradation de LOD en mouvement
		if "enable_motion_stretch" in renderer:
			renderer.enable_motion_stretch = false  # Désactiver le motion stretch coûteux en fillrate
		if "sort_distance_threshold" in renderer:
			renderer.sort_distance_threshold = 0.25  # Moins sensible aux micromouvements
		if "chunk_load_radius" in renderer:
			renderer.chunk_load_radius = 12.0  # Limiter le chargement de chunks distants

	# 3. Optimisation Foveated Rendering
	if "foveated_enabled" in manager:
		manager.foveated_enabled = true
	if "foveal_density_multiplier" in manager:
		manager.foveal_density_multiplier = 1.5
	if "peripheral_density_multiplier" in manager:
		manager.peripheral_density_multiplier = 0.25  # Périphérie très basse densité

	print("FoveaMobilePresets: Préréglages Meta Quest 3 appliqués avec succès.")

## Applique automatiquement les optimisations si la plateforme courante est mobile ou VR autonome.
static func auto_apply_if_mobile_vr(manager: Node) -> void:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("web") or OS.has_feature("xr"):
		apply_quest3_presets(manager)
