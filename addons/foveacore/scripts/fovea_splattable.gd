@tool
extends Node3D
## FoveaSplattable - Node à attacher aux MeshInstance3D pour activer le splatting
## Marque un objet comme candidat au Gaussian Splatting visible-only

class_name FoveaSplattable

# ─────────────────────────────────────────────────────────────
#  Events / Signals
# ─────────────────────────────────────────────────────────────

## Emitted when 3D segmentation begins on this splattable node.
## [param prompt] represents the text description or prompt target of the segmentation.
signal segmentation_started(prompt: String)

## Emitted when 3D segmentation completes on this node.
## [param success] is [code]true[/code] if the segmentation successfully finished and updated the splats.
signal segmentation_completed(success: bool)

## Emitted when asset conversion and compression to the native [code].fovea[/code] format starts.
## [param dest_path] is the destination path on disk where the asset will be written.
signal conversion_started(dest_path: String)

## Emitted when asset conversion and compression to [code].fovea[/code] completes.
## [param success] is [code]true[/code] if the export was successful.
## [param dest_path] is the path of the successfully written asset.
signal conversion_completed(success: bool, dest_path: String)

## Emitted when procedural splat generation starts.
signal generation_started()

## Emitted when procedural splats are successfully generated from the node's mesh.
## [param splat_count] is the total number of splats generated.
signal generation_completed(splat_count: int)

# ─────────────────────────────────────────────────────────────
#  Static References & Exports
# ─────────────────────────────────────────────────────────────

## Static reference to the PLYLoader script.
const _PlyLoaderScript = preload("res://addons/foveacore/scripts/reconstruction/ply_loader.gd")
## Unified point-cloud loader (routes .ply/.splat/.spz/.sog by extension).
const _SplatFormatLoaderScript = preload("res://addons/foveacore/scripts/reconstruction/splat_format_loader.gd")

## Local multiplier for splat density (e.g. 1.0 matches the global density).
@export var splat_density := 1.0

## Path to a Gaussian Splatting file (.ply, .fovea, .spz, .splat).
@export_file("*.ply", "*.fovea", "*.spz", "*.splat") var splat_file_path: String = "":
	set(val):
		splat_file_path = val
		if is_node_ready():
			if splat_file_path.ends_with(".ply") or splat_file_path.ends_with(".splat"):
				_load_splats_from_ply()
			elif splat_file_path.ends_with(".fovea"):
				var renderer: Node = get_node_or_null("SplatRenderer")
				if renderer:
					renderer.queue_free()
				_setup_native_renderer()

## @deprecated Use [member splat_file_path] instead.
## Maintained for backwards compatibility with existing scenes.
@export_file("*.ply") var ply_file_path: String = "":
	set(val):
		ply_file_path = val
		if splat_file_path.is_empty() and not ply_file_path.is_empty():
			splat_file_path = ply_file_path

@export_group("AI Segmentation & Tagging")
## Tag text/prompt to segment in 3D (e.g. "liquid", "wood", "cloth", "stone").
## Run it from the "Fovea Actions" buttons at the top of the inspector,
## or call [method run_segmentation] from code.
@export var run_segmentation_prompt: String = ""

# Note : les anciens déclencheurs "checkbox-bouton" (trigger_segmentation,
# trigger_conversion_to_fovea, trigger_generation) sont remplacés par de vrais
# boutons d'inspecteur — voir editor/fovea_splattable_inspector_plugin.gd.
# Les actions restent accessibles en code : run_segmentation(), export_to_fovea(),
# generate_splats_now().

@export_group("Physics Collisions")
## If [code]true[/code], generates a physical collision shape from the splat voxels.
@export var generate_collisions := false
## Grid resolution of voxels used for collision generation, in meters (e.g. 0.15 is 15cm).
@export var voxel_size := 0.15
## Opacity threshold (0.0 to 1.0) above which a voxel is considered solid.
@export_range(0.0, 1.0) var opacity_threshold := 0.1

## Local override style resource (null will inherit the global FoveaCoreManager style).
@export var style_override: FoveaStyle = null

