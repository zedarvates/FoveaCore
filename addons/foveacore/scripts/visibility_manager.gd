extends Node
class_name VisibilityManager

## VisibilityManager - Orchestre l'extraction de surfaces visibles
## Combine le culling par œil avec l'extraction de triangles visibles

## Résultat de visibilité pour un frame
class FrameVisibilityResult:
	var total_visible_nodes: int = 0
	var total_visible_triangles: int = 0
	var total_triangles: int = 0
	var extraction_time_ms: float = 0.0
	var per_node_results: Dictionary = {}  # Node -> ExtractionResult

## Référence au culler
var _eye_culler: EyeCuller = null

## Cache des nœuds à traiter
var _splattable_nodes: Array[FoveaSplattable] = []

## Positions des caméras VR
var _left_camera_pos: Vector3 = Vector3.ZERO
var _right_camera_pos: Vector3 = Vector3.ZERO
var _left_camera_transform: Transform3D = Transform3D.IDENTITY
var _right_camera_transform: Transform3D = Transform3D.IDENTITY

func _ready():
	pass

## Configurer le gestionnaire avec le culler
func setup(eye_culler: EyeCuller):
	_eye_culler = eye_culler

## Enregistrer un nœud
func register_splattable(node: FoveaSplattable):
	if not _splattable_nodes.has(node):
		_splattable_nodes.append(node)

## Retirer un nœud
func unregister_splattable(node: FoveaSplattable):
	_splattable_nodes.erase(node)

## Mettre à jour les positions des caméras VR
func update_camera_positions(
	left_pos: Vector3, left_transform: Transform3D,
	right_pos: Vector3, right_transform: Transform3D
):
	_left_camera_pos = left_pos
	_left_camera_transform = left_transform
	_right_camera_pos = right_pos
	_right_camera_transform = right_transform

## Exécuter l'extraction de surfaces visibles pour un frame
func extract_visible_surfaces() -> FrameVisibilityResult:
	var start_time: int = Time.get_ticks_usec()
	var result: FrameVisibilityResult = FrameVisibilityResult.new()

	if _eye_culler == null:
		return result

	# Exécuter le culling
	var cull_result: Dictionary = _eye_culler.cull_all()

	# Pour chaque nœud visible, extraire les triangles
	var left_nodes: Array = cull_result["left"].visible_nodes as Array
	var right_nodes: Array = cull_result["right"].visible_nodes as Array

	# Combiner les nœuds visibles des deux yeux
	var all_visible_nodes: Array[FoveaSplattable] = []
	var seen_nodes: Dictionary = {}

	for node: FoveaSplattable in left_nodes + right_nodes:
		if is_instance_valid(node) and not seen_nodes.has(node):
			seen_nodes[node] = true
			all_visible_nodes.append(node)

	result.total_visible_nodes = all_visible_nodes.size()

	# Extraire les triangles pour chaque nœud visible
	for node: FoveaSplattable in all_visible_nodes:
		var extraction: SurfaceExtractor.ExtractionResult = SurfaceExtractor.extract_visible_surfaces_stereo(
			node,
			_left_camera_pos,
			_right_camera_pos,
			cull_result
		)

		result.per_node_results[node] = extraction
		result.total_visible_triangles += extraction.visible_count
		result.total_triangles += extraction.total_triangles

	var end_time: int = Time.get_ticks_usec()
	result.extraction_time_ms = (end_time - start_time) / 1000.0

	return result

## Obtenir les statistiques de visibilité
func get_stats() -> Dictionary:
	return {
		"registered_nodes": _splattable_nodes.size(),
		"left_camera_pos": _left_camera_pos,
		"right_camera_pos": _right_camera_pos
	}
