extends Node
class_name FloatersDetector

signal cleaning_started(total_floating: int)
signal cleaning_progress_updated(current: int, total: int)
signal cleaning_completed(removed_count: int)
signal cleaning_failed(reason: String)

@export var min_isolated_distance: float = 0.1
@export var min_opacity_threshold: float = 0.01
@export var max_splat_size: float = 0.05
@export var auto_clean_on_load: bool = false

var _splats_data: Array = []
var _floating_indices: Array = []
var _workspace_path: String = ""

func _ready() -> void:
	print("FloatersDetector: Initialisé")

func analyze_workspace(workspace_dir: String) -> Dictionary:
	_workspace_path = workspace_dir
	_splats_data.clear()
	_floating_indices.clear()
	
	var splat_file_path = workspace_dir + "/point_cloud/points.ply"
	if not FileAccess.file_exists(splat_file_path):
		splat_file_path = workspace_dir + "/splats.ply"
	
	if not FileAccess.file_exists(splat_file_path):
		push_error("FloatersDetector: Fichier splats introuvable: " + splat_file_path)
		return {}
	
	_splats_data = _parse_ply_splats(splat_file_path)
	if _splats_data.is_empty():
		push_error("FloatersDetector: Impossible de parser les splats")
		return {}
	
	_floating_indices = _detect_floating_splats()
	
	var result = {
		"total_splats": _splats_data.size(),
		"floating_count": _floating_indices.size(),
		"floating_percentage": float(_floating_indices.size()) / float(_splats_data.size()) * 100.0,
		"floating_indices": _floating_indices.duplicate()
	}
	
	print("FloatersDetector: Analyse terminee - %d/%d floaters detectes (%f%%)" % 
		[_floating_indices.size(), _splats_data.size(), result["floating_percentage"]])
	
	return result

func _parse_ply_splats(file_path: String) -> Array:
	var splats: Array = []
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("FloatersDetector: Cannot open file: " + file_path)
		return splats
	
	var header_found = false
	var vertex_count = 0
	var properties: Array = []

	var file_error = file.get_error()
	if file_error != OK:
		push_error("FloatersDetector: File error: " + str(file_error))
		file.close()
		return splats
	
	while file.get_position() < file.get_length():
		var line = file.get_line().strip_edges()
		if line.begins_with("end_header"):
			header_found = true
			break
		elif line.begins_with("element vertex"):
			vertex_count = int(line.split(" ")[2])
		elif line.begins_with("property"):
			properties.append(line)
	
	if not header_found or vertex_count == 0:
		file.close()
		return splats
	
	var x_idx = properties.find("property float x")
	var y_idx = properties.find("property float y")
	var z_idx = properties.find("property float z")
	var nx_idx = properties.find("property float nx")
	var ny_idx = properties.find("property float ny")
	var nz_idx = properties.find("property float nz")
	var scale_idx = properties.find("property float scale_0")
	var opacity_idx = properties.find("property float opacity")
	var color_idx = properties.find("property float red")
	
	for i in range(vertex_count):
		if file.get_position() >= file.get_length():
			break
		var parts = file.get_line().split(" ")
		if parts.size() < 3:
			continue
		
		var splat: Dictionary = {
			"index": i,
			"pos": Vector3.ZERO,
			"normal": Vector3.UP,
			"scale": 0.01,
			"opacity": 1.0,
			"color": Color.WHITE
		}
		
		if x_idx >= 0 and y_idx >= 0 and z_idx >= 0:
			splat["pos"] = Vector3(float(parts[x_idx]), float(parts[y_idx]), float(parts[z_idx]))
		
		if nx_idx >= 0 and ny_idx >= 0 and nz_idx >= 0:
			splat["normal"] = Vector3(float(parts[nx_idx]), float(parts[ny_idx]), float(parts[nz_idx]))
		
		if scale_idx >= 0 and scale_idx < parts.size():
			splat["scale"] = float(parts[scale_idx])
		
		if opacity_idx >= 0 and opacity_idx < parts.size():
			splat["opacity"] = float(parts[opacity_idx])
		
		if color_idx >= 0 and color_idx + 2 < parts.size():
			splat["color"] = Color(
				float(parts[color_idx]) / 255.0,
				float(parts[color_idx + 1]) / 255.0,
				float(parts[color_idx + 2]) / 255.0
			)
		
		splats.append(splat)
	
	file.close()
	return splats

func _detect_floating_splats() -> Array:
	var floating: Array = []
	var splat_count = _splats_data.size()

	if splat_count == 0:
		return floating

	# Parallel detection using threads
	var num_threads = max(1, OS.get_processor_count() - 1)
	var chunk_size = max(1, splat_count / num_threads)
	var threads: Array[Thread] = []
	var mutex = Mutex.new()
	var results: Array[Array] = []
	results.resize(num_threads)

	for t in range(num_threads):
		results[t] = []
		var thread = Thread.new()
		thread.start(_detect_chunk.bind(
			t,
			t * chunk_size,
			min((t + 1) * chunk_size, splat_count),
			_splats_data,
			min_isolated_distance,
			min_opacity_threshold,
			max_splat_size,
			results,
			mutex
		))
		threads.append(thread)

	# Wait all threads
	for thread in threads:
		thread.wait_to_finish()

	# Collect results
	for t_results in results:
		floating.append_array(t_results)

	return floating