## If [code]true[/code], enables splatting for this object.
@export var splatting_enabled := true

## If [code]true[/code], enables shared instanced rendering (Global Splat Instancing) for .fovea assets.
@export var enable_instancing: bool = true

## If [code]true[/code], this asset is treated as completely static/stable.
## Static assets bypass redundant GPU culling/sorting dispatches on mobile.
## Dynamic assets support skeletal skinning, physics solver, and get sorted every frame.
@export var is_static: bool = true:
	set(val):
		is_static = val
		var renderer = get_node_or_null("FoveaCoreSplatRenderer")
		if renderer:
			renderer.is_static = val


@export_group("Delta-Splat Overrides")
## Custom tint color override applied to this instance.
@export var color_override: Color = Color.WHITE
## Custom scale multiplier override applied to this instance.
@export var scale_override: float = 1.0
## Custom alpha/opacity multiplier override (0.0 to 1.0) applied to this instance.
@export var alpha_override: float = 1.0
## Type de déformation locale appliqué à cette instance (morph).
@export_enum("None", "Bend", "Twist", "Squish", "Wave") var morph_type: String = "None"
## Force de la déformation (0.0 = aucun effet, 1.0 = effet maximum).
@export_range(0.0, 1.0) var morph_weight: float = 0.0
## Valeur cible pour le morphing (permet une interpolation fluide).
@export_range(0.0, 1.0) var morph_weight_target: float = 0.0
## Vitesse d'interpolation (0 = instantané, >0 = vitesse d'interpolation).
@export var morph_interpolation_speed: float = 5.0
## Fréquence spatiale du morphing.
@export var morph_frequency: float = 1.0
## Amplitude maximale du morphing.
@export var morph_amplitude: float = 0.5

## Force de l'application du delta (0.0 = aucun effet, 1.0 = effet maximum).
@export_range(0.0, 1.0) var delta_weight: float = 0.0
## Valeur cible pour le delta (permet une interpolation fluide).
@export_range(0.0, 1.0) var delta_weight_target: float = 0.0
## Vitesse d'interpolation du delta.
@export var delta_interpolation_speed: float = 5.0

## If [code]true[/code], hides the original MeshInstance3D when splatting is active.
@export var hide_mesh_when_splatting := true

## Culling priority (0 is culled first, 10 is culled last).
@export_range(0, 10) var culling_priority := 5

@export_file("*.fvdelta") var delta_file_path: String = "":
	set(val):
		delta_file_path = val
		if not delta_file_path.is_empty():
			load_delta_file(delta_file_path)

## Delta colors (tint overrides per splat index: local_idx -> Color)
var delta_colors: Dictionary = {}
## Delta positions (deform offsets per splat index: local_idx -> Vector3)
var delta_positions: Dictionary = {}

func save_delta_file(path: String) -> void:
	if loaded_splats.is_empty():
		return
	FoveaDeltaData.save_to_file(path, loaded_splats.size(), delta_positions, delta_colors, {})

func load_delta_file(path: String) -> void:
	var result: Variant = FoveaDeltaData.load_from_file(path)
	if result is Dictionary and not result.is_empty():
		delta_positions = result.delta_positions
		delta_colors = result.delta_colors

## Référence au mesh original
var original_mesh: Mesh = null

## Référence au MeshInstance3D trouvé (parent ou enfant)
var _mesh_instance_ref: MeshInstance3D = null

## Splats chargés depuis un fichier PLY (si ply_file_path est défini)
var loaded_splats: Array[GaussianSplat] = []

## Grille spatiale pour les requêtes de proximité (ex: SplatBrushEngine)
var spatial_grid: RefCounted = null

## Indique si les splats ont été chargés depuis un PLY
var has_ply_splats: bool = false

## Buffer GPU pour les splats (géré par le renderer natif)
var splat_buffer_rid: RID = RID()

## Sets a delta tint color on a specific splat index.
func set_delta_color(local_idx: int, color: Color) -> void:
	delta_colors[local_idx] = color

## Sets a delta position deformation offset on a specific splat index.
func set_delta_position(local_idx: int, offset: Vector3) -> void:
	delta_positions[local_idx] = offset


