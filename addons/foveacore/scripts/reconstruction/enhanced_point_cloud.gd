extends Node3D
class_name EnhancedPointCloudViewer

signal loading_started(total_points: int)
signal loading_progress(current: int, total: int)
signal loading_completed(point_count: int, load_time_ms: float)
signal render_mode_changed(mode: int)

enum RenderMode { DENSE, LOD, DENSITY_HEATMAP, NORMAL, DEPTH, OCCLUSION }

@export var point_size: float = 0.02
@export var max_points: int = 100000
@export var lod_distance: float = 5.0
@export var cull_distance: float = 20.0

var _render_mode: RenderMode = RenderMode.DENSE
var _points_data: Array[Dictionary] = []
var _load_time: float = 0.0
var _is_loaded: bool = false

@onready var _multi_mesh: MultiMeshInstance3D = MultiMeshInstance3D.new()
@onready var _camera: Camera3D = null

func _ready() -> void:
	add_child(_multi_mesh)
	_multi_mesh.name = "PointCloudMultiMesh"

func load_ply_async(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("EnhancedPointCloud: File not found: " + path)
		return
	
	loading_started.emit(max_points)
	
	var start_time = Time.get_ticks_msec()
	
	var thread = Thread.new()
	thread.start(_thread_load_ply.bind(path))
	
	while thread.is_alive():
		await get_tree().process_frame
	
	var result = thread.wait()
	_load_time = float(Time.get_ticks_msec() - start_time)
	
	_is_loaded = true
	loading_completed.emit(_points_data.size(), _load_time)

func _thread_load_ply(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	
	var header = _parse_ply_header(file)
	var count = min(header.get("vertex_count", 0), max_points)
	
	_points_data.clear()
	
	for i in range(count):
		if file.eof_reached():
			break
		
		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue
		
		var parts = line.split(" ")
		if parts.size() < 3:
			continue
		
		var pt = {
			"pos": Vector3(float(parts[0]), float(parts[1]), float(parts[2])),
			"color": Color.WHITE,
			"normal": Vector3.UP,
			"opacity": 1.0,
			"scale": 1.0
		}
		
		if header.get("has_color", false) and parts.size() >= 6:
			pt["color"] = Color(
				float(parts[3]) / 255.0,
				float(parts[4]) / 255.0,
				float(parts[5]) / 255.0
			)
		
		_points_data.append(pt)
		
		if i % 5000 == 0:
			loading_progress.emit(i, count)
	
	file.close()

func _parse_ply_header(file: FileAccess) -> Dictionary:
	var header = {"vertex_count": 0, "has_color": false, "has_normal": false}
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.begins_with("element vertex"):
			var parts = line.split(" ")
			if parts.size() >= 3:
				header["vertex_count"] = int(parts[2])
		if line.contains("property") and "red" in line:
			header["has_color"] = true
		if line.contains("property") and ("nx" in line or "nx" in line):
			header["has_normal"] = true
		if line == "end_header":
			break
	return header

func render() -> void:
	if _points_data.is_empty():
		return
	
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = _points_data.size()
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(point_size, point_size)
	
	var mat = _create_material()
	mesh.material = mat
	
	mm.mesh = mesh
	_multi_mesh.multimesh = mm
	
	for i in range(_points_data.size()):
		var pt = _points_data[i]
		var t = Transform3D(Basis(), pt["pos"])
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, pt["color"])
	
	print("EnhancedPointCloud: Rendered %d points" % _points_data.size())

func _create_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	
	match _render_mode:
		RenderMode.DENSE:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.vertex_color_use_as_albedo = true
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		RenderMode.LOD:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.vertex_color_use_as_albedo = true
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.point_size = 2
		RenderMode.DENSITY_HEATMAP:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(0, 1, 0)
			mat.emission_enabled = true
			mat.emission = Color(0, 1, 0)
		RenderMode.DEPTH:
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			mat.vertex_color_use_as_albedo = true
	
	return mat

func set_render_mode(mode: RenderMode) -> void:
	_render_mode = mode
	render_mode_changed.emit(mode)
	render()

func get_statistics() -> Dictionary:
	if _points_data.is_empty():
		return {}
	
	var min_pos = Vector3.INF
	var max_pos = -Vector3.INF
	var center = Vector3.ZERO
	var avg_color = Vector3.ZERO
	
	for pt in _points_data:
		min_pos = min_pos.min(pt["pos"])
		max_pos = max_pos.max(pt["pos"])
		center += pt["pos"]
		avg_color += Vector3(pt["color"].r, pt["color"].g, pt["color"].b)
	
	center /= _points_data.size()
	avg_color /= _points_data.size()
	
	return {
		"point_count": _points_data.size(),
		"bounds_min": min_pos,
		"bounds_max": max_pos,
		"center": center,
		"size": max_pos - min_pos,
		"avg_color": avg_color,
		"load_time_ms": _load_time
	}

func filter_by_bounds(bounds: AABB) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for pt in _points_data:
		if bounds.has_point(pt["pos"]):
			filtered.append(pt)
	return filtered

func filter_by_density(radius: float) -> Dictionary:
	var density_map = {}
	
	for pt in _points_data:
		var cell = Vector3i(
			int(pt["pos"].x / radius),
			int(pt["pos"].y / radius),
			int(pt["pos"].z / radius)
		)
		if not density_map.has(cell):
			density_map[cell] = 0
		density_map[cell] += 1
	
	var max_density = 0
	var min_density = 999999
	
	for count in density_map.values():
		max_density = max(max_density, count)
		min_density = min(min_density, count)
	
	return {
		"density_map": density_map,
		"max_density": max_density,
		"min_density": min_density,
		"average_density": float(density_map.size()) / max(_points_data.size(), 1)
	}

func export_to_loded(path: String, levels: int = 3) -> void:
	if _points_data.is_empty():
		return
	
	var levels_data = []
	var current_radius = 0.5
	
	for lvl in range(levels):
		var level_points = []
		for pt in _points_data:
			if (pt["pos"] - Vector3.ZERO).length() < cull_distance * pow(2, lvl):
				level_points.append(pt)
		levels_data.append({
			"level": lvl,
			"point_count": level_points.size(),
			"radius": current_radius,
			"points": level_points
		})
		current_radius *= 2.0
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(levels_data, "\t"))
	file.close()