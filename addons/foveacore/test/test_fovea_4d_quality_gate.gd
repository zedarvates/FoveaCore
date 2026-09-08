extends SceneTree

const WriterScript := preload("res://addons/foveacore/scripts/fovea_4d_writer.gd")
const LoaderScript := preload("res://addons/foveacore/scripts/fovea_4d_loader.gd")

const BASE_PATH: String = "res://test/fixtures/reference_3dgs.fovea"
const SIDECAR_PATH: String = "user://fovea4d_quality_gate.fovea4d"
const GRID_DIMS: Vector3i = Vector3i(8, 8, 8)
const KEYFRAME_COUNT: int = 16
const PROXY_FRAME_COUNT: int = 120
const SAMPLE_RATE_HZ: float = 16.0
const MAX_COMBINED_BYTES: int = 214 * 1024
const MAX_NORMALIZED_POSITION_RMSE: float = 0.001
const MAX_NORMALIZED_LOOP_RMSE: float = 0.000001
const MAX_CPU_MEDIAN_MS: float = 16.67

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	var fixture: Dictionary = _load_fixture_positions(BASE_PATH)
	_assert("8,000-splat base fixture loads", bool(fixture.get("ok", false)), str(fixture.get("error", "fixture load failed")))
	if not bool(fixture.get("ok", false)):
		_finish()
		return
	var positions: PackedVector3Array = fixture["positions"]
	var bounds: AABB = fixture["bounds"]
	_assert("base fixture has 8,000 splats", positions.size() == 8000, str(positions.size()))
	var diagonal: float = bounds.size.length()
	var keyframes: Array[PackedVector3Array] = _build_unique_keyframes(bounds, diagonal)
	var write_error: Error = WriterScript.write_sidecar(
		SIDECAR_PATH,
		BASE_PATH,
		GRID_DIMS,
		keyframes,
		SAMPLE_RATE_HZ,
		true,
		bounds
	)
	_assert("quality sidecar writes", write_error == OK, error_string(write_error))
	if write_error != OK:
		_finish()
		return

	var loaded: Dictionary = LoaderScript.load_sidecar(SIDECAR_PATH, BASE_PATH)
	_assert("quality sidecar reloads", bool(loaded.get("ok", false)), str(loaded.get("error", "reload failed")))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var field: Fovea4DMotionField = loaded.get("field")
	var combined_bytes: int = FileAccess.get_file_as_bytes(BASE_PATH).size() + FileAccess.get_file_as_bytes(SIDECAR_PATH).size()
	var cache_started_usec: int = Time.get_ticks_usec()
	var cpu_cache: Dictionary = field.build_cpu_sample_cache(positions)
	var cpu_cache_build_ms: float = float(Time.get_ticks_usec() - cache_started_usec) / 1000.0
	_assert("CPU spatial cache builds", bool(cpu_cache.get("ok", false)), str(cpu_cache.get("error", "cache failed")))
	if not bool(cpu_cache.get("ok", false)):
		_finish()
		return

	var squared_error_sum: float = 0.0
	var cpu_frame_times_ms: Array[float] = []
	for frame_index: int in range(PROXY_FRAME_COUNT):
		var time_seconds: float = float(frame_index) / float(PROXY_FRAME_COUNT)
		var phase: float = TAU * time_seconds
		var started_usec: int = Time.get_ticks_usec()
		var predicted_offsets: PackedVector3Array = field.sample_cpu_cache(cpu_cache, time_seconds)
		cpu_frame_times_ms.append(float(Time.get_ticks_usec() - started_usec) / 1000.0)
		for position_index: int in range(positions.size()):
			var position: Vector3 = positions[position_index]
			var predicted: Vector3 = predicted_offsets[position_index]
			var normalized: Vector3 = _normalize_position(position, bounds)
			var expected: Vector3 = _analytic_offset(normalized, phase, diagonal)
			squared_error_sum += predicted.distance_squared_to(expected)

	var normalized_position_rmse: float = sqrt(squared_error_sum / float(PROXY_FRAME_COUNT * positions.size())) / diagonal
	var loop_squared_error: float = 0.0
	var loop_start: PackedVector3Array = field.sample_cpu_cache(cpu_cache, 0.0)
	var loop_end: PackedVector3Array = field.sample_cpu_cache(cpu_cache, 1.0)
	for position_index: int in range(positions.size()):
		loop_squared_error += loop_start[position_index].distance_squared_to(loop_end[position_index])
	var normalized_loop_closure_rmse: float = sqrt(loop_squared_error / float(positions.size())) / diagonal
	cpu_frame_times_ms.sort()
	var cpu_median_ms: float = cpu_frame_times_ms[cpu_frame_times_ms.size() / 2]

	_assert("combined base and sidecar stay within 214 KiB", combined_bytes <= MAX_COMBINED_BYTES, str(combined_bytes))
	_assert("normalized position RMSE stays below 0.1%", normalized_position_rmse <= MAX_NORMALIZED_POSITION_RMSE, "%.8f" % normalized_position_rmse)
	_assert("unique-loop closure is exact", normalized_loop_closure_rmse <= MAX_NORMALIZED_LOOP_RMSE, "%.10f" % normalized_loop_closure_rmse)
	_assert("CPU proxy frame stays within 60 FPS budget", cpu_median_ms < MAX_CPU_MEDIAN_MS, "%.3f ms" % cpu_median_ms)
	print("Fovea4D quality metrics: combined=%d bytes, position_rmse=%.8f, loop_rmse=%.10f, cpu_cache_build=%.3f ms, cpu_median=%.3f ms" % [
		combined_bytes,
		normalized_position_rmse,
		normalized_loop_closure_rmse,
		cpu_cache_build_ms,
		cpu_median_ms,
	])
	_finish()


