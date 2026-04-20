class_name SplatGenerator

## SplatGenerator - Génère des splats gaussiens depuis les triangles visibles
## Cœur du pipeline FoveaCore

## Configuration du générateur
class SplatConfig:
	var splats_per_triangle: int = 3        # Nombre de splats par triangle
	var min_radius: float = 0.02            # Rayon minimum
	var max_radius: float = 0.3             # Rayon maximum
	var density_multiplier: float = 1.0     # Multiplicateur de densité
	var color_from_normal: bool = false     # Utiliser la normale pour la couleur
	var depth_aware_blending: bool = true   # Blending conscient de la profondeur


## Résultat de la génération
class SplatGenerationResult:
	var splats: Array[GaussianSplat] = []
	var total_splats: int = 0
	var generation_time_ms: float = 0.0
	var source_triangles: int = 0


## Configuration par défaut
static var default_config: SplatConfig = SplatConfig.new()


## Générer des splats depuis les triangles visibles d'un nœud
static func generate_splats_from_triangles(
	triangles: Array,  # Array[VisibleTriangle]
	camera_position: Vector3,
	config: SplatConfig,
	splat_density: float = 1.0
) -> SplatGenerationResult:
	var start_time: int = Time.get_ticks_usec()
	var result: SplatGenerationResult = SplatGenerationResult.new()
	result.source_triangles = triangles.size()

	for triangle in triangles:
		# Vérifier que le triangle a les données nécessaires
		if triangle.vertices.size() < 3:
			continue

		var tri_area: float = triangle.area
		if tri_area < 0.001:
			continue

		# Générer des points d'échantillonnage sur le triangle
		var points: Array = _sample_triangle(triangle, config.splats_per_triangle)

		for point_data in points:
			var pos: Vector3 = point_data["position"] as Vector3
			var barycentric: Vector3 = point_data["barycentric"] as Vector3

			# Interpoler la normale
			var normal: Vector3 = (
				triangle.normals[0] * barycentric.x +
				triangle.normals[1] * barycentric.y +
				triangle.normals[2] * barycentric.z
			).normalized()

			# Calculer la couleur (procédurale ou depuis la normale)
			var splat_color: Color = _compute_color(pos, normal, tri_area)

			# Créer le splat
			var splat: GaussianSplat = GaussianSplat.create_from_triangle(
				pos, normal, splat_color, tri_area, camera_position, splat_density
			)

			# Appliquer les limites de rayon
			splat.radius = clamp(splat.radius, config.min_radius, config.max_radius)

			# Depth-aware blending
			if config.depth_aware_blending:
				var depth_factor: float = 1.0 / (1.0 + splat.depth * 0.1)
				splat.opacity *= depth_factor

			result.splats.append(splat)

	result.total_splats = result.splats.size()

	var end_time: int = Time.get_ticks_usec()
	result.generation_time_ms = (end_time - start_time) / 1000.0

	return result


## Échantillonner des points sur un triangle
static func _sample_triangle(triangle, count: int) -> Array:
	var points: Array = []
	var v0: Vector3 = triangle.vertices[0]
	var v1: Vector3 = triangle.vertices[1]
	var v2: Vector3 = triangle.vertices[2]

	for _i in range(count):
		# Échantillonnage barycentrique uniforme
		var r1: float = randf()
		var r2: float = randf()
		var sqrt_r1: float = sqrt(r1)

		var u: float = 1.0 - sqrt_r1
		var v: float = sqrt_r1 * (1.0 - r2)
		var w: float = sqrt_r1 * r2

		var pos: Vector3 = v0 * u + v1 * v + v2 * w
		points.append({
			"position": pos,
			"barycentric": Vector3(u, v, w)
		})

	return points


## Calculer la couleur d'un splat via le StyleEngine
static func _compute_color(position: Vector3, normal: Vector3, area: float, material_type: int = 0) -> Color:
	var config = StyleEngine.MaterialStyleConfig.new()
	config.material_type = material_type
	config.base_color = Color(0.7, 0.7, 0.7)
	config.detail = 1.0
	config.grain = 0.5
	config.light_coherence = 0.8
	config.micro_shadow = 0.5
	config.noise_scale = 10.0
	config.noise_octaves = 4

	var light_dir = Vector3(0, 1, 0.5).normalized()
	return StyleEngine.compute_color(position, normal, material_type, config, light_dir)


## Noise simple procédural (remplacera par FBM/Worley plus tard)
static func _simple_noise(pos: Vector3) -> float:
	var n: float = sin(pos.x * 12.9898 + pos.y * 78.233 + pos.z * 45.543) * 43758.5453
	return n - floor(n)


## Générer des splats pour tous les nœuds visibles
static func generate_all_splats(
	visibility_result,  # FrameVisibilityResult
	camera_position: Vector3,
	config: SplatConfig,
	global_density: float = 1.0
) -> Array[GaussianSplat]:
	var all_splats: Array[GaussianSplat] = []

	if visibility_result.per_node_results.is_empty():
		return all_splats

	for node in visibility_result.per_node_results:
		var extraction: SurfaceExtractor.ExtractionResult = visibility_result.per_node_results[node] as SurfaceExtractor.ExtractionResult

		# Obtenir la densité locale du nœud
		var local_density: float = global_density
		if node is FoveaSplattable:
			local_density *= node.splat_density

		var node_result: SplatGenerationResult = generate_splats_from_triangles(
			extraction.visible_triangles,
			camera_position,
			config,
			local_density
		)

		all_splats.append_array(node_result.splats)

	return all_splats
