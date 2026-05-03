extends Node3D
## FoveaSplattable - Node à attacher aux MeshInstance3D pour activer le splatting
## Marque un objet comme candidat au Gaussian Splatting visible-only

class_name FoveaSplattable

## Référence statique au PlyLoader via preload (évite le problème de scope class_name)
const _PlyLoaderScript = preload("res://addons/foveacore/scripts/ply_loader.gd")

## Densité locale des splats (1.0 = densité globale)
@export var splat_density := 1.0

## Chemin vers un fichier .ply de Gaussian Splatting (optionnel)
## Si renseigné, les splats sont chargés depuis ce fichier au lieu d'être générés procéduralement
@export_file("*.ply") var ply_file_path: String = ""

## Override du style local (null = utiliser le style global)
@export var style_override: FoveaStyle = null

## Activer/désactiver le splatting pour cet objet
@export var splatting_enabled := true

## Masquer le mesh original (pour ne voir que le nuage de points/splats)
@export var hide_mesh_when_splatting := true

## Priorité de culling (0 = toujours culler en premier si nécessaire)
@export_range(0, 10) var culling_priority := 5

## Référence au mesh original
var original_mesh: Mesh = null

## Référence au MeshInstance3D trouvé (parent ou enfant)
var _mesh_instance_ref: MeshInstance3D = null

## Splats chargés depuis un fichier PLY (si ply_file_path est défini)
var loaded_splats: Array[GaussianSplat] = []

## Indique si les splats ont été chargés depuis un PLY
var has_ply_splats: bool = false

## Buffer GPU pour les splats (géré par le renderer natif)
var splat_buffer_rid: RID = RID()


func _enter_tree() -> void:
	var manager = get_node_or_null("/root/FoveaCoreManager")
	if manager:
		manager.register_splattable(self)


func _exit_tree() -> void:
	var manager = get_node_or_null("/root/FoveaCoreManager")
	if manager:
		manager.unregister_splattable(self)


func _ready() -> void:
	_capture_mesh_reference()
	# Masquer le mesh si nécessaire
	if hide_mesh_when_splatting and splatting_enabled and _mesh_instance_ref != null:
		_mesh_instance_ref.visible = false
	# Charger le PLY si un chemin est fourni
	if not ply_file_path.is_empty():
		_load_splats_from_ply()


## Cherche un MeshInstance3D dans le parent ou les enfants directs.
## FoveaSplattable extends Node3D (pas MeshInstance3D), on ne peut pas faire `self is MeshInstance3D`.
func _capture_mesh_reference() -> void:
	# 1. Le parent est-il un MeshInstance3D ?
	var parent := get_parent()
	if parent is MeshInstance3D:
		_mesh_instance_ref = parent as MeshInstance3D
		original_mesh = _mesh_instance_ref.mesh
		return

	# 2. Y a-t-il un enfant direct MeshInstance3D ?
	for child in get_children():
		if child is MeshInstance3D:
			_mesh_instance_ref = child as MeshInstance3D
			original_mesh = _mesh_instance_ref.mesh
			return

	# 3. Un enfant nommé "MeshInstance3D" ?
	var named_child := get_node_or_null("MeshInstance3D")
	if named_child != null and named_child is MeshInstance3D:
		_mesh_instance_ref = named_child as MeshInstance3D
		original_mesh = _mesh_instance_ref.mesh


## Charger les splats depuis le fichier PLY configuré
func _load_splats_from_ply() -> void:
	print("FoveaSplattable: Chargement PLY depuis '", ply_file_path, "'...")
	var load_result = _PlyLoaderScript.load_ply(ply_file_path)
	if load_result == null:
		push_error("FoveaSplattable: PlyLoader a retourné null")
		return
	if load_result.success:
		loaded_splats = load_result.splats
		has_ply_splats = true
		print("FoveaSplattable: %d splats chargés depuis PLY" % loaded_splats.size())
	else:
		push_error("FoveaSplattable: Échec chargement PLY — " + load_result.error_message)


func set_density(density: float) -> void:
	splat_density = clamp(density, 0.1, 5.0)


func is_visible_to_camera(camera: Camera3D) -> bool:
	if camera == null:
		return true
	# Test AABB + frustum sur les 8 coins du bounding box
	if original_mesh != null:
		var world_aabb := original_mesh.get_aabb()
		var gtr := global_transform
		var p := world_aabb.position
		var s := world_aabb.size
		var corners := [
			gtr * p,
			gtr * (p + Vector3(s.x, 0.0, 0.0)),
			gtr * (p + Vector3(0.0, s.y, 0.0)),
			gtr * (p + Vector3(0.0, 0.0, s.z)),
			gtr * (p + Vector3(s.x, s.y, 0.0)),
			gtr * (p + Vector3(s.x, 0.0, s.z)),
			gtr * (p + Vector3(0.0, s.y, s.z)),
			gtr * (p + s)
		]
		for corner in corners:
			if camera.is_position_in_frustum(corner):
				return true
		return false
	# Pas de mesh — tester juste la position du nœud
	return camera.is_position_in_frustum(global_position)
