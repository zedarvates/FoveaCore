extends SceneTree

const SHADER_PATH: String = "res://addons/foveacore/shaders/fovea_4d_motion.glsl"
const PIPELINE_PATH: String = "res://addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	var shader_source: String = _read_text(SHADER_PATH)
	var pipeline_source: String = _read_text(PIPELINE_PATH)

	_assert("4D motion shader exists", not shader_source.is_empty(), SHADER_PATH)
	_assert("shader uses 256 threads", shader_source.contains("local_size_x = 256"), "missing local size")
	for binding: int in range(4):
		_assert(
			"shader declares binding %d" % binding,
			shader_source.contains("binding = %d" % binding),
			"missing binding"
		)
	_assert("shader documents X-fastest indexing", shader_source.contains("x + dims.x * (y + dims.y * z)"), "index contract missing")
	_assert("shader includes keyframe-major indexing", shader_source.contains("keyframe * cells_per_frame"), "time layout missing")
	_assert("shader decodes against base bounds", shader_source.contains("base_min") and shader_source.contains("base_max"), "base bounds missing")
	_assert("shader encodes against animated bounds", shader_source.contains("animated_min") and shader_source.contains("animated_max"), "animated bounds missing")
	_assert("shader performs temporal interpolation", shader_source.contains("mix(offset0, offset1"), "temporal mix missing")

	_assert("pipeline exposes configure API", pipeline_source.contains("func configure_4d_motion("), "configure API missing")
	_assert("pipeline exposes time API", pipeline_source.contains("func set_4d_motion_time("), "time API missing")
	_assert("pipeline exposes clear API", pipeline_source.contains("func clear_4d_motion("), "clear API missing")
	var dispatch_index: int = pipeline_source.find("# 4D_MOTION_DISPATCH_BEFORE_CULLING")
	var cull_index: int = pipeline_source.find("# 6. Ex")
	_assert("4D dispatch precedes culling", dispatch_index >= 0 and cull_index >= 0 and dispatch_index < cull_index, "dispatch ordering missing")
	_assert("delta and 4D are exclusive", pipeline_source.contains("motion_4d_field == null") and pipeline_source.contains("delta_buffer.is_valid()"), "exclusive source selection missing")

	print("Fovea4D GPU contract tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
