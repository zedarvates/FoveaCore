class_name FoveaSplatSubsystem
extends Node

## FoveaSplatSubsystem — Pipeline de génération, tri, filtrage et rendu des Gaussian Splats.
## Extrait de FoveaCoreManager pour respecter le principe de responsabilité unique.
## Responsabilités :
##   - Génération de splats depuis les surfaces visibles
##   - Reprojection temporelle
##   - Tri back-to-front (GPU ou CPU)
##   - Injection dans le SplatRenderer

## Splats du frame courant (post-tri, pré-rendu)
var current_splats: Array[GaussianSplat] = []

## Config du générateur
var splat_config: SplatGenerator.SplatConfig = null

## Densité globale (multiplie la config locale de chaque FoveaSplattable)
var global_splat_density: float = 1.0

## Références aux sous-systèmes partenaires (injectées par le manager)
var temporal_reprojector: TemporalReprojector = null
var occlusion_culler: OcclusionCuller = null
var splat_sorter: SplatSorter = null
var splat_renderer: FoveaSplatRenderer = null

## Position caméra du frame précédent (pour reprojection temporelle)
var _previous_camera_position: Vector3 = Vector3.ZERO

func setup(density: float) -> void:
	global_splat_density = density

	splat_config = SplatGenerator.SplatConfig.new()
	splat_config.splats_per_triangle = 3
	splat_config.min_radius = 0.02
	splat_config.max_radius = 0.3
	splat_config.depth_aware_blending = true

## Traiter les résultats de visibilité pour un frame
## Retourne le nombre de splats rendus
func process_frame(visibility_result, camera: Camera3D, camera_pos: Vector3) -> int:
	_generate_and_filter(visibility_result, camera, camera_pos)
	_previous_camera_position = camera_pos
	return _submit_to_renderer()

## Génération + reprojection temporelle + occlusion
func _generate_and_filter(visibility_result, camera: Camera3D, camera_pos: Vector3) -> void:
	if temporal_reprojector:
		current_splats = []
		for node in visibility_result.per_node_results:
			var extraction = visibility_result.per_node_results[node]
			var filtered_triangles = _filter_occlusion(extraction.visible_triangles, camera)
			var reprojected: Array[GaussianSplat] = temporal_reprojector.reproject_splats(
				node, [], camera_pos, _previous_camera_position, filtered_triangles)
			current_splats.append_array(reprojected)
	else:
		current_splats = SplatGenerator.generate_all_splats(
			visibility_result, camera_pos, splat_config, global_splat_density)

	current_splats = _sort_gpu_aware(current_splats, camera, camera_pos)

## Filtre les triangles occultés via le Hi-Z culler CPU
func _filter_occlusion(triangles: Array, camera: Camera3D) -> Array:
	if occlusion_culler == null or camera == null:
		return triangles
	var view_proj := camera.get_camera_projection() * Projection(camera.global_transform.affine_inverse())
	var filtered: Array = []
	for tri in triangles:
		if not occlusion_culler.is_occluded(tri.center, view_proj, camera.global_transform):
			filtered.append(tri)
	return filtered

## Tri back-to-front : GPU si disponible, sinon CPU par profondeur
func _sort_gpu_aware(splats: Array[GaussianSplat], camera: Camera3D, camera_pos: Vector3) -> Array[GaussianSplat]:
	if splat_sorter and splat_sorter.is_gpu_available() and splats.size() <= splat_sorter.get_max_supported_splats():
		var indices := splat_sorter.sort_splats_back_to_front(splats, camera)
		if indices and not indices.is_empty():
			var sorted: Array[GaussianSplat] = []
			for idx in indices:
				if idx < splats.size():
					sorted.append(splats[idx])
			return sorted
	return SplatSorter.sort_by_depth(splats, camera_pos)

## Soumettre les splats triés au renderer
func _submit_to_renderer() -> int:
	if splat_renderer == null:
		return 0
	return splat_renderer.render_splats(current_splats)

## Appliquer les poids foveated et filtrer par opacité
func apply_foveated_pass(foveated_controller: FoveatedController) -> void:
	if foveated_controller == null:
		return
	var foveated_splats: Array[GaussianSplat] = []
	for splat in current_splats:
		var weight := foveated_controller.get_foveal_weight(splat.position)
		var density := foveated_controller.get_density_multiplier(splat.position)
		splat.apply_foveal_weight(weight * density / 2.0)
		if splat.opacity > 0.05:
			foveated_splats.append(splat)
	current_splats = foveated_splats
	current_splats = SplatSorter.minimize_overdraw(current_splats)
