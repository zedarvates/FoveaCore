extends MultiMeshInstance3D
class_name SplatRenderer
## SplatRenderer — Rendu haute-performance des Gaussian Splats
## Utilise MultiMeshInstance3D pour afficher des milliers de splats en VR à 90 FPS
## Chaque instance représente un gaussien avec position, rotation, échelle et couleur

# GaussianSplat is a global class_name

signal render_updated(instance_count: int)
signal sorting_completed(elapsed_ms: float)
signal memory_usage_reported(bytes: int)

@export var point_size: float = 0.05
@export var max_instances: int = 1000000
@export var enable_sorting: bool = true
@export var sort_distance_threshold: float = 0.1
@export var debug_show_bounds: bool = false
@export var enable_anisotropic: bool = true
@export var lod_enabled: bool = false
@export var lod_distance: float = 25.0
@export var lod_scale_multiplier: float = 1.5  # Make distant splats bigger

var _splats: Array[GaussianSplat] = []
var _multimesh: MultiMesh
var _camera: Camera3D = null
var _last_camera_pos: Vector3 = Vector3.ZERO
var _sort_dirty: bool = false
var _render_distance: float = 50.0
var _stats: Dictionary = {}
var _sorter = null  # GPU sorter (SplatSorter from reconstruction)

func _ready() -> void:
	name = "SplatRenderer"
	_setup_multimesh()
	# Auto-detecter la caméra principale
	_camera = get_viewport().get_camera_3d() if get_viewport() else null
	# Initialiser le GPU sorter (si disponible)
	_init_sorter()

func _init_sorter() -> void:
	if _sorter == null:
		var SorterScript = preload("res://addons/foveacore/scripts/reconstruction/splat_sorter.gd")
		_sorter = SorterScript.new()
		# Vérifier la disponibilité GPU
		if not _sorter.is_gpu_available():
			print("SplatRenderer: GPU sorter not available, using CPU sort fallback")
			_sorter = null

func _setup_multimesh() -> void:
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = false  # On utilise pas custom_data, on stocke tout dans transform
	_multimesh.instance_count = 0

	# Mesh : un simple quad qui serabillboardisé
	var mesh = QuadMesh.new()
	mesh.size = Vector2(point_size, point_size)

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # Les splats sont vus des deux côtés
	mesh.material = mat

	_multimesh.mesh = mesh
	self.multimesh = _multimesh

func load_splats(splats: Array[GaussianSplat]) -> void:
	"""Charge un tableau de ReconstructionGaussianSplat et prepare le rendu."""
	_splats = splats.duplicate()
	var count = min(_splats.size(), max_instances)

	if _multimesh == null:
		_setup_multimesh()
	_multimesh.instance_count = count

	var cam_pos = _camera.global_position if _camera else Vector3.ZERO
	for i in range(count):
		var splat = _splats[i]
		var transform = _splat_to_transform(splat, cam_pos)
		_multimesh.set_instance_transform(i, transform)
		_multimesh.set_instance_color(i, splat.color)

	_sort_dirty = true
	_last_camera_pos = cam_pos

	render_updated.emit(count)
	_report_memory_usage()

func update_splats(splats: Array[GaussianSplat]) -> void:
	"""Met à jour les splats (remplacement complet)."""
	load_splats(splats)

func render_splats(splats: Array[GaussianSplat]) -> int:
	"""Alias pour update_splats compatible avec FoveaCoreManager, retourne le nombre de splats."""
	update_splats(splats)
	return splats.size()

