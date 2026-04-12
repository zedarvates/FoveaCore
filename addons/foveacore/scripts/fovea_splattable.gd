extends Node3D
## FoveaSplattable - Node à attacher aux MeshInstance3D pour activer le splatting
## Marque un objet comme candidat au Gaussian Splatting visible-only

class_name FoveaSplattable

## Densité locale des splats (1.0 = densité globale)
@export var splat_density := 1.0

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

## Buffer GPU pour les splats (géré par le renderer natif)
var splat_buffer_rid: RID = RID()

func _enter_tree():
	var manager: FoveaCoreManager = get_node_or_null("/root/FoveaCoreManager")
	if manager:
		manager.register_splattable(self)

func _exit_tree():
	var manager: FoveaCoreManager = get_node_or_null("/root/FoveaCoreManager")
	if manager:
		manager.unregister_splattable(self)

func _ready():
	_capture_mesh_reference()
	if hide_mesh_when_splatting and splatting_enabled:
		if self is MeshInstance3D:
			self.visible = false
		elif has_node("MeshInstance3D"):
			get_node("MeshInstance3D").visible = false

func _capture_mesh_reference():
	if self is MeshInstance3D:
		original_mesh = self.mesh
	elif has_node("MeshInstance3D"):
		var mesh_instance = $MeshInstance3D as MeshInstance3D
		if mesh_instance:
			original_mesh = mesh_instance.mesh

func set_density(density: float):
	splat_density = clamp(density, 0.1, 5.0)

func is_visible_to_camera(camera: Camera3D) -> bool:
	# TODO: Implémenter le test de visibilité
	return true
