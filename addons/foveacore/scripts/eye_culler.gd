extends Node
class_name EyeCuller

## EyeCuller - Gestionnaire de frustum culling par œil pour VR
## Détermine quels objets sont visibles pour chaque œil

enum EyeIndex {
	LEFT = 0,
	RIGHT = 1
}

## Résultat du culling pour un œil
class EyeCullResult:
	var visible_nodes: Array[FoveaSplattable] = []
	var frustum: FrustumUtils.Frustum
	var cull_time_ms: float = 0.0

## Frustums pour chaque œil
var _left_frustum: FrustumUtils.Frustum
var _right_frustum: FrustumUtils.Frustum

## Cache des nœuds à culler
var _splattable_nodes: Array[FoveaSplattable] = []

## Statistiques
var _stats: Dictionary = {
	"total_nodes": 0,
	"left_visible": 0,
	"right_visible": 0,
	"both_visible": 0,
	"culled": 0
}

func _ready():
	_left_frustum = FrustumUtils.Frustum.new()
	_right_frustum = FrustumUtils.Frustum.new()

## Mettre à jour les frustums depuis les caméras VR
func update_frustums(
	left_projection: Projection, left_transform: Transform3D,
	right_projection: Projection, right_transform: Transform3D
):
	_left_frustum.from_matrix(left_projection, left_transform)
	_right_frustum.from_matrix(right_projection, right_transform)

## Enregistrer un nœud splattable pour le culling
func register_splattable(node: FoveaSplattable):
	if not _splattable_nodes.has(node):
		_splattable_nodes.append(node)

## Retirer un nœud splattable
func unregister_splattable(node: FoveaSplattable):
	_splattable_nodes.erase(node)

## Exécuter le culling pour les deux yeux
func cull_all() -> Dictionary:
	var start_time: int = Time.get_ticks_usec()

	var left_result: EyeCullResult = EyeCullResult.new()
	var right_result: EyeCullResult = EyeCullResult.new()
	left_result.frustum = _left_frustum
	right_result.frustum = _right_frustum

	var both_visible_count: int = 0

	for node in _splattable_nodes:
		if not is_instance_valid(node):
			continue

		var aabb: AABB = _get_world_aabb(node)
		var left_visible: bool = _left_frustum.contains_aabb(aabb)
		var right_visible: bool = _right_frustum.contains_aabb(aabb)

		if left_visible:
			left_result.visible_nodes.append(node)
		if right_visible:
			right_result.visible_nodes.append(node)
		if left_visible and right_visible:
			both_visible_count += 1

	var end_time: int = Time.get_ticks_usec()
	var elapsed_ms: float = (end_time - start_time) / 1000.0

	left_result.cull_time_ms = elapsed_ms
	right_result.cull_time_ms = elapsed_ms

	# Stats
	_stats["total_nodes"] = _splattable_nodes.size()
	_stats["left_visible"] = left_result.visible_nodes.size()
	_stats["right_visible"] = right_result.visible_nodes.size()
	_stats["both_visible"] = both_visible_count
	_stats["culled"] = _stats["total_nodes"] - both_visible_count

	return {
		"left": left_result,
		"right": right_result,
		"stats": _stats.duplicate()
	}

## Obtenir les statistiques de culling
func get_stats() -> Dictionary:
	return _stats.duplicate()

## Calculer l'AABB mondial d'un nœud
func _get_world_aabb(node: FoveaSplattable) -> AABB:
	if node.original_mesh != null:
		var local_aabb: AABB = node.original_mesh.get_aabb()
		return _transform_aabb(local_aabb, node.global_transform)
	else:
		# Fallback: AABB par défaut
		return AABB(node.global_position, Vector3.ONE)

## Transformer un AABB par une matrice
func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	var corners: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size
	]

	var min_point: Vector3 = transform * corners[0]
	var max_point: Vector3 = min_point

	for i in range(1, 8):
		var transformed: Vector3 = transform * corners[i]
		min_point = min_point.min(transformed)
		max_point = max_point.max(transformed)

	return AABB(min_point, max_point - min_point)
