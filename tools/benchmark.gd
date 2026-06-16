extends SceneTree

# tools/benchmark.gd — Integrated benchmark tool for FoveaEngine
# Measures FPS and frame times at 1k, 10k, and 100k splats.
# Generates a JSON report.

const FoveaCoreSplatRenderer = preload("res://addons/foveacore/scripts/advanced/fovea_core_splat_renderer.gd")
const FoveaStyle = preload("res://addons/foveacore/scripts/fovea_style.gd")

var _root_node: Node3D
var _camera: Camera3D
var _light: DirectionalLight3D
var _current_renderer: FoveaCoreSplatRenderer

var _counts := [1000, 10000, 100000]
var _results := {}

func _init() -> void:
	print("\n" + "======================================================================")
	print("🚀 STARTING FOVEAENGINE INTEGRATED BENCHMARK")
	print("======================================================================")
	
	await create_timer(0.2).timeout
	_run_benchmark()

func _run_benchmark() -> void:
	# Set up 3D environment
	_root_node = Node3D.new()
	root.add_child(_root_node)
	
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 5)
	_root_node.add_child(_camera)
	
	_light = DirectionalLight3D.new()
	_light.rotation_degrees = Vector3(-45, 45, 0)
	_root_node.add_child(_light)
	
	for count in _counts:
		print("\nBenchmarking with %d splats..." % count)
		_setup_splats(count)
		
		# Warm-up frames
		for i in range(10):
			await create_timer(0.016).timeout
			
		# Measurement loop
		var start_time = Time.get_ticks_usec()
		var frame_times := []
		
		var num_frames = 100
		for i in range(num_frames):
			var frame_start = Time.get_ticks_usec()
			await create_timer(0.016).timeout # Simulate physics/process
			var frame_end = Time.get_ticks_usec()
			frame_times.append((frame_end - frame_start) / 1000.0)
			
		var total_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
		var avg_frame_time = total_time_ms / num_frames
		var avg_fps = 1000.0 / avg_frame_time if avg_frame_time > 0 else 0.0
		
		print("  -> Avg Frame Time: %.2f ms" % avg_frame_time)
		print("  -> Avg FPS: %.1f" % avg_fps)
		
		_results[str(count)] = {
			"splat_count": count,
			"avg_frame_time_ms": avg_frame_time,
			"avg_fps": avg_fps,
			"total_time_ms": total_time_ms,
			"frames_rendered": num_frames
		}
		
		_cleanup_splats()
		
	_save_report()
	
	# Cleanup root
	_root_node.queue_free()
	quit(0)

func _setup_splats(count: int) -> void:
	_current_renderer = FoveaCoreSplatRenderer.new()
	_current_renderer.use_triangle_mesh = true
	_current_renderer.splat_subdivisions = 16
	
	# Create Multimesh
	var mesh = ArrayMesh.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(-0.1, -0.1, 0))
	st.add_vertex(Vector3(0.1, -0.1, 0))
	st.add_vertex(Vector3(0, 0.1, 0))
	mesh = st.commit()
	
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	
	for i in range(count):
		var pos = Vector3(
			randf() * 4.0 - 2.0,
			randf() * 4.0 - 2.0,
			randf() * 4.0 - 2.0
		)
		var transform = Transform3D(Basis(), pos)
		multimesh.set_instance_transform(i, transform)
		multimesh.set_instance_custom_data(i, Color(randf(), randf(), randf(), 1.0))
		
	_current_renderer.multimesh = multimesh
	_root_node.add_child(_current_renderer)

func _cleanup_splats() -> void:
	if _current_renderer and is_instance_valid(_current_renderer):
		_current_renderer.queue_free()
		_current_renderer = null

func _save_report() -> void:
	var report_data = {
		"timestamp": Time.get_datetime_string_from_system(),
		"engine": "FoveaEngine 🔷",
		"results": _results
	}
	
	var json_str = JSON.stringify(report_data, "  ")
	var file_path = "res://benchmark_report.json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("\n✅ Benchmark report saved to: ", ProjectSettings.globalize_path(file_path))
	else:
		push_error("Failed to write benchmark report.")
