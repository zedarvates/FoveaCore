extends SceneTree

const LoaderScript := preload("res://addons/foveacore/scripts/fovea_4d_loader.gd")

const BASE_PATH: String = "res://test/fixtures/rust_v2_fixture.fovea"
const OTHER_BASE_PATH: String = "res://test/fixtures/reference_3dgs.fovea"
const SIDECAR_PATH: String = "user://fovea4d_loader_valid.fovea4d"
const MALFORMED_PATH: String = "user://fovea4d_loader_malformed.fovea4d"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_write_bytes(SIDECAR_PATH, _build_sidecar(FileAccess.get_sha256(BASE_PATH)))
	_write_bytes(MALFORMED_PATH, PackedByteArray([1, 2, 3]))

	var valid: Dictionary = LoaderScript.load_sidecar(SIDECAR_PATH, BASE_PATH)
	_assert("matching base loads", bool(valid.get("ok", false)), str(valid))
	_assert("load returns motion field", valid.get("field") is Fovea4DMotionField, str(valid))
	var field: Fovea4DMotionField = valid.get("field")
	_assert("loaded field validates", field != null and field.validate().is_empty(), "invalid field")

	_expect_failure("different valid base fails hash binding", SIDECAR_PATH, OTHER_BASE_PATH, "SHA-256")
	_expect_failure("missing sidecar fails", "user://missing.fovea4d", BASE_PATH, "does not exist")
	_expect_failure("missing base fails", SIDECAR_PATH, "user://missing.fovea", "does not exist")
	_expect_failure("malformed sidecar fails", MALFORMED_PATH, BASE_PATH, "header")
	_expect_failure("machine sidecar path fails", "C:/temp/file.fovea4d", BASE_PATH, "project-local")
	_expect_failure("wrong sidecar extension fails", "user://file.bin", BASE_PATH, ".fovea4d")
	_expect_failure("wrong base extension fails", SIDECAR_PATH, "res://test/demo_bonsai.ply", ".fovea")

	_cleanup()
	print("Fovea4D loader tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _build_sidecar(base_digest: String) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(224)
	var magic: PackedByteArray = "FOVEA_4D".to_ascii_buffer()
	for index: int in range(magic.size()):
		bytes[index] = magic[index]
	bytes.encode_u32(8, 1)
	bytes.encode_u32(12, 128)
	bytes.encode_u32(16, 1)
	bytes.encode_u32(20, 1)
	for index: int in range(32):
		bytes[24 + index] = base_digest.substr(index * 2, 2).hex_to_int()
	bytes.encode_u16(56, 2)
	bytes.encode_u16(58, 2)
	bytes.encode_u16(60, 2)
	bytes.encode_u16(62, 2)
	bytes.encode_float(64, 4.0)
	bytes.encode_float(80, 1.0)
	bytes.encode_float(84, 1.0)
	bytes.encode_float(88, 1.0)
	bytes.encode_float(92, 0.01)
	bytes.encode_float(96, 0.01)
	bytes.encode_float(100, 0.01)
	bytes.encode_u64(104, 128)
	bytes.encode_u64(112, 96)
	return bytes


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_assert("fixture write", false, error_string(FileAccess.get_open_error()))
		return
	file.store_buffer(bytes)
	file.close()


func _expect_failure(name: String, sidecar_path: String, base_path: String, marker: String) -> void:
	var result: Dictionary = LoaderScript.load_sidecar(sidecar_path, base_path)
	_assert(
		name,
		not bool(result.get("ok", true)) and str(result.get("error", "")).contains(marker),
		str(result)
	)


func _cleanup() -> void:
	var directory: DirAccess = DirAccess.open("user://")
	if directory == null:
		return
	for path: String in [SIDECAR_PATH, MALFORMED_PATH]:
		if FileAccess.file_exists(path):
			directory.remove(path.get_file())


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
