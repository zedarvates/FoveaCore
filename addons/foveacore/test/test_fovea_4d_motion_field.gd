extends SceneTree

const MotionFieldScript := preload("res://addons/foveacore/scripts/fovea_4d_motion_field.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	var payload: PackedByteArray = _build_payload()
	var header: Dictionary = _header(true)
	var field: Fovea4DMotionField = MotionFieldScript.new()
	_assert("valid field configures", field.configure(header, payload).is_empty(), field.validate())
	_assert_vec("corner sample", field.sample(Vector3.ZERO, 0.0), Vector3.ZERO)
	_assert_vec("spatial center", field.sample(Vector3(0.5, 0.5, 0.5), 0.0), Vector3(0.5, 0.5, 0.5))
	_assert_vec("temporal midpoint", field.sample(Vector3(0.5, 0.5, 0.5), 0.5), Vector3(1.5, 1.5, 1.5))
	_assert_vec("second keyframe", field.sample(Vector3(0.5, 0.5, 0.5), 1.0), Vector3(2.5, 2.5, 2.5))
	_assert_vec("last-to-first loop", field.sample(Vector3(0.5, 0.5, 0.5), 1.5), Vector3(1.5, 1.5, 1.5))
	_assert_vec("negative time wraps", field.sample(Vector3(0.5, 0.5, 0.5), -0.5), Vector3(1.5, 1.5, 1.5))
	_assert_vec("loop closes", field.sample(Vector3(0.5, 0.5, 0.5), 2.0), Vector3(0.5, 0.5, 0.5))
	var cpu_cache: Dictionary = field.build_cpu_sample_cache(PackedVector3Array([Vector3.ZERO, Vector3(0.5, 0.5, 0.5)]))
	_assert("CPU batch cache builds", bool(cpu_cache.get("ok", false)), str(cpu_cache))
	var cached_samples: PackedVector3Array = field.sample_cpu_cache(cpu_cache, 0.5)
	_assert("CPU batch matches scalar samples", cached_samples.size() == 2 and cached_samples[0].is_equal_approx(field.sample(Vector3.ZERO, 0.5)) and cached_samples[1].is_equal_approx(field.sample(Vector3(0.5, 0.5, 0.5), 0.5)), str(cached_samples))

	var bounds: AABB = field.animated_bounds(AABB(Vector3.ZERO, Vector3.ONE))
	_assert_vec("animated bounds minimum", bounds.position, Vector3.ZERO)
	_assert_vec("animated bounds maximum", bounds.end, Vector3(4.0, 4.0, 4.0))
	var gpu_bytes: PackedByteArray = field.to_gpu_bytes()
	_assert("GPU records are std430-safe", gpu_bytes.size() == 2 * 8 * 8, str(gpu_bytes.size()))

	var non_loop: Fovea4DMotionField = MotionFieldScript.new()
	_assert("non-loop configures", non_loop.configure(_header(false), payload).is_empty(), non_loop.validate())
	_assert_vec("non-loop clamps end", non_loop.sample(Vector3(0.5, 0.5, 0.5), 99.0), Vector3(2.5, 2.5, 2.5))

	var invalid: Fovea4DMotionField = MotionFieldScript.new()
	_assert("short payload rejected", not invalid.configure(header, payload.slice(0, payload.size() - 1)).is_empty(), "accepted")

	print("Fovea4D motion field tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _header(looped: bool) -> Dictionary:
	return {
		"flags": 1 if looped else 0,
		"loop": looped,
		"base_sha256": "00".repeat(32),
		"grid_dims": Vector3i(2, 2, 2),
		"keyframe_count": 2,
		"sample_rate_hz": 1.0,
		"bounds_min": Vector3.ZERO,
		"bounds_max": Vector3.ONE,
		"displacement_scale": Vector3.ONE,
		"payload_size": 96,
	}


func _build_payload() -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(96)
	var cursor: int = 0
	for keyframe: int in range(2):
		for z: int in range(2):
			for y: int in range(2):
				for x: int in range(2):
					var offset := Vector3i(x, y, z) + Vector3i.ONE * keyframe * 2
					payload.encode_u16(cursor, offset.x & 0xffff)
					payload.encode_u16(cursor + 2, offset.y & 0xffff)
					payload.encode_u16(cursor + 4, offset.z & 0xffff)
					cursor += 6
	return payload


func _assert_vec(test_name: String, actual: Vector3, expected: Vector3) -> void:
	_assert(test_name, actual.is_equal_approx(expected), "expected=%s actual=%s" % [expected, actual])


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