func _load_fixture_positions(path: String) -> Dictionary:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 72 or bytes.slice(0, 8).get_string_from_ascii() != "FOVEA_3D":
		return {"ok": false, "error": "invalid base fixture header"}
	var splat_count: int = bytes.decode_u32(12)
	var color_count: int = bytes.decode_u32(16)
	var covariance_count: int = bytes.decode_u32(20)
	var minimum := Vector3(bytes.decode_float(24), bytes.decode_float(28), bytes.decode_float(32))
	var maximum := Vector3(bytes.decode_float(36), bytes.decode_float(40), bytes.decode_float(44))
	var bounds := AABB(minimum, maximum - minimum)
	var splat_offset: int = 72 + color_count * 12 + covariance_count * 32
	if splat_offset + splat_count * 16 > bytes.size() or bounds.size.length_squared() <= 0.0:
		return {"ok": false, "error": "base fixture layout is invalid"}
	var positions := PackedVector3Array()
	positions.resize(splat_count)
	for index: int in range(splat_count):
		var offset: int = splat_offset + index * 16
		var normalized := Vector3(
			float(bytes.decode_u16(offset)) / 65535.0,
			float(bytes.decode_u16(offset + 2)) / 65535.0,
			float(bytes.decode_u16(offset + 4)) / 65535.0
		)
		positions[index] = bounds.position + normalized * bounds.size
	return {"ok": true, "positions": positions, "bounds": bounds}


func _build_unique_keyframes(bounds: AABB, diagonal: float) -> Array[PackedVector3Array]:
	var frames: Array[PackedVector3Array] = []
	var cell_count: int = GRID_DIMS.x * GRID_DIMS.y * GRID_DIMS.z
	for keyframe_index: int in range(KEYFRAME_COUNT):
		var phase: float = TAU * float(keyframe_index) / float(KEYFRAME_COUNT)
		var offsets := PackedVector3Array()
		offsets.resize(cell_count)
		var cell_index: int = 0
		for z: int in range(GRID_DIMS.z):
			for y: int in range(GRID_DIMS.y):
				for x: int in range(GRID_DIMS.x):
					var normalized := Vector3(
						float(x) / float(GRID_DIMS.x - 1),
						float(y) / float(GRID_DIMS.y - 1),
						float(z) / float(GRID_DIMS.z - 1)
					)
					offsets[cell_index] = _analytic_offset(normalized, phase, diagonal)
					cell_index += 1
		frames.append(offsets)
	return frames


func _normalize_position(position: Vector3, bounds: AABB) -> Vector3:
	return ((position - bounds.position) / bounds.size).clamp(Vector3.ZERO, Vector3.ONE)


func _analytic_offset(normalized: Vector3, phase: float, diagonal: float) -> Vector3:
	return Vector3(
		diagonal * 0.010 * (0.5 + 0.5 * normalized.y) * sin(phase),
		diagonal * 0.008 * (0.75 + 0.25 * normalized.x) * cos(phase),
		diagonal * 0.006 * (0.5 + 0.5 * normalized.z) * sin(phase + PI * 0.25)
	)


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])


func _finish() -> void:
	if FileAccess.file_exists(SIDECAR_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SIDECAR_PATH))
	print("Fovea4D quality gate: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
