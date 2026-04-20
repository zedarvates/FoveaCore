extends Node
class_name ChunkedPointCloudLoader

signal chunk_loading_started()
signal chunk_loaded(chunk_index: int, points_loaded: int, total_points: int)
signal chunking_complete(total_chunks: int)
signal loading_cancelled()

var chunk_size: int = 10000
var max_concurrent_loads: int = 2
var preloading_enabled: bool = true
var preloading_distance: float = 5.0

var _file_path: String = ""
var _total_points: int = 0
var _total_chunks: int = 0
var _header_info: Dictionary = {}
var _chunk_boundaries: Array[Dictionary] = []
var _loaded_chunks: Array[int] = []
var _is_loading: bool = false
var _should_cancel: bool = false

@onready var _spatial_hash: SpatialHashGrid = null

func _ready() -> void:
	_spatial_hash = SpatialHashGrid.new(1.0)

func start_loading(path: String) -> void:
	if _is_loading:
		return
	
	_file_path = path
	_is_loading = true
	_should_cancel = false
	
	if not FileAccess.file_exists(path):
		push_error("ChunkedLoader: File not found: " + path)
		_is_loading = false
		return
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		_is_loading = false
		return
	
	_header_info = _parse_header(file)
	_total_points = _header_info.get("vertex_count", 0)
	_total_chunks = ceil(float(_total_points) / chunk_size)
	
	_calculate_chunk_boundaries()
	
	file.close()
	
	chunk_loading_started.emit()
	chunking_complete.emit(_total_chunks)
	
	_load_chunks_in_range(Vector3.ZERO)

func _parse_header(file: FileAccess) -> Dictionary:
	var header = {"vertex_count": 0, "has_color": false, "has_normal": false}
	
	while not file.eof_reached():
		var line = file.get_line().strip_edges()
		if line.begins_with("element vertex"):
			var parts = line.split(" ")
			if parts.size() >= 3:
				header["vertex_count"] = int(parts[2])
		if line.contains("property") and "red" in line:
			header["has_color"] = true
		if line.contains("property") and "normal" in line:
			header["has_normal"] = true
		if line == "end_header":
			break
	
	return header

func _calculate_chunk_boundaries() -> void:
	_chunk_boundaries.clear()
	
	var header_end = _find_header_end()
	var bytes_per_line = 50
	var data_start = header_end
	
	for i in range(_total_chunks):
		var start_point = i * chunk_size
		var end_point = min((i + 1) * chunk_size - 1, _total_points - 1)
		
		_chunk_boundaries.append({
			"index": i,
			"start_line": start_point,
			"end_line": end_point,
			"point_count": end_point - start_point + 1,
			"byte_offset": data_start + start_point * bytes_per_line
		})

func _find_header_end() -> int:
	var file = FileAccess.open(_file_path, FileAccess.READ)
	if not file:
		return 0
	
	var pos = 0
	while file.get_position() < file.get_length():
		var line = file.get_line()
		if line.strip_edges().begins_with("end_header"):
			pos = file.get_position()
			break
		pos = file.get_position()
	
	file.close()
	return pos

func _load_chunks_in_range(center: Vector3) -> void:
	if not _is_loading or _should_cancel:
		return
	
	var chunks_to_load = _get_chunks_in_range(center, preloading_distance)
	var newly_needed: Array[int] = []
	
	for idx in chunks_to_load:
		if not _loaded_chunks.has(idx):
			newly_needed.append(idx)
	
	newly_needed.resize(min(newly_needed.size(), max_concurrent_loads))
	
	for chunk_idx in newly_needed:
		_load_chunk(chunk_idx)
		_loaded_chunks.append(chunk_idx)
		chunk_loaded.emit(chunk_idx, _loaded_chunks.size(), _total_chunks)
	
	if _loaded_chunks.size() >= _total_chunks:
		_is_loading = false

func _load_chunk(chunk_index: int) -> void:
	if chunk_index < 0 or chunk_index >= _chunk_boundaries.size():
		return
	
	var boundary = _chunk_boundaries[chunk_index]
	var file = FileAccess.open(_file_path, FileAccess.READ)
	
	if not file:
		return
	
	var header_end = _find_header_end()
	file.seek(header_end)
	
	var current_line = 0
	var loaded_count = 0
	
	while not file.eof_reached() and loaded_count < boundary["point_count"]:
		var line = file.get_line().strip_edges()
		if line.is_empty():
			continue
		
		if current_line >= boundary["start_line"]:
			var parts = line.split(" ")
			if parts.size() >= 3:
				var pos = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
				var data = {"index": current_line}
				
				if _header_info.get("has_color", false) and parts.size() >= 6:
					data["color"] = Color(
						float(parts[3]) / 255.0,
						float(parts[4]) / 255.0,
						float(parts[5]) / 255.0
					)
				
				_spatial_hash.insert_point(pos, data)
				loaded_count += 1
		
		current_line += 1
	
	file.close()

func _get_chunks_in_range(center: Vector3, distance: float) -> Array[int]:
	var result: Array[int] = []
	var center_key = _spatial_hash.get_cell_key(center)
	var cell_radius = ceil(distance / _spatial_hash.cell_size)
	
	for x in range(-cell_radius, cell_radius + 1):
		for y in range(-cell_radius, cell_radius + 1):
			for z in range(-cell_radius, cell_radius + 1):
				var key = center_key + Vector3i(x, y, z)
				var chunk_idx = _find_chunk_for_cell(key)
				if chunk_idx >= 0 and not result.has(chunk_idx):
					result.append(chunk_idx)
	
	return result

func _find_chunk_for_cell(cell_key: Vector3i) -> int:
	return (cell_key.x + cell_key.y * 10 + cell_key.z * 100) % _total_chunks

func cancel_loading() -> void:
	_should_cancel = true
	_is_loading = false
	loading_cancelled.emit()

func get_progress() -> float:
	if _total_chunks == 0:
		return 0.0
	return float(_loaded_chunks.size()) / float(_total_chunks)

func get_loaded_chunk_count() -> int:
	return _loaded_chunks.size()

func get_total_chunk_count() -> int:
	return _total_chunks

func force_load_all() -> void:
	for i in range(_total_chunks):
		if not _loaded_chunks.has(i):
			_load_chunk(i)
			_loaded_chunks.append(i)
	
	_is_loading = false