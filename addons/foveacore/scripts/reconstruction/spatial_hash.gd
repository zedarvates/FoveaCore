extends Node
class_name SpatialHashGrid

signal chunk_loaded(chunk_key: Vector3i)
signal chunk_unloaded(chunk_key: Vector3i)
signal all_chunks_loaded()

var cell_size: float = 1.0
var max_loaded_chunks: int = 64

var _chunks: Dictionary = {}
var _active_chunk_keys: Array[Vector3i] = []
var _point_buckets: Dictionary = {}

func _init(cell_size_val: float = 1.0) -> void:
	cell_size = cell_size_val

func get_cell_key(position: Vector3) -> Vector3i:
	return Vector3i(
		floor(position.x / cell_size),
		floor(position.y / cell_size),
		floor(position.z / cell_size)
	)

func insert_point(position: Vector3, data: Dictionary) -> void:
	var key = get_cell_key(position)
	
	if not _point_buckets.has(key):
		_point_buckets[key] = []
		_chunks[key] = {
			"center": position,
			"point_count": 0,
			"loaded": false
		}
	
	_point_buckets[key].append({
		"position": position,
		"data": data
	})
	_chunks[key]["point_count"] += 1

func get_points_in_radius(position: Vector3, radius: float) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var radius_sq = radius * radius
	var cell_radius = ceil(radius / cell_size)
	
	var center_key = get_cell_key(position)
	
	for x in range(-cell_radius, cell_radius + 1):
		for y in range(-cell_radius, cell_radius + 1):
			for z in range(-cell_radius, cell_radius + 1):
				var key = center_key + Vector3i(x, y, z)
				if _point_buckets.has(key):
					for pt in _point_buckets[key]:
						if pt["position"].distance_squared_to(position) <= radius_sq:
							results.append(pt)
	
	return results

func get_nearest_neighbors(position: Vector3, count: int) -> Array[Dictionary]:
	var all_points: Array[Dictionary] = []
	var cell_radius = ceil(cell_size)
	var center_key = get_cell_key(position)
	
	for x in range(-cell_radius, cell_radius + 1):
		for y in range(-cell_radius, cell_radius + 1):
			for z in range(-cell_radius, cell_radius + 1):
				var key = center_key + Vector3i(x, y, z)
				if _point_buckets.has(key):
					for pt in _point_buckets[key]:
						all_points.append(pt)
	
	all_points.sort_custom(func(a, b):
		return a["position"].distance_squared_to(position) < b["position"].distance_squared_to(position)
	)
	
	return all_points.slice(0, min(count, all_points.size()))

func update_loaded_chunks(camera_position: Vector3, view_distance: float) -> void:
	var center_key = get_cell_key(camera_position)
	var load_radius = ceil(view_distance / cell_size)
	
	var newly_loaded: Array[Vector3i] = []
	var to_unload: Array[Vector3i] = []
	
	for x in range(-load_radius, load_radius + 1):
		for y in range(-load_radius, load_radius + 1):
			for z in range(-load_radius, load_radius + 1):
				var key = center_key + Vector3i(x, y, z)
				if _chunks.has(key) and not _active_chunk_keys.has(key):
					newly_loaded.append(key)
				elif not _chunks.has(key):
					_chunks[key] = {"center": Vector3.ZERO, "point_count": 0, "loaded": false}
					newly_loaded.append(key)
	
	if _active_chunk_keys.size() > max_loaded_chunks:
		var to_remove = _active_chunk_keys.size() - max_loaded_chunks
		for i in range(to_remove):
			var key = _active_chunk_keys[i]
			_active_chunk_keys.remove_at(i)
			to_unload.append(key)
	
	for key in to_unload:
		if _chunks.has(key):
			_chunks[key]["loaded"] = false
			chunk_unloaded.emit(key)
	
	for key in newly_loaded:
		if _chunks.has(key):
			_chunks[key]["loaded"] = true
			if not _active_chunk_keys.has(key):
				_active_chunk_keys.append(key)
			chunk_loaded.emit(key)
	
	if newly_loaded.size() > 0:
		all_chunks_loaded.emit()

func get_chunk_info(key: Vector3i) -> Dictionary:
	if _chunks.has(key):
		return _chunks[key]
	return {}

func get_total_point_count() -> int:
	var count = 0
	for chunk in _chunks.values():
		count += chunk.get("point_count", 0)
	return count

func clear() -> void:
	_chunks.clear()
	_point_buckets.clear()
	_active_chunk_keys.clear()

func get_statistics() -> Dictionary:
	return {
		"total_chunks": _chunks.size(),
		"active_chunks": _active_chunk_keys.size(),
		"total_points": get_total_point_count(),
		"cell_size": cell_size,
		"memory_estimate_kb": get_total_point_count() * 64 / 1024
	}