func _enter_tree() -> void:
	add_to_group("splattables")
	var manager: Node = get_node_or_null("/root/FoveaCoreManager")
	if manager:
		manager.register_splattable(self)


func _exit_tree() -> void:
	remove_from_group("splattables")
	var manager: Node = get_node_or_null("/root/FoveaCoreManager")
	if manager:
		manager.unregister_splattable(self)


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		if morph_interpolation_speed > 0.0:
			morph_weight = move_toward(morph_weight, morph_weight_target, morph_interpolation_speed * delta)
		else:
			morph_weight = morph_weight_target
			
		if delta_interpolation_speed > 0.0:
			delta_weight = move_toward(delta_weight, delta_weight_target, delta_interpolation_speed * delta)
		else:
			delta_weight = delta_weight_target


func _ready() -> void:
	morph_weight_target = morph_weight
	delta_weight_target = delta_weight
	_capture_mesh_reference()
	
	# Gestion de la compatibilité des fichiers de splats
	if splat_file_path.is_empty() and not ply_file_path.is_empty():
		splat_file_path = ply_file_path
		
	# Masquer le mesh si nécessaire
	if hide_mesh_when_splatting and splatting_enabled and _mesh_instance_ref != null:
		_mesh_instance_ref.visible = false
		
	# Charger le nuage de points si un chemin est fourni
	if not splat_file_path.is_empty():
		if splat_file_path.ends_with(".ply") or splat_file_path.ends_with(".splat"):
			_load_splats_from_ply()
		elif splat_file_path.ends_with(".fovea"):
			_setup_native_renderer()
		else:
			print("FoveaSplattable: Format de fichier non géré pour le rendu direct: ", splat_file_path)
			
		if generate_collisions:
			if splat_file_path.ends_with(".fovea"):
				# call_deferred évite de bloquer le main thread au démarrage de scène
				# La collision est générée sur la prochaine frame (PERF-01 fix)
				call_deferred("_generate_collision_shape")
			else:
				push_warning("FoveaSplattable: La génération de collision physique nécessite un fichier .fovea (pas .ply). Convertir d'abord avec FoveaAssetLoader.convert_ply_to_fovea().")


func _setup_native_renderer() -> void:
	if not splat_file_path.ends_with(".fovea"):
		return
	if enable_instancing:
		if not Engine.is_editor_hint():
			print("FoveaSplattable: Rendu instancié global activé pour ", splat_file_path)
		return
	if not Engine.is_editor_hint():
		print("FoveaSplattable: Rendu natif local détecté pour ", splat_file_path)
	
	# Instancier dynamiquement FoveaCoreSplatRenderer pour les assets natifs
	var renderer: FoveaCoreSplatRenderer = get_node_or_null("FoveaCoreSplatRenderer") as FoveaCoreSplatRenderer
	if not renderer:
		renderer = FoveaCoreSplatRenderer.new()
		renderer.name = "FoveaCoreSplatRenderer"
		renderer.sort_distance_threshold = 0.1
		renderer.is_static = is_static
		add_child(renderer)
	renderer.asset_path = splat_file_path



