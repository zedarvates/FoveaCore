extends SceneTree

const REQUIRES_GPU := true
const LoaderScript := preload("res://addons/foveacore/scripts/fovea_4d_loader.gd")
const PipelineScript := preload("res://addons/foveacore/scripts/advanced/gpu_culler_pipeline.gd")

const BASE_PATH: String = "res://test/fixtures/rust_v2_fixture.fovea"
const SIDECAR_PATH: String = "res://test/fixtures/gdscript_fovea4d_v1_fixture.fovea4d"
const SHADER_PATH: String = "res://addons/foveacore/shaders/fovea_4d_motion.glsl"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	var loaded: Dictionary = LoaderScript.load_sidecar(SIDECAR_PATH, BASE_PATH)
	_assert("fixture loads", bool(loaded.get("ok", false)), str(loaded.get("error", "load failed")))
	if not bool(loaded.get("ok", false)):
		_finish()
		return
	var field: Fovea4DMotionField = loaded.get("field")
	var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
	_assert("local RenderingDevice is available", rd != null, "GPU backend unavailable")
	if rd == null:
		_finish()
		return

	var shader_file: RDShaderFile = load(SHADER_PATH)
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	var compile_error: String = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	_assert("motion shader compiles", compile_error.is_empty(), compile_error)
	var shader: RID = rd.shader_create_from_spirv(spirv)
	var pipeline: RID = rd.compute_pipeline_create(shader)
	_assert("motion pipeline is valid", pipeline.is_valid(), "invalid compute pipeline")

	var base_bounds := AABB(field.bounds_min, field.bounds_max - field.bounds_min)
	var animated_bounds: AABB = field.animated_bounds(base_bounds)
	var sample_time: float = 0.25
	var base_position: Vector3 = base_bounds.position
	var expected_position: Vector3 = base_position + field.sample(base_position, sample_time)
	var base_bytes := PackedByteArray()
	base_bytes.resize(16)
	base_bytes.encode_u32(0, 0)
	base_bytes.encode_u32(4, 0xabcd0000)
	base_bytes.encode_u32(8, 0x12345678)
	base_bytes.encode_u32(12, 0x89abcdef)
	var base_buffer: RID = rd.storage_buffer_create(16, base_bytes)
	var animated_buffer: RID = rd.storage_buffer_create(16)
	var field_bytes: PackedByteArray = field.to_gpu_bytes()
	var field_buffer: RID = rd.storage_buffer_create(field_bytes.size(), field_bytes)
	var params_bytes: PackedByteArray = _build_params(field, base_bounds, animated_bounds, sample_time)
	var params_buffer: RID = rd.storage_buffer_create(params_bytes.size(), params_bytes)
	var uniform_set: RID = rd.uniform_set_create([
		_storage_uniform(0, base_buffer),
		_storage_uniform(1, animated_buffer),
		_storage_uniform(2, field_buffer),
		_storage_uniform(3, params_buffer),
	], shader, 0)

	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

	var output: PackedByteArray = rd.buffer_get_data(animated_buffer)
	var actual_position: Vector3 = _decode_position(output, animated_bounds)
	var quantization_unit: Vector3 = animated_bounds.size / 65535.0
	var tolerance: float = quantization_unit.length() + 0.000001
	_assert("GPU position matches CPU sample", actual_position.distance_to(expected_position) <= tolerance, "%s != %s" % [actual_position, expected_position])
	_assert("normal bits are preserved", output.decode_u32(4) & 0xffff0000 == 0xabcd0000, "normal changed")
	_assert("color and covariance are preserved", output.decode_u32(8) == 0x12345678, "data2 changed")
	_assert("opacity and flags are preserved", output.decode_u32(12) == 0x89abcdef, "data3 changed")

	rd.free_rid(uniform_set)
	rd.free_rid(params_buffer)
	rd.free_rid(field_buffer)
	rd.free_rid(animated_buffer)
	rd.free_rid(base_buffer)
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free()

	var culler: GPUCullerPipeline = PipelineScript.new()
	_assert("culler owns a local RenderingDevice", culler.rd != null, "pipeline GPU unavailable")
	if culler.rd != null:
		_assert("culler accepts a validated motion field", culler.configure_4d_motion(field, base_bounds) == OK, "configuration rejected")
		_assert("culler creates persistent motion buffers", culler.motion_4d_field_buffer.is_valid() and culler.motion_4d_params_buffer.is_valid(), "buffers missing")
		culler.set_4d_motion_time(sample_time)
		_assert("culler stores finite playback time", is_equal_approx(culler.motion_4d_time_seconds, sample_time), "time not stored")
		culler.clear_4d_motion()
		_assert("culler clear restores static source state", culler.motion_4d_field == null and not culler.motion_4d_field_buffer.is_valid(), "motion state retained")
	culler.cleanup()
	_finish()


func _build_params(field: Fovea4DMotionField, base_bounds: AABB, animated_bounds: AABB, time_seconds: float) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(128)
	bytes.encode_u32(0, 1)
	bytes.encode_u32(4, field.grid_dims.x)
	bytes.encode_u32(8, field.grid_dims.y)
	bytes.encode_u32(12, field.grid_dims.z)
	_encode_vec3(bytes, 16, base_bounds.position)
	bytes.encode_float(28, float(field.keyframe_count))
	_encode_vec3(bytes, 32, base_bounds.end)
	bytes.encode_float(44, field.sample_rate_hz)
	_encode_vec3(bytes, 48, animated_bounds.position)
	bytes.encode_float(60, 1.0 if field.loop else 0.0)
	_encode_vec3(bytes, 64, animated_bounds.end)
	_encode_vec3(bytes, 80, field.displacement_scale)
	bytes.encode_float(92, time_seconds)
	_encode_vec3(bytes, 96, field.bounds_min)
	_encode_vec3(bytes, 112, field.bounds_max)
	return bytes


func _encode_vec3(bytes: PackedByteArray, offset: int, value: Vector3) -> void:
	bytes.encode_float(offset, value.x)
	bytes.encode_float(offset + 4, value.y)
	bytes.encode_float(offset + 8, value.z)


func _storage_uniform(binding: int, buffer: RID) -> RDUniform:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	return uniform


func _decode_position(bytes: PackedByteArray, bounds: AABB) -> Vector3:
	var data0: int = bytes.decode_u32(0)
	var data1: int = bytes.decode_u32(4)
	var normalized := Vector3(
		float(data0 & 0xffff) / 65535.0,
		float((data0 >> 16) & 0xffff) / 65535.0,
		float(data1 & 0xffff) / 65535.0
	)
	return bounds.position + normalized * bounds.size


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])


func _finish() -> void:
	print("Fovea4D GPU readback tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
