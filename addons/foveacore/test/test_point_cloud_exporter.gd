extends SceneTree

## Unit tests for FoveaPointCloudExporter
## Validates filtering, downsampling, and exporting (both ASCII and Binary PLY formats).

const FoveaPointCloudExporterScript := preload("res://addons/foveacore/scripts/advanced/fovea_point_cloud_exporter.gd")
const GaussianSplatScript := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

var _passed := 0
var _failed := 0

signal all_complete(passed: int, failed: int)

func _init() -> void:
	print("\n" + "─".repeat(70))
	print("FoveaPointCloudExporter Unit Tests")
	print("─".repeat(70))

	await create_timer(0.2).timeout
	_run_all()

func _run_all() -> void:
	_test_point_filtering_and_export()
	
	print("\n" + "─".repeat(70))
	print("PointCloudExporter Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("─".repeat(70))
	all_complete.emit(_passed, _failed)
	
	if _failed > 0:
		quit(1)
	else:
		quit(0)

func _test_point_filtering_and_export() -> void:
	print("\n--- _test_point_filtering_and_export ---")
	
	# 1. Create dummy splats
	# We will create 100 splats. Some will be noisy floaters, some will be low opacity, some will be large scale.
	var splats: Array[GaussianSplat] = []
	
	# Group A: 50 good core splats (close to center, high opacity, small scale)
	for i in range(50):
		var pos = Vector3(
			sin(i * 0.5) * 0.2,
			cos(i * 0.5) * 0.2,
			float(i) * 0.01
		)
		var s = GaussianSplatScript.new(pos)
		s.opacity = 0.8
		s.scale = Vector3(0.01, 0.01, 0.01)
		s.color = Color(1.0, 0.0, 0.0) # Red
		splats.append(s)
		
	# Group B: 10 low-opacity splats (should be filtered out)
	for i in range(10):
		var s = GaussianSplatScript.new(Vector3(2.0, 2.0, 2.0))
		s.opacity = 0.05
		s.scale = Vector3(0.01, 0.01, 0.01)
		s.color = Color(0.0, 1.0, 0.0) # Green
		splats.append(s)
		
	# Group C: 10 large-scale splats (should be filtered out)
	for i in range(10):
		var s = GaussianSplatScript.new(Vector3(-2.0, -2.0, -2.0))
		s.opacity = 0.9
		s.scale = Vector3(0.2, 0.2, 0.2)
		s.color = Color(0.0, 0.0, 1.0) # Blue
		splats.append(s)
		
	# Group D: 3 isolated floaters (should be filtered out by neighborhood check)
	# They have normal opacity/scale but are located far away from any other points
	var floaters_pos = [Vector3(10.0, 0.0, 0.0), Vector3(0.0, 10.0, 0.0), Vector3(0.0, 0.0, 10.0)]
	for pos in floaters_pos:
		var s = GaussianSplatScript.new(pos)
		s.opacity = 0.8
		s.scale = Vector3(0.01, 0.01, 0.01)
		s.color = Color(1.0, 1.0, 1.0) # White
		splats.append(s)
		
	_assert("Splats setup", splats.size() == 73, "Generated 73 initial splats")

	# 2. Configure exporter
	var config = FoveaPointCloudExporterScript.ExportConfig.new()
	config.min_opacity = 0.15
	config.max_scale = 0.05
	config.target_points_count = 30 # Request downsampling to 30 points
	config.filter_isolated_floaters = true
	config.floater_radius = 1.0
	config.floater_min_neighbors = 2 # Need at least 2 neighbors within 1.0m
	config.use_binary = false # Let's test ASCII first so we can parse it easily
	
	# 3. Test ASCII Export
	var ascii_path := "user://test_pc_export_ascii.ply"
	var success_ascii = FoveaPointCloudExporterScript.export_splats_to_ply(splats, ascii_path, config)
	_assert("ASCII export success", success_ascii, "export_splats_to_ply returned true")
	_assert("ASCII file exists", FileAccess.file_exists(ascii_path), "File was written to user://")
	
	# Verify contents of ASCII file
	if FileAccess.file_exists(ascii_path):
		var file = FileAccess.open(ascii_path, FileAccess.READ)
		var lines: Array[String] = []
		while not file.eof_reached():
			var line = file.get_line().strip_edges()
			if not line.is_empty():
				lines.append(line)
		file.close()
		
		# Validate header
		_assert("ASCII header signature", lines[0] == "ply", "Header starts with 'ply'")
		_assert("ASCII header format", lines[1] == "format ascii 1.0", "Format is ascii")
		
		# Find vertex count line
		var vertex_line := ""
		for line in lines:
			if line.begins_with("element vertex"):
				vertex_line = line
				break
		
		# Expected count should be min(filtered, target) -> we had 50 good points, requested 30, so 30.
		# Good points are Group A (50 points). Group B, C, D are filtered.
		# So target points count of 30 should be met.
		_assert("ASCII vertex count matches target", vertex_line == "element vertex 30", "Vertex line: " + vertex_line)
		
		# Make sure there are no green or blue colors in the exported points (as they should be filtered)
		var filtered_correctly := true
		var data_start := false
		var data_lines_count := 0
		for line in lines:
			if line == "end_header":
				data_start = true
				continue
			if data_start:
				data_lines_count += 1
				var parts = line.split(" ")
				if parts.size() >= 7:
					var r = parts[4].to_int()
					var g = parts[5].to_int()
					var b = parts[6].to_int()
					# Good points (Group A) are red (255, 0, 0). Filtered Group B is green, Group C is blue, Group D is white.
					# So g and b should be 0.
					if g != 0 or b != 0:
						filtered_correctly = false
						
		_assert("Data lines count matches vertex element", data_lines_count == 30, "Found %d data lines" % data_lines_count)
		_assert("Filtering applied correctly (no green/blue/white points)", filtered_correctly, "All exported points are from Group A (Red)")

	# 4. Test Binary Export
	config.use_binary = true
	var binary_path := "user://test_pc_export_binary.ply"
	var success_binary = FoveaPointCloudExporterScript.export_splats_to_ply(splats, binary_path, config)
	_assert("Binary export success", success_binary, "export_splats_to_ply returned true")
	_assert("Binary file exists", FileAccess.file_exists(binary_path), "Binary file written to user://")
	
	if FileAccess.file_exists(binary_path):
		var file = FileAccess.open(binary_path, FileAccess.READ)
		var is_binary_format = false
		for i in range(20):
			var line = file.get_line().strip_edges()
			if line == "format binary_little_endian 1.0":
				is_binary_format = true
				break
			if line == "end_header":
				break
		file.close()
		_assert("Binary format header correct", is_binary_format, "Header declares binary format")

	# Clean up
	var dir = DirAccess.open("user://")
	if dir:
		if dir.file_exists("test_pc_export_ascii.ply"):
			dir.remove("test_pc_export_ascii.ply")
		if dir.file_exists("test_pc_export_binary.ply"):
			dir.remove("test_pc_export_binary.ply")

func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_pass(name if detail.is_empty() else "%s — %s" % [name, detail])
	else:
		_fail(name, detail)

func _pass(detail: String) -> void:
	_passed += 1
	print("  ✓ %s" % detail)

func _fail(test_name: String, err: String) -> void:
	_failed += 1
	print("  ✗ %s — %s" % [test_name, err])