## Calculates the gravity vector and aligns the entire splat cloud's up direction with absolute Vector3.UP.
func align_to_gravity_plane() -> void:
	if loaded_splats.is_empty():
		push_warning("FoveaSplattable: Cannot align splats, loaded_splats is empty.")
		return
	
	# 1. Collect all Y coordinates to find the lowest 10%
	var y_coords: Array[float] = []
	for splat in loaded_splats:
		y_coords.append(splat.position.y)
	y_coords.sort()
	
	var threshold_idx: int = int(y_coords.size() * 0.1)
	if threshold_idx == 0:
		threshold_idx = 1
	var y_threshold: float = y_coords[threshold_idx]
	
	# 2. Extract bottom splats
	var bottom_points: Array[Vector3] = []
	for splat in loaded_splats:
		if splat.position.y <= y_threshold:
			bottom_points.append(splat.position)
	
	if bottom_points.size() < 3:
		push_warning("FoveaSplattable: Not enough points in the lowest 10% to compute gravity plane.")
		return
		
	# 3. Calculate plane normal using least squares fit (y = ax + bz + c)
	var sum_xx: float = 0.0
	var sum_xz: float = 0.0
	var sum_x: float = 0.0
	var sum_zz: float = 0.0
	var sum_z: float = 0.0
	var sum_xy: float = 0.0
	var sum_zy: float = 0.0
	var sum_y: float = 0.0
	var n_pts: float = float(bottom_points.size())
	
	for pt in bottom_points:
		sum_xx += pt.x * pt.x
		sum_xz += pt.x * pt.z
		sum_x += pt.x
		sum_zz += pt.z * pt.z
		sum_z += pt.z
		sum_xy += pt.x * pt.y
		sum_zy += pt.z * pt.y
		sum_y += pt.y
		
	var det: float = sum_xx * (sum_zz * n_pts - sum_z * sum_z) - \
					 sum_xz * (sum_xz * n_pts - sum_x * sum_z) + \
					 sum_x  * (sum_xz * sum_z - sum_x * sum_zz)
					
	var normal: Vector3 = Vector3.UP
	if abs(det) > 1e-6:
		var a: float = ((sum_zz * n_pts - sum_z * sum_z) * sum_xy + \
						(sum_x * sum_z - sum_xz * n_pts) * sum_zy + \
						(sum_xz * sum_z - sum_x * sum_zz) * sum_y) / det
						
		var b: float = ((sum_x * sum_z - sum_xz * n_pts) * sum_xy + \
						(sum_xx * n_pts - sum_x * sum_x) * sum_zy + \
						(sum_x * sum_xz - sum_xx * sum_z) * sum_y) / det
		
		# Normal points generally upwards, from Y = ax + bz + c it corresponds to (-a, 1, -b)
		normal = Vector3(-a, 1.0, -b).normalized()
	
	# 4. Calculate rotation quaternion Q from normal to Vector3.UP
	var q: Quaternion = Quaternion(normal, Vector3.UP)
	
	# 5. Apply Q to all splats: position, rotation
	for splat in loaded_splats:
		splat.position = q * splat.position
		splat.rotation = q * splat.rotation
		
	# 6. Update local renderer and print result
	_update_local_renderer()
	print("FoveaSplattable: Gravitational Up-Vector alignment complete using normal: ", normal)


func _update_local_renderer() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Engine.is_editor_hint() or not get_node_or_null("/root/FoveaCoreManager"):
		if has_ply_splats and not loaded_splats.is_empty():
			var renderer: Node = get_node_or_null("SplatRenderer")
			if not renderer:
				var SplatRendererScript: GDScript = load("res://addons/foveacore/scripts/reconstruction/splat_renderer.gd") as GDScript
				if SplatRendererScript:
					renderer = SplatRendererScript.new() as Node
					renderer.name = "SplatRenderer"
					add_child(renderer)
			if renderer:
				renderer.call("load_splats", loaded_splats)


## Runs 3D semantic segmentation on this splattable using the specified prompt.
## Emits [signal segmentation_started] and [signal segmentation_completed].
func run_segmentation(prompt: String) -> void:
	print("FoveaSplattable: Démarrage de la segmentation pour le prompt : '", prompt, "'...")
	var SegmentationBridgeScript: GDScript = load("res://addons/foveacore/scripts/advanced/fovea_segmentation_bridge.gd")
	if not SegmentationBridgeScript:
		push_error("FoveaSplattable: Impossible de charger le script FoveaSegmentationBridge.")
		segmentation_completed.emit(false)
		return
	segmentation_started.emit(prompt)
	var bridge: Object = SegmentationBridgeScript.new()
	bridge.use_simulation = true # La simulation locale fonctionne de manière autonome
	bridge.segment_splattable(self, prompt, func(success: bool):
		if success:
			print("FoveaSplattable: Segmentation effectuée avec succès.")
			_update_local_renderer()
		else:
			push_error("FoveaSplattable: Échec de la segmentation.")
		segmentation_completed.emit(success)
	)