func _splat_to_transform(splat: GaussianSplat, camera_pos: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis = Basis.IDENTITY
	var translation = splat.position

	var scale_x: float
	var scale_y: float

	if enable_anisotropic:
		scale_x = splat.scale.x * 2.0 * point_size
		scale_y = splat.scale.y * 2.0 * point_size
	else:
		var avg_scale = (splat.scale.x + splat.scale.y + splat.scale.z) / 3.0
		scale_x = avg_scale * 2.0 * point_size
		scale_y = avg_scale * 2.0 * point_size

	# Apply LOD scaling if enabled and camera provided
	if lod_enabled and camera_pos != Vector3.ZERO:
		var dist = translation.distance_to(camera_pos)
		if dist > lod_distance:
			var factor = lod_scale_multiplier
			scale_x *= factor
			scale_y *= factor

	var scale_vec = Vector3(scale_x, scale_y, 1.0)

	if splat.rotation != Quaternion.IDENTITY:
		basis = Basis(splat.rotation)

	basis = basis.scaled(scale_vec)
	return Transform3D(basis, translation)

func _process(_delta: float) -> void:
	if enable_sorting and _camera and _sort_dirty:
		_sort_by_camera_distance()
		_sort_dirty = false

	# Vérifier si la caméra a bougé suffisamment pour nécessiter un nouveau tri
	if _camera:
		var cam_pos = _camera.global_position
		if (cam_pos - _last_camera_pos).length() > sort_distance_threshold:
			_sort_dirty = true
			_last_camera_pos = cam_pos

func _sort_by_camera_distance() -> void:
	"""Trie les instances par distance caméra (back-to-front) pour transparence correcte."""
	if _splats.is_empty() or not _camera:
		return

	var start_time = Time.get_ticks_msec()

	# Utiliser le GPU sorter si disponible
	var sorted_indices: Array[int] = []
	if _sorter and _sorter.is_gpu_available() and _splats.size() <= _sorter.get_max_supported_splats():
		sorted_indices = _sorter.sort_splats_back_to_front(_splats, _camera)
	else:
		# Fallback CPU
		sorted_indices = _cpu_sort_by_distance(_camera.global_position)

	# Réorganiser les transformations dans le MultiMesh selon le nouvel ordre
	# (évite readback GPU, on recalcule à partir des splats)
	for i in range(sorted_indices.size()):
		var splat = _splats[sorted_indices[i]]
		var cam_pos = _camera.global_position if _camera else Vector3.ZERO
		_multimesh.set_instance_transform(i, _splat_to_transform(splat, cam_pos))
		_multimesh.set_instance_color(i, splat.color)

	var elapsed = Time.get_ticks_msec() - start_time
	sorting_completed.emit(elapsed)
	print("SplatRenderer: Sorted %d splats in %d ms (%s)" % [
		_splats.size(),
		elapsed,
		"GPU" if _sorter and _sorter.is_gpu_available() else "CPU"
	])

func _cpu_sort_by_distance(cam_pos: Vector3) -> Array[int]:
	"""Tri CPU des indices par distance décroissante."""
	var indexed: Array[Dictionary] = []
	for i in range(_splats.size()):
		var dist = _splats[i].position.distance_to(cam_pos)
		indexed.append({"idx": i, "dist": dist})

	indexed.sort_custom(_compare_splat_distance)

	var sorted: Array[int] = []
	for item in indexed:
		sorted.append(item["idx"])
	return sorted


func _compare_splat_distance(a: Dictionary, b: Dictionary) -> bool:
	"""Fonction de comparaison pour le tri (nécessaire car Godot ne supporte pas les lambdas inline dans sort_custom)."""
	return a["dist"] > b["dist"]

func set_camera(cam: Camera3D) -> void:
	"""Définit manuellement la caméra pour le tri."""
	_camera = cam
	_sort_dirty = true

func mark_sort_dirty() -> void:
	"""Marque le tri comme nécessaire (appeler après déformation des splats)."""
	_sort_dirty = true

func get_statistics() -> Dictionary:
	var stats = {
		"total_splats": _splats.size(),
		"visible_instances": _multimesh.instance_count,
		"sorting_enabled": enable_sorting,
		"sort_dirty": _sort_dirty,
		"point_size": point_size,
		"camera_linked": _camera != null
	}

	# Comput bounding box
	if not _splats.is_empty():
		var min_pos = Vector3(INF, INF, INF)
		var max_pos = Vector3(-INF, -INF, -INF)
		var avg_scale = 0.0

		for splat in _splats:
			min_pos = min_pos.min(splat.position)
			max_pos = max_pos.max(splat.position)
			avg_scale += (splat.scale.x + splat.scale.y + splat.scale.z) / 3.0

		stats["bounds_min"] = min_pos
		stats["bounds_max"] = max_pos
		stats["bounds_size"] = max_pos - min_pos
		stats["avg_scale"] = avg_scale / _splats.size()

	return stats

func _report_memory_usage() -> void:
	var bytes = 0
	# Estimation mémoire :
	# - Array[ReconstructionGaussianSplat]: ~48 bytes per element (Vector3*2 + Quat + Color + 2 floats)
	bytes += _splats.size() * 64
	# - MultiMesh internal buffer: transform (32 bytes) + color (16 bytes) per instance
	bytes += _multimesh.instance_count * 48
	memory_usage_reported.emit(bytes)

func set_point_size(size: float) -> void:
	point_size = size
	if _multimesh and _multimesh.mesh:
		var mesh = _multimesh.mesh as QuadMesh
		if mesh:
			mesh.size = Vector2(point_size, point_size)
	# Re-apply transforms to scale with new point_size
	if not _splats.is_empty():
		refresh()

func set_render_distance(distance: float) -> void:
	_render_distance = distance
	# MultiMesh does not support per-instance visibility natively.
	# To enforce render distance, rebuild the multimesh with only visible instances
	# via rebuild_visible_only() or implement LOD in the compute shader.

func refresh() -> void:
	"""Reconstruit complètement le rendu (appeler après changement massif)."""
	if not _splats.is_empty():
		load_splats(_splats)

func export_to_ply(path: String) -> Error:
	"""Exporte les splats actuels vers un fichier PLY binaire (format 3DGS)."""
	if _splats.is_empty():
		push_error("SplatRenderer: No splats to export")
		return ERR_INVALID_DATA

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SplatRenderer: Cannot open file for writing: " + path)
		return FAILED

	# Écrire l'en-tête PLY (format ASCII puis données binaires)
	file.store_string("ply\n")
	file.store_string("format binary_little_endian 1.0\n")
	file.store_string("element vertex %d\n" % _splats.size())
	file.store_string("property float x\n")
	file.store_string("property float y\n")
	file.store_string("property float z\n")
	file.store_string("property float nx\n")
	file.store_string("property float ny\n")
	file.store_string("property float nz\n")
	# On peut ajouter f_dc, scale, opacity, rot selon le format cible
	file.store_string("property float f_dc_0\n")
	file.store_string("property float f_dc_1\n")
	file.store_string("property float f_dc_2\n")
	file.store_string("property float opacity\n")
	file.store_string("property float scale_0\n")
	file.store_string("property float scale_1\n")
	file.store_string("property float scale_2\n")
	file.store_string("property float rot_0\n")
	file.store_string("property float rot_1\n")
	file.store_string("property float rot_2\n")
	file.store_string("property float rot_3\n")
	file.store_string("end_header\n")

	# Écrire les données binaires pour chaque splat
	for splat in _splats:
		# position
		file.store_float(splat.position.x)
		file.store_float(splat.position.y)
		file.store_float(splat.position.z)
		# normals (estimées à l'up pour l'instant)
		file.store_float(0.0); file.store_float(1.0); file.store_float(0.0)
		# f_dc (SH degree-0) from color
		var r = splat.color.r
		var g = splat.color.g
		var b = splat.color.b
		# Inverser la conversion SH: f_dc = (color - 0.5) / 0.28209
		var f_dc_0 = (r - 0.5) / 0.28209
		var f_dc_1 = (g - 0.5) / 0.28209
		var f_dc_2 = (b - 0.5) / 0.28209
		file.store_float(f_dc_0)
		file.store_float(f_dc_1)
		file.store_float(f_dc_2)
		# opacity (sigmoid inverse)
		var logit = -log(1.0 / splat.opacity - 1.0)
		file.store_float(logit)
		# scale (log)
		file.store_float(log(splat.scale.x))
		file.store_float(log(splat.scale.y))
		file.store_float(log(splat.scale.z))
		# rotation (quaternion)
		file.store_float(splat.rotation.x)
		file.store_float(splat.rotation.y)
		file.store_float(splat.rotation.z)
		file.store_float(splat.rotation.w)

	file.close()
	print("SplatRenderer: Exported %d splats to %s" % [_splats.size(), path])
	return OK
