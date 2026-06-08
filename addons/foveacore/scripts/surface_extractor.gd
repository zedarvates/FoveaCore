class_name SurfaceExtractor

## SurfaceExtractor - Extrait les surfaces visibles d'un mesh
## Combine backface culling + occlusion approximative pour identifier les triangles visibles

## Résultat d'un triangle visible
class VisibleTriangle:
	var indices: Array[int] = []        # Indices des 3 sommets
	var vertices: Array[Vector3] = []   # Positions mondiales
	var normals: Array[Vector3] = []    # Normales mondiales
	var center: Vector3 = Vector3.ZERO  # Centre du triangle
	var area: float = 0.0               # Surface du triangle
	var distance_to_camera: float = 0.0 # Distance à la caméra

## Résultat de l'extraction pour un nœud
class ExtractionResult:
	var visible_triangles: Array[VisibleTriangle] = []
	var total_triangles: int = 0
	var visible_count: int = 0
	var culled_backface: int = 0
	var culled_occlusion: int = 0
	var extraction_time_ms: float = 0.0

## Backface culling : vérifier si un triangle fait face à la caméra
static func is_front_facing(triangle_vertices: Array[Vector3], camera_position: Vector3) -> bool:
	if triangle_vertices.size() < 3:
		return false

	var v0: Vector3 = triangle_vertices[0]
	var v1: Vector3 = triangle_vertices[1]
	var v2: Vector3 = triangle_vertices[2]

	# Calculer la normale du triangle
	var edge1: Vector3 = v1 - v0
	var edge2: Vector3 = v2 - v0
	var face_normal: Vector3 = edge1.cross(edge2).normalized()

	# Vecteur du sommet à la caméra
	var to_camera: Vector3 = (camera_position - v0).normalized()

	# Si le produit scalaire > 0, le triangle fait face à la caméra
	return face_normal.dot(to_camera) > 0.0

## Calculer l'aire d'un triangle
static func triangle_area(vertices: Array[Vector3]) -> float:
	if vertices.size() < 3:
		return 0.0
	var edge1: Vector3 = vertices[1] - vertices[0]
	var edge2: Vector3 = vertices[2] - vertices[0]
	return edge1.cross(edge2).length() / 2.0

