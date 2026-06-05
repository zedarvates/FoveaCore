extends Node3D
## FoveaSplattable - Node à attacher aux MeshInstance3D pour activer le splatting
## Marque un objet comme candidat au Gaussian Splatting visible-only

class_name FoveaSplattable

## Référence statique au PLYLoader via preload
const _PlyLoaderScript = preload("res://addons/foveacore/scripts/reconstruction/ply_loader.gd")

## Densité locale des splats (1.0 = densité globale)
@export var splat_density := 1.0

## Chemin vers un fichier de Gaussian Splatting (.ply, .fovea, .spz)
@export_file("*.ply", "*.fovea", "*.spz") var splat_file_path: String = ""

## @deprecated Utiliser splat_file_path à la place.
## Conservé uniquement pour la compatibilité ascendante des scènes existantes.
## Migration : remplacer ply_file_path par splat_file_path dans l'inspecteur.
## Cette propriété sera supprimée dans une future version de FoveaCore.
@export_file("*.ply") var ply_file_path: String = ""

@export_group("Physics Collisions")
## Activer la génération de collision physique automatique depuis les voxels
@export var generate_collisions := false
## Résolution de la grille de voxels en mètres (ex: 0.15 = 15cm)
@export var voxel_size := 0.15
## Seuil d'opacité pour considérer un voxel comme solide (0.0..1.0)
@export_range(0.0, 1.0) var opacity_threshold := 0.1

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
	
	# Gestion de la compatibilité des fichiers de splats
	if splat_file_path.is_empty() and not ply_file_path.is_empty():
		splat_file_path = ply_file_path
		
	# Masquer le mesh si nécessaire
	if hide_mesh_when_splatting and splatting_enabled and _mesh_instance_ref != null:
		_mesh_instance_ref.visible = false
		
	# Charger le PLY si un chemin est fourni
	if not splat_file_path.is_empty():
		if splat_file_path.ends_with(".ply"):
			_load_splats_from_ply()
		elif splat_file_path.ends_with(".fovea"):
			print("FoveaSplattable: Rendu natif détecté pour ", splat_file_path)
			# Instancier dynamiquement FoveaSplatRenderer pour les assets natifs
			var renderer = FoveaSplatRenderer.new()
			renderer.name = "FoveaSplatRenderer"
			renderer.asset_path = splat_file_path
			renderer.sort_distance_threshold = 0.1
			add_child(renderer)
		else:
			print("FoveaSplattable: Format de fichier non géré pour le rendu direct: ", splat_file_path)
			
		if generate_collisions:
			if splat_file_path.ends_with(".fovea"):
				# call_deferred évite de bloquer le main thread au démarrage de scène
				# La collision est générée sur la prochaine frame (PERF-01 fix)
				call_deferred("_generate_collision_shape")
			else:
				push_warning("FoveaSplattable: La génération de collision physique nécessite un fichier .fovea (pas .ply). Convertir d'abord avec FoveaAssetLoader.convert_ply_to_fovea().")


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
	print("FoveaSplattable: Chargement PLY depuis '", splat_file_path, "'...")
	var gaussians = _PlyLoaderScript.load_gaussians_from_ply(splat_file_path)
	if gaussians == null or gaussians.is_empty():
		push_error("FoveaSplattable: PLYLoader returned empty")
		return
	loaded_splats = gaussians
	has_ply_splats = true
	print("FoveaSplattable: %d splats loaded from PLY" % loaded_splats.size())


## Génère et attache une collision physique ConcavePolygonShape3D
func _generate_collision_shape() -> void:
	print("FoveaSplattable: Génération de la collision physique via FoveaVoxelizer...")
	var collision_shape = FoveaVoxelizer.generate_collision_shape(splat_file_path, voxel_size, opacity_threshold)
	if collision_shape == null:
		push_warning("FoveaSplattable: Impossible de générer la collision pour " + splat_file_path)
		return
		
	var static_body = StaticBody3D.new()
	static_body.name = "SplatCollisionBody"
	
	var collision_node = CollisionShape3D.new()
	collision_node.name = "SplatCollisionShape"
	collision_node.shape = collision_shape
	
	static_body.add_child(collision_node)
	add_child(static_body)
	print("FoveaSplattable: Collision physique attachée avec succès au nœud.")


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