## Converts and compresses the loaded Gaussian splats into a native binary [code].fovea[/code] asset.
## Saves the output to [param dest_path]. Returns [code]true[/code] if successful.
## Emits [signal conversion_started] and [signal conversion_completed].
func export_to_fovea(dest_path: String) -> bool:
	if loaded_splats.is_empty():
		push_error("FoveaSplattable: Aucun splat chargé à exporter.")
		conversion_completed.emit(false, dest_path)
		return false
	
	print("FoveaSplattable: Conversion et compression au format .fovea vers : ", dest_path)
	conversion_started.emit(dest_path)
	var FoveaAssetWriterScript: GDScript = load("res://addons/foveacore/scripts/fovea_asset_writer.gd")
	if not FoveaAssetWriterScript:
		push_error("FoveaSplattable: Script FoveaAssetWriter introuvable.")
		conversion_completed.emit(false, dest_path)
		return false
		
	var success: bool = FoveaAssetWriterScript.write_fovea_asset(dest_path, loaded_splats, null, style_override, {
		"session": "Imported & Compressed",
		"exported_by": "FoveaSplattable Editor Tool",
		"timestamp": Time.get_unix_time_from_system()
	})
	
	if success:
		print("FoveaSplattable: Asset .fovea exporté et compressé avec succès à : ", dest_path)
		splat_file_path = dest_path
	else:
		push_error("FoveaSplattable: Échec de l'écriture de l'asset .fovea.")
	
	conversion_completed.emit(success, dest_path)
	return success


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


## Charge les splats depuis le fichier configuré (.ply / .splat / …), via le
## routeur de formats. Le nom historique est conservé car des appelants externes
## (plugin.gd) l'invoquent directement.
func _load_splats_from_ply() -> void:
	print("FoveaSplattable: Chargement du nuage depuis '", splat_file_path, "'...")
	var gaussians: Array = _SplatFormatLoaderScript.load_gaussians(splat_file_path)
	if gaussians.is_empty():
		push_error("FoveaSplattable: loader returned empty for " + splat_file_path)
		return
	loaded_splats = gaussians
	has_ply_splats = true
	print("FoveaSplattable: %d splats loaded from %s" % [loaded_splats.size(), splat_file_path.get_extension()])
	_update_local_renderer()


## Génère et attache une collision physique ConcavePolygonShape3D
func _generate_collision_shape() -> void:
	print("FoveaSplattable: Génération de la collision physique via FoveaVoxelizer...")
	var collision_shape: Shape3D = FoveaVoxelizer.generate_collision_shape(splat_file_path, voxel_size, opacity_threshold)
	if collision_shape == null:
		push_warning("FoveaSplattable: Impossible de générer la collision pour " + splat_file_path)
		return
		
	var static_body: StaticBody3D = StaticBody3D.new()
	static_body.name = "SplatCollisionBody"
	
	var collision_node: CollisionShape3D = CollisionShape3D.new()
	collision_node.name = "SplatCollisionShape"
	collision_node.shape = collision_shape
	
	static_body.add_child(collision_node)
	add_child(static_body)
	print("FoveaSplattable: Collision physique attachée avec succès au nœud.")


## Sets the local splat density multiplier, clamped between [code]0.1[/code] and [code]5.0[/code].
func set_density(density: float) -> void:
	splat_density = clamp(density, 0.1, 5.0)


## Checks if the splattable is visible to the given camera frustum (AABB/position culling).
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


func get_aabb() -> AABB:
	if original_mesh != null:
		return original_mesh.get_aabb()
	
	if splat_file_path != "" and ClassDB.class_exists("FoveaAssetLoader") and ClassDB.can_instantiate("FoveaAssetLoader"):
		var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
		if loader and loader.has_method("get_asset_aabb"):
			var aabb_val: Variant = loader.get_asset_aabb(splat_file_path)
			if aabb_val is AABB:
				return aabb_val
				
	# Fallback box
	return AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))