## Extraire les triangles visibles d'un mesh
static func extract_visible_triangles(
	splattable: FoveaSplattable,
	camera_position: Vector3,
	camera_transform: Transform3D
) -> ExtractionResult:
	var start_time: int = Time.get_ticks_usec()
	var result: ExtractionResult = ExtractionResult.new()

	if splattable.original_mesh == null:
		return result

	var mesh: Mesh = splattable.original_mesh
	var world_transform: Transform3D = splattable.global_transform

	var use_native = ClassDB.can_instantiate("FoveaAssetLoader")
	var loader = null
	if use_native:
		loader = ClassDB.instantiate("FoveaAssetLoader")

	# Parcourir les surfaces du mesh
	for surface_idx: int in range(mesh.get_surface_count()):
		var mesh_data: Array = mesh.surface_get_arrays(surface_idx)
		if mesh_data.size() < Mesh.ARRAY_NORMAL:
			continue

		var vertices: PackedVector3Array = mesh_data[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals: PackedVector3Array = mesh_data[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var indices: PackedInt32Array = mesh_data[Mesh.ARRAY_INDEX] as PackedInt32Array

		if vertices.is_empty():
			continue

		if use_native and loader != null:
			var native_res = loader.extract_visible_triangles_native(
				vertices,
				normals,
				indices,
				world_transform,
				camera_position
			)
			
			result.total_triangles += native_res.get("total_triangles", 0)
			result.culled_backface += native_res.get("culled_backface", 0)
			
			var native_indices: PackedInt32Array = native_res.get("indices")
			var native_vertices: PackedVector3Array = native_res.get("vertices")
			var native_normals: PackedVector3Array = native_res.get("normals")
			var native_centers: PackedVector3Array = native_res.get("centers")
			var native_areas: PackedFloat32Array = native_res.get("areas")
			var native_distances: PackedFloat32Array = native_res.get("distances")
			
			var visible_tri_count = native_centers.size()
			for t_idx in range(visible_tri_count):
				var tri: VisibleTriangle = VisibleTriangle.new()
				tri.indices = [
					native_indices[t_idx * 3],
					native_indices[t_idx * 3 + 1],
					native_indices[t_idx * 3 + 2]
				]
				tri.vertices = [
					native_vertices[t_idx * 3],
					native_vertices[t_idx * 3 + 1],
					native_vertices[t_idx * 3 + 2]
				]
				tri.normals = [
					native_normals[t_idx * 3],
					native_normals[t_idx * 3 + 1],
					native_normals[t_idx * 3 + 2]
				]
				tri.center = native_centers[t_idx]
				tri.area = native_areas[t_idx]
				tri.distance_to_camera = native_distances[t_idx]
				result.visible_triangles.append(tri)
		else:
			result.total_triangles += indices.size() / 3
			
			# Parcourir les triangles (Repli GDScript)
			for i: int in range(0, indices.size() - 2, 3):
				var idx0: int = indices[i]
				var idx1: int = indices[i + 1]
				var idx2: int = indices[i + 2]

				# Transformer les vertices en espace mondial
				var v0_world: Vector3 = world_transform * vertices[idx0]
				var v1_world: Vector3 = world_transform * vertices[idx1]
				var v2_world: Vector3 = world_transform * vertices[idx2]

				var world_vertices: Array[Vector3] = [v0_world, v1_world, v2_world]

				# Backface culling
				if not is_front_facing(world_vertices, camera_position):
					result.culled_backface += 1
					continue

				# Occlusion approximative (test de distance simple)
				var center: Vector3 = (v0_world + v1_world + v2_world) / 3.0
				var distance: float = center.distance_to(camera_position)

				# Créer le triangle visible
				var tri: VisibleTriangle = VisibleTriangle.new()
				tri.indices = [idx0, idx1, idx2]
				tri.vertices = world_vertices
				tri.normals = [
					(world_transform.basis * normals[idx0]).normalized(),
					(world_transform.basis * normals[idx1]).normalized(),
					(world_transform.basis * normals[idx2]).normalized()
				]
				tri.center = center
				tri.area = triangle_area(world_vertices)
				tri.distance_to_camera = distance

				result.visible_triangles.append(tri)

	result.visible_count = result.visible_triangles.size()
	result.culled_occlusion = result.total_triangles - result.visible_count - result.culled_backface

	var end_time: int = Time.get_ticks_usec()
	result.extraction_time_ms = (end_time - start_time) / 1000.0

	return result

## Extraire les surfaces visibles pour les deux yeux (VR)
static func extract_visible_surfaces_stereo(
	splattable: FoveaSplattable,
	left_camera_pos: Vector3,
	right_camera_pos: Vector3,
	cull_result: Dictionary
) -> ExtractionResult:
	var combined_result: ExtractionResult = ExtractionResult.new()
	var seen_triangles: Dictionary = {}  # Pour éviter les doublons

	var left_result: ExtractionResult = null
	var right_result: ExtractionResult = null

	var has_left := cull_result.has("left")
	var has_right := cull_result.has("right")

	# Exécuter l'extraction des deux yeux en parallèle si les deux sont visibles (Optimisation CPU VR)
	if has_left and has_right:
		var thread_left := Thread.new()
		var thread_right := Thread.new()
		
		# Démarrer l'extraction de l'œil gauche
		thread_left.start(func() -> void:
			left_result = extract_visible_triangles(splattable, left_camera_pos, Transform3D.IDENTITY)
		)
		
		# Démarrer l'extraction de l'œil droit
		thread_right.start(func() -> void:
			right_result = extract_visible_triangles(splattable, right_camera_pos, Transform3D.IDENTITY)
		)
		
		thread_left.wait_to_finish()
		thread_right.wait_to_finish()
	else:
		if has_left:
			left_result = extract_visible_triangles(splattable, left_camera_pos, Transform3D.IDENTITY)
		if has_right:
			right_result = extract_visible_triangles(splattable, right_camera_pos, Transform3D.IDENTITY)

	# Fusionner les résultats de l'œil gauche
	if left_result != null:
		for tri: VisibleTriangle in left_result.visible_triangles:
			var key: String = _triangle_key(tri)
			if not seen_triangles.has(key):
				seen_triangles[key] = true
				combined_result.visible_triangles.append(tri)
		combined_result.total_triangles += left_result.total_triangles
		combined_result.culled_backface += left_result.culled_backface

	# Fusionner les résultats uniques de l'œil droit
	if right_result != null:
		for tri: VisibleTriangle in right_result.visible_triangles:
			var key: String = _triangle_key(tri)
			if not seen_triangles.has(key):
				seen_triangles[key] = true
				combined_result.visible_triangles.append(tri)
		combined_result.total_triangles += right_result.total_triangles
		combined_result.culled_backface += right_result.culled_backface

	combined_result.visible_count = combined_result.visible_triangles.size()
	return combined_result

## Générer une clé unique pour un triangle
static func _triangle_key(tri: VisibleTriangle) -> String:
	if tri.indices.size() < 3:
		return ""
	var sorted_indices: Array[int] = tri.indices.duplicate()
	sorted_indices.sort()
	return "%d_%d_%d" % [sorted_indices[0], sorted_indices[1], sorted_indices[2]]
