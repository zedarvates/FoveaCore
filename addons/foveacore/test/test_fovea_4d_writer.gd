extends SceneTree

const WriterScript := preload("res://addons/foveacore/scripts/fovea_4d_writer.gd")
const FormatScript := preload("res://addons/foveacore/scripts/fovea_4d_format.gd")
const LoaderScript := preload("res://addons/foveacore/scripts/fovea_4d_loader.gd")

const BASE_PATH: String = "res://test/fixtures/rust_v2_fixture.fovea"
const OUTPUT_A: String = "user://fovea4d_writer_a.fovea4d"
const OUTPUT_B: String = "user://fovea4d_writer_b.fovea4d"
const ZERO_AXIS_OUTPUT: String = "user://fovea4d_writer_zero_axis.fovea4d"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	var frames: Array[PackedVector3Array] = _build_frames()
	var bounds := AABB(Vector3.ZERO, Vector3.ONE)
	var write_a: Error = WriterScript.write_sidecar(OUTPUT_A, BASE_PATH, Vector3i(2, 2, 2), frames, 4.0, true, bounds)
	var write_b: Error = WriterScript.write_sidecar(OUTPUT_B, BASE_PATH, Vector3i(2, 2, 2), frames, 4.0, true, bounds)
	_assert("first write succeeds", write_a == OK, error_string(write_a))
	_assert("second write succeeds", write_b == OK, error_string(write_b))
	var bytes_a: PackedByteArray = FileAccess.get_file_as_bytes(OUTPUT_A)
	var bytes_b: PackedByteArray = FileAccess.get_file_as_bytes(OUTPUT_B)
	_assert("sidecar size is exact", bytes_a.size() == 224, str(bytes_a.size()))
	_assert("writer is deterministic", bytes_a == bytes_b, "outputs differ")
	var parsed: Dictionary = FormatScript.parse_bytes(bytes_a)
	_assert("written bytes parse", bool(parsed.get("ok", false)), str(parsed))
	_assert("base digest is bound", str(parsed.get("header", {}).get("base_sha256", "")) == FileAccess.get_sha256(BASE_PATH), str(parsed))
	var loaded: Dictionary = LoaderScript.load_sidecar(OUTPUT_A, BASE_PATH)
	_assert("written sidecar reloads", bool(loaded.get("ok", false)), str(loaded))
	var field: Fovea4DMotionField = loaded.get("field")
	_assert_vec("maximum offset round-trips", field.sample(Vector3.ONE, 0.25), Vector3(0.3, 0.4, 0.5), 0.00002)

	var zero_axis_frames: Array[PackedVector3Array] = _build_zero_axis_frames()
	var zero_error: Error = WriterScript.write_sidecar(ZERO_AXIS_OUTPUT, BASE_PATH, Vector3i(2, 2, 2), zero_axis_frames, 2.0, false, bounds)
	_assert("all-zero axes are accepted", zero_error == OK, error_string(zero_error))
	var zero_loaded: Dictionary = LoaderScript.load_sidecar(ZERO_AXIS_OUTPUT, BASE_PATH)
	var zero_field: Fovea4DMotionField = zero_loaded.get("field")
	var zero_sample: Vector3 = zero_field.sample(Vector3.ONE, 1.0)
	_assert("zero axes decode exactly", zero_sample.y == 0.0 and zero_sample.z == 0.0, str(zero_sample))

	var empty_frames: Array[PackedVector3Array] = []
	_assert("empty keys rejected", WriterScript.write_sidecar(OUTPUT_A, BASE_PATH, Vector3i(2, 2, 2), empty_frames, 4.0, true, bounds) == ERR_INVALID_PARAMETER, "accepted")
	var inconsistent: Array[PackedVector3Array] = frames.duplicate()
	inconsistent[1] = PackedVector3Array([Vector3.ZERO])
	_assert("inconsistent cells rejected", WriterScript.write_sidecar(OUTPUT_A, BASE_PATH, Vector3i(2, 2, 2), inconsistent, 4.0, true, bounds) == ERR_INVALID_PARAMETER, "accepted")
	_assert("machine output rejected", WriterScript.write_sidecar("C:/temp/test.fovea4d", BASE_PATH, Vector3i(2, 2, 2), frames, 4.0, true, bounds) == ERR_INVALID_PARAMETER, "accepted")
	_assert("invalid bounds rejected", WriterScript.write_sidecar(OUTPUT_A, BASE_PATH, Vector3i(2, 2, 2), frames, 4.0, true, AABB(Vector3.ONE, -Vector3.ONE)) == ERR_INVALID_PARAMETER, "accepted")
	var non_finite: Array[PackedVector3Array] = frames.duplicate(true)
	non_finite[0][0] = Vector3(NAN, 0.0, 0.0)
	_assert("non-finite offset rejected", WriterScript.write_sidecar(OUTPUT_A, BASE_PATH, Vector3i(2, 2, 2), non_finite, 4.0, true, bounds) == ERR_INVALID_DATA, "accepted")

	_cleanup()
	print("Fovea4D writer tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _build_frames() -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for keyframe: int in range(2):
		var frame := PackedVector3Array()
		for z: int in range(2):
			for y: int in range(2):
				for x: int in range(2):
					frame.append(Vector3(float(x) * 0.1, float(y) * 0.1, float(z) * 0.1) + Vector3(0.2, 0.3, 0.4) * keyframe)
		result.append(frame)
	return result


func _build_zero_axis_frames() -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for keyframe: int in range(2):
		var frame := PackedVector3Array()
		for index: int in range(8):
			frame.append(Vector3(float(index + keyframe) * 0.01, 0.0, 0.0))
		result.append(frame)
	return result


func _cleanup() -> void:
	var directory: DirAccess = DirAccess.open("user://")
	if directory == null:
		return
	for path: String in [OUTPUT_A, OUTPUT_B, ZERO_AXIS_OUTPUT]:
		if FileAccess.file_exists(path):
			directory.remove(path.get_file())


func _assert_vec(test_name: String, actual: Vector3, expected: Vector3, tolerance: float) -> void:
	_assert(test_name, actual.distance_to(expected) <= tolerance, "expected=%s actual=%s" % [expected, actual])


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
