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
var splat_renderer: Node = null
var animation_subsystem: FoveaAnimationSubsystem = null

## Position caméra du frame précédent (pour reprojection temporelle)
var _previous_camera_position: Vector3 = Vector3.ZERO

var max_splats: int = 100000

func setup(density: float, max_s: int = 100000) -> void:
	global_splat_density = density
	max_splats = max_s

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
	current_splats = []
	current_splats.resize(max_splats)
	var current_idx := 0

	if temporal_reprojector:
		for node in visibility_result.per_node_results:
			if node is FoveaSplattable and node.has_ply_splats and not node.loaded_splats.is_empty():
				var gtr: Transform3D = node.global_transform
				var gtr_rot: Quaternion = gtr.basis.get_rotation_quaternion()
				var gtr_scale: Vector3 = gtr.basis.get_scale()
				for local_splat in node.loaded_splats:
					if current_idx < max_splats:
						var splat: GaussianSplat = GaussianSplat.new()
						splat.position = gtr * (local_splat.position + local_splat.origin_offset)
						splat.rotation = (gtr_rot * local_splat.rotation).normalized()
						splat.scale = gtr_scale * local_splat.scale
						splat.opacity = local_splat.opacity * node.alpha_override
						splat.color = local_splat.color * node.color_override
						splat.palette_index = local_splat.palette_index
						splat.normal = (gtr.basis * local_splat.normal).normalized()
						splat.surface_normal = (gtr.basis * local_splat.surface_normal).normalized()
						splat.origin_offset = gtr.basis * local_splat.origin_offset
						splat.velocity = gtr.basis * local_splat.velocity
						splat.stiffness = local_splat.stiffness
						splat.depth = splat.position.distance_to(camera_pos)
						splat.radius = local_splat.radius * node.scale_override
						splat.covariance = local_splat.covariance
						splat.layer_type = local_splat.layer_type
						splat.brush_type = local_splat.brush_type
						splat.dither_seed = local_splat.dither_seed
						splat.flipbook_frame = local_splat.flipbook_frame
						splat.flipbook_frame_count = local_splat.flipbook_frame_count
						splat.bone_indices = local_splat.bone_indices
						splat.bone_weights = local_splat.bone_weights
						splat.bind_pose_position = gtr * local_splat.bind_pose_position
						current_splats[current_idx] = splat
						current_idx += 1
					else:
						break
			else:
				var extraction: SurfaceExtractor.ExtractionResult = visibility_result.per_node_results[node]
				var filtered_triangles: Array = _filter_occlusion(extraction.visible_triangles, camera)
				var reprojected: Array[GaussianSplat] = temporal_reprojector.reproject_splats(
					node, [], camera_pos, _previous_camera_position, filtered_triangles)
				for splat in reprojected:
					if current_idx < max_splats:
						current_splats[current_idx] = splat
						current_idx += 1
					else:
						break
	else:
		var use_hierarchical: bool = splat_renderer != null and splat_renderer.get("enable_hlod") == true
		var splats: Array[GaussianSplat] = []
		if use_hierarchical:
			for node in visibility_result.per_node_results:
				if not (node is FoveaSplattable and node.has_ply_splats and not node.loaded_splats.is_empty()):
					if node is FoveaSplattable and node._mesh_instance_ref and node._mesh_instance_ref.mesh:
						var node_splats := HierarchicalSplatGenerator.generate_hierarchical_splats(node._mesh_instance_ref.mesh)
						var gtr: Transform3D = node.global_transform
						var gtr_rot: Quaternion = gtr.basis.get_rotation_quaternion()
						var gtr_scale: Vector3 = gtr.basis.get_scale()
						for s: GaussianSplat in node_splats:
							s.position = gtr * s.position
							s.rotation = (gtr_rot * s.rotation).normalized()
							s.scale = gtr_scale * s.scale
							s.normal = (gtr.basis * s.normal).normalized()
							s.surface_normal = (gtr.basis * s.surface_normal).normalized()
							s.depth = s.position.distance_to(camera_pos)
							splats.append(s)
		
		if splats.is_empty():
			splats = SplatGenerator.generate_all_splats(
				visibility_result, camera_pos, splat_config, global_splat_density)
		for splat in splats:
			if current_idx < max_splats:
				current_splats[current_idx] = splat
				current_idx += 1
			else:
				break

	current_splats.resize(current_idx)
	if animation_subsystem:
		animation_subsystem.apply(current_splats)
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
func apply_foveated_pass(foveated_controller: FoveatedController, layered_controller: LayeredFoveatedController = null, enable_layered: bool = false) -> void:
	if foveated_controller == null:
		return
		
	if enable_layered and layered_controller != null:
		var camera := get_viewport().get_camera_3d()
		var cam_pos := camera.global_position if camera else Vector3.ZERO
		var gaze_pt := foveated_controller.get_gaze_point()
		current_splats = layered_controller.optimize_layered_splats(current_splats, gaze_pt, cam_pos)
		current_splats = SplatSorter.minimize_overdraw(current_splats)
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