## Procedurally generates Gaussian splats from the vertex and normal arrays of the attached mesh.
## Emits [signal generation_started] and [signal generation_completed].
func generate_splats_now() -> void:
	print("FoveaSplattable: Generating procedural splats...")
	_capture_mesh_reference()
	if original_mesh == null:
		push_error("FoveaSplattable: Cannot generate splats, no mesh found.")
		generation_completed.emit(0)
		return
	
	generation_started.emit()
	var triangles: Array = []
	var mesh: Mesh = original_mesh
	
	for surface_idx in range(mesh.get_surface_count()):
		var mesh_data: Array = mesh.surface_get_arrays(surface_idx)
		if mesh_data.size() < Mesh.ARRAY_INDEX:
			continue
		
		var vertices: PackedVector3Array = mesh_data[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = mesh_data[Mesh.ARRAY_NORMAL] if mesh_data[Mesh.ARRAY_NORMAL] else PackedVector3Array()
		var indices: PackedInt32Array = mesh_data[Mesh.ARRAY_INDEX]
		
		for i in range(0, indices.size() - 2, 3):
			var idx0: int = indices[i]
			var idx1: int = indices[i + 1]
			var idx2: int = indices[i + 2]
			
			var tri: SurfaceExtractor.VisibleTriangle = SurfaceExtractor.VisibleTriangle.new()
			tri.indices = [idx0, idx1, idx2]
			tri.vertices = [vertices[idx0], vertices[idx1], vertices[idx2]]
			
			var n0: Vector3 = normals[idx0] if normals.size() > idx0 else Vector3.UP
			var n1: Vector3 = normals[idx1] if normals.size() > idx1 else Vector3.UP
			var n2: Vector3 = normals[idx2] if normals.size() > idx2 else Vector3.UP
			tri.normals = [n0, n1, n2]
			
			tri.center = (tri.vertices[0] + tri.vertices[1] + tri.vertices[2]) / 3.0
			tri.area = SurfaceExtractor.triangle_area(tri.vertices)
			tri.distance_to_camera = 1.0
			triangles.append(tri)
			
	var config: SplatGenerator.SplatConfig = SplatGenerator.SplatConfig.new()
	config.splats_per_triangle = 3
	config.min_radius = 0.02
	config.max_radius = 0.3
	
	var gen_res: SplatGenerator.SplatGenerationResult = SplatGenerator.generate_splats_from_triangles(
		triangles,
		Vector3.ZERO,
		config,
		splat_density
	)
	
	loaded_splats = gen_res.splats
	has_ply_splats = true
	print("FoveaSplattable: Procedurally generated %d splats." % loaded_splats.size())
	_update_local_renderer()
	generation_completed.emit(loaded_splats.size())


class SplatSpatialHashGrid extends RefCounted:
	var cell_size: float
	var grid: Dictionary = {} # Vector3i -> Array[int]

	func _init(p_cell_size: float, splats: Array[GaussianSplat]) -> void:
		cell_size = p_cell_size
		for i in range(splats.size()):
			var pos: Vector3 = splats[i].position
			var cell: Vector3i = Vector3i(
				int(floor(pos.x / cell_size)),
				int(floor(pos.y / cell_size)),
				int(floor(pos.z / cell_size))
			)
			if not grid.has(cell):
				grid[cell] = []
			grid[cell].append(i)

	func get_indices_in_radius(center: Vector3, radius: float) -> Array[int]:
		var results: Array[int] = []
		var min_cell: Vector3i = Vector3i(
			int(floor((center.x - radius) / cell_size)),
			int(floor((center.y - radius) / cell_size)),
			int(floor((center.z - radius) / cell_size))
		)
		var max_cell: Vector3i = Vector3i(
			int(floor((center.x + radius) / cell_size)),
			int(floor((center.y + radius) / cell_size)),
			int(floor((center.z + radius) / cell_size))
		)
		for x in range(min_cell.x, max_cell.x + 1):
			for y in range(min_cell.y, max_cell.y + 1):
				for z in range(min_cell.z, max_cell.z + 1):
					var cell: Vector3i = Vector3i(x, y, z)
					if grid.has(cell):
						results.append_array(grid[cell])
		return results