func _detect_chunk(thread_id: int, start: int, end: int, splats_data: Array, min_dist: float, min_opacity: float, max_size: float, results: Array, mutex: Mutex) -> void:
	var local_floating: Array = []
	for i in range(start, end):
		var splat = splats_data[i]

		# Check opacity
		if splat["opacity"] < min_opacity:
			local_floating.append(i)
			continue

		# Check scale
		if splat["scale"] > max_size:
			local_floating.append(i)
			continue

		# Check neighbors (needs KD-Tree, done sequentially for now)
		# TODO: Move KD-Tree query outside or use spatial hash
		# For now, skip neighbor check in parallel mode to avoid race conditions
		# We'll do a second pass sequentially if needed

	# Append to shared results array atomically
	mutex.lock()
	results[thread_id] = local_floating
	mutex.unlock()

func _build_kd_tree() -> Object:
	var tree = KD_Tree.new()
	for i in range(_splats_data.size()):
		tree.insert_point(_splats_data[i]["pos"], i)
	return tree

func _find_nearest_neighbors(kd_tree: Object, pos: Vector3, radius: float) -> Array:
	return kd_tree.find_in_radius(pos, radius)

func remove_floating_splats(target_directory: String) -> bool:
	if _floating_indices.is_empty():
		print("FloatersDetector: Aucun floaters a supprimer")
		return true
	
	cleaning_started.emit(_floating_indices.size())
	
	var input_path = _workspace_path + "/point_cloud/points.ply"
	if not FileAccess.file_exists(input_path):
		input_path = _workspace_path + "/splats.ply"
	
	var output_path = target_directory + "/splats_cleaned.ply"
	
	var input_file = FileAccess.open(input_path, FileAccess.READ)
	if not input_file:
		cleaning_failed.emit("Impossible d'ouvrir le fichier source")
		return false
	
	var header_end_pos = _find_header_end(input_file)
	input_file.seek(header_end_pos)
	
	var output_file = FileAccess.open(output_path, FileAccess.WRITE)
	if not output_file:
		cleaning_failed.emit("Impossible de creer le fichier de sortie")
		return false
	
	var header = _read_header(input_file)
	header = header.replace("element vertex " + str(_splats_data.size()), "element vertex " + str(_splats_data.size() - _floating_indices.size()))
	output_file.store_string(header)
	
	var line_idx = 0
	var removed_count = 0
	var floating_set = {}
	for idx in _floating_indices:
		floating_set[idx] = true
	
	while input_file.get_position() < input_file.get_length():
		if _floating_indices.has(line_idx):
			input_file.get_line()
			line_idx += 1
			removed_count += 1
			cleaning_progress_updated.emit(removed_count, _floating_indices.size())
			continue
		
		var line = input_file.get_line()
		output_file.store_line(line)
		line_idx += 1
	
	input_file.close()
	output_file.close()
	
	cleaning_completed.emit(_floating_indices.size())
	print("FloatersDetector: %d splats supprimes" % removed_count)
	return true

func _find_header_end(file: FileAccess) -> int:
	var pos = 0
	while file.get_position() < file.get_length():
		var line = file.get_line()
		if line.strip_edges().begins_with("end_header"):
			return file.get_position()
		pos = file.get_position()
	return pos

func _read_header(file: FileAccess) -> String:
	file.seek(0)
	var header_lines: Array = []
	while file.get_position() < file.get_length():
		var line = file.get_line()
		header_lines.append(line)
		if line.strip_edges().begins_with("end_header"):
			break
	var full_header = ""
	for l in header_lines:
		full_header += l + "\n"
	return full_header

func get_floating_report() -> String:
	if _floating_indices.is_empty():
		return "Aucun artifact flottant detecte."
	
	var report = "=== Floaters Detection Report ===\n"
	report += "Total splats: %d\n" % _splats_data.size()
	report += "Floating artifacts: %d (%f%%)\n" % [_floating_indices.size(), float(_floating_indices.size()) / float(_splats_data.size()) * 100.0]
	report += "Seuil d'isolement: %f\n" % min_isolated_distance
	report += "Seuil d'opacite: %f\n" % min_opacity_threshold
	report += "=============================="
	return report


class KD_Tree:
	var _points: Array = []
	var _indices: Array = []
	
	func insert_point(pos: Vector3, idx: int) -> void:
		_points.append(pos)
		_indices.append(idx)
	
	func find_in_radius(pos: Vector3, radius: float) -> Array:
		var results: Array = []
		for i in range(_points.size()):
			if pos.distance_to(_points[i]) <= radius:
				results.append(_indices[i])
		return results