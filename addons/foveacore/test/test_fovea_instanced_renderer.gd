extends SceneTree

## Unit tests for FoveaInstancedCuller and FoveaInstancedSplatRenderer
## Validates: culler initialization, transform serialization, parallel instanced decoding.

## Marks this suite as requiring a GPU/RenderingDevice for meaningful validation.
## Without one, GPU-only assertions are reported as skipped while source-level
## layout assertions still run. run_all_tests.gd routes this to the "gpu" group.
const REQUIRES_GPU := true
const FoveaInstancedSplatLayout := preload("res://addons/foveacore/scripts/advanced/fovea_instanced_splat_layout.gd")

var _passed := 0
var _failed := 0
var _skipped := 0

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("Fovea Instanced Renderer Unit Tests")
	print("=".repeat(70))
	call_deferred("_run_after_tree_ready")


func _run_after_tree_ready() -> void:
	await process_frame
	_run_all()

	print("\n" + "=".repeat(70))
	print("Instanced Renderer Tests: %d passed, %d failed, %d skipped (%.0f%%)" % [
		_passed, _failed, _skipped,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("=".repeat(70))

	quit(0 if _failed == 0 else 1)

func _run_all() -> void:
	_test_culler_initialization()
	_test_transform_serialization()
	_test_instanced_renderer_properties()
	_test_parallel_decoding_with_instances()
	_test_gpu_output_layout()

func _test_culler_initialization() -> void:
	print("\n--- Culler Initialization ---")
	
	var culler = FoveaInstancedCuller.new()
	_assert("Culler is instantiated", culler != null, "")
	
	# Culler RD checks. A missing device is a hardware block, not a pass.
	var rd_available = culler.rd != null
	print("  RenderingDevice available: %s" % rd_available)
	if rd_available:
		_pass("Culler has a valid RenderingDevice")
		culler.cleanup()
	else:
		_skip("Culler GPU validation", "RenderingDevice unavailable")

func _test_transform_serialization() -> void:
	print("\n--- Transform Serialization ---")
	
	var transforms: Array[Transform3D] = [
		Transform3D(Basis().rotated(Vector3.UP, PI / 4.0), Vector3(1, 2, 3)),
		Transform3D(Basis().scaled(Vector3(2, 2, 2)), Vector3(-1, 0, 5))
	]
	
	var serialized = FoveaInstancedCuller.serialize_transforms(transforms)
	_assert("Serialized array size matches expected bytes", serialized.size() == 2 * 64, 
		"Expected %d bytes, got %d" % [2 * 64, serialized.size()])
		
	# Verify first transform values
	var t0_origin_x = serialized.decode_float(48)
	var t0_origin_y = serialized.decode_float(52)
	var t0_origin_z = serialized.decode_float(56)
	_assert_approx("t0 origin X", t0_origin_x, 1.0, 0.001)
	_assert_approx("t0 origin Y", t0_origin_y, 2.0, 0.001)
	_assert_approx("t0 origin Z", t0_origin_z, 3.0, 0.001)
	
	# Verify second transform values (scaling)
	var t1_basis_00 = serialized.decode_float(64) # Row 0 Col 0
	var t1_basis_11 = serialized.decode_float(64 + 20) # Row 1 Col 1
	var t1_basis_22 = serialized.decode_float(64 + 40) # Row 2 Col 2
	_assert_approx("t1 scale X", t1_basis_00, 2.0, 0.001)
	_assert_approx("t1 scale Y", t1_basis_11, 2.0, 0.001)
	_assert_approx("t1 scale Z", t1_basis_22, 2.0, 0.001)

func _test_instanced_renderer_properties() -> void:
	print("\n--- Instanced Renderer Properties ---")
	
	var renderer = FoveaInstancedSplatRenderer.new()
	_assert("Renderer node is instantiated", renderer != null, "")
	_assert("Renderer has instance_transforms array", renderer.instance_transforms != null, "")
	
	# Add to tree
	root.add_child(renderer)
	if renderer.material_override == null:
		renderer._ready()
	_assert("Renderer material_override initialized in tree", renderer.material_override != null, "")
	root.remove_child(renderer)
	renderer.queue_free()

func _test_parallel_decoding_with_instances() -> void:
	print("\n--- Parallel Decoding with Instance Matrices ---")
	
	# Construct mock GPU output bytes for 2 splats.
	# Each output record is 24 bytes: canonical splat + local_idx + instance_id.
	var culled_bytes = PackedByteArray()
	culled_bytes.resize(48)
	
	# Splat 0: local pos (0.2, 0.4, 0.6) mapped, color default, instance_id = 0
	# Quantized pos in 16-bit: (13107, 26214, 39321)
	culled_bytes.encode_u16(0, 13107)
	culled_bytes.encode_u16(2, 26214)
	culled_bytes.encode_u16(4, 39321)
	
	# Preserve dither (173) and brush (STIPPLE = 4) in canonical data3.
	var data3_t0: int = 0x04AD00FF
	culled_bytes.encode_u32(12, data3_t0)
	culled_bytes.encode_u32(16, 7) # local_idx
	culled_bytes.encode_u32(20, 0) # instance_id
	
	# Splat 1: local pos (0.5, 0.5, 0.5) mapped, color default, instance_id = 1
	# Quantized pos in 16-bit: (32767, 32767, 32767)
	culled_bytes.encode_u16(24, 32767)
	culled_bytes.encode_u16(26, 32767)
	culled_bytes.encode_u16(28, 32767)
	
	# Second record uses independent canonical metadata and instance_id = 1.
	var data3_t1: int = 0x02B400FF
	culled_bytes.encode_u32(36, data3_t1)
	culled_bytes.encode_u32(40, 11) # local_idx
	culled_bytes.encode_u32(44, 1)  # instance_id
	_assert("Splat 0 canonical dither is preserved", culled_bytes.decode_u8(14) == 173, "")
	_assert("Splat 0 canonical brush is preserved", culled_bytes.decode_u8(15) == 4, "")
	
	# Instance transforms
	var instance_transforms: Array[Transform3D] = [
		Transform3D(Basis(), Vector3(10, 0, 0)),             # translation (+10, 0, 0)
		Transform3D(Basis().scaled(Vector3(2, 2, 2)), Vector3(0, 20, 0)) # scale x2, translation (0, +20, 0)
	]
	
	# aabb
	var aabb_min := Vector3.ZERO
	var aabb_max := Vector3(10, 10, 10)
	
	var decode_result = FoveaThreadPool.decode_parallel(
		culled_bytes,
		2,
		aabb_min,
		aabb_max,
		instance_transforms,
		[], [], [], [], [], [], [], [], [], [],
		FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE
	)
	
	_assert("Decoded count matches", decode_result.splat_count == 2, "")
	_assert("Transform array size matches", decode_result.xf_array.size() == 8, 
		"Expected 8 Vector3s (2 transforms), got %d" % decode_result.xf_array.size())
		
	# Verify Splat 0 position: local (0.2, 0.4, 0.6) * aabb size (10, 10, 10) = (2, 4, 6)
	# Transformed by instance 0 (+10, 0, 0) -> (12, 4, 6)
	var splat0_pos = decode_result.xf_array[3] # Column 3 of transform 0
	_assert_approx("Splat 0 transformed pos X", splat0_pos.x, 12.0, 0.1)
	_assert_approx("Splat 0 transformed pos Y", splat0_pos.y, 4.0, 0.1)
	_assert_approx("Splat 0 transformed pos Z", splat0_pos.z, 6.0, 0.1)
	_assert("Splat 0 basis is identity", decode_result.xf_array[0] == Vector3.RIGHT, "")
	
	# Verify Splat 1 position: local (0.5, 0.5, 0.5) * aabb size (10, 10, 10) = (5, 5, 5)
	# Transformed by instance 1 (scale 2, translation (0, 20, 0)) -> (5 * 2, 5 * 2 + 20, 5 * 2) = (10, 30, 10)
	var splat1_pos = decode_result.xf_array[7] # Column 3 of transform 1
	_assert_approx("Splat 1 transformed pos X", splat1_pos.x, 10.0, 0.1)
	_assert_approx("Splat 1 transformed pos Y", splat1_pos.y, 30.0, 0.1)
	_assert_approx("Splat 1 transformed pos Z", splat1_pos.z, 10.0, 0.1)
	
	# Verify Splat 1 basis is scaled by 2
	var splat1_basis_x = decode_result.xf_array[4]
	_assert_approx("Splat 1 basis X scale", splat1_basis_x.x, 2.0, 0.01)

	# The generic decoder must recognize an exact 24-byte output buffer even
	# when a caller does not provide the optional stride argument.
	var auto_stride_result := FoveaThreadPool.decode_parallel(
		culled_bytes,
		2,
		aabb_min,
		aabb_max,
		instance_transforms
	)
	_assert_approx("Auto-detected 24-byte stride preserves instance routing", auto_stride_result.xf_array[7].y, 30.0, 0.1)

func _test_gpu_output_layout() -> void:
	print("\n--- GPU Output Layout ---")
	var culler := FoveaInstancedCuller.new()
	if culler.rd == null or not culler.pipeline_rid.is_valid():
		_skip("GPU output layout", "RenderingDevice or compute pipeline unavailable")
		return

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.global_position = Vector3(0, 0, 5)

	# One canonical v2 record with non-default artistic metadata.
	var raw_bytes := PackedByteArray()
	raw_bytes.resize(16)
	raw_bytes.encode_u16(0, 32767)
	raw_bytes.encode_u16(2, 32767)
	raw_bytes.encode_u16(4, 32767)
	raw_bytes.encode_u32(12, 0x04AD00FF) # opacity, layer, dither=173, brush=4

	var result := culler.process_instanced_splats(
		raw_bytes,
		[Transform3D.IDENTITY, Transform3D(Basis(), Vector3(2, 0, 0))],
		camera,
		RID(),
		0.0,
		Vector3(-1, -1, -1),
		Vector3(1, 1, 1)
	)

	var output_buffer: RID = result.get("buffer_rid", RID())
	var output_count: int = result.get("count", 0)
	_assert("GPU culler emits one splat per visible instance", output_count == 2, "")
	if output_buffer.is_valid() and output_count == 2:
		var output_bytes: PackedByteArray = culler.rd.buffer_get_data(output_buffer)
		_assert("GPU output uses the declared record size", output_bytes.size() >= 2 * FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE, "")
		var instance_ids: Array[int] = []
		for i: int in range(2):
			var base: int = i * FoveaInstancedSplatLayout.OUTPUT_SPLAT_BYTE_SIZE
			_assert("GPU output preserves canonical data3 for record %d" % i, output_bytes.decode_u32(base + 12) == 0x04AD00FF, "")
			_assert("GPU output writes local_idx separately for record %d" % i, output_bytes.decode_u32(base + FoveaInstancedSplatLayout.LOCAL_IDX_OFFSET) == 0, "")
			instance_ids.append(output_bytes.decode_u32(base + FoveaInstancedSplatLayout.INSTANCE_ID_OFFSET))
		_assert("GPU output preserves both instance identifiers", instance_ids.has(0) and instance_ids.has(1), "")
		culler.rd.free_rid(output_buffer)
	elif output_buffer.is_valid():
		culler.rd.free_rid(output_buffer)

	root.remove_child(camera)
	camera.queue_free()
	culler.cleanup()

func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_pass(name if detail.is_empty() else "%s — %s" % [name, detail])
	else:
		_fail(name, detail)

func _assert_approx(name: String, val: float, target: float, tol: float) -> void:
	if abs(val - target) <= tol:
		_pass("%s = %.4f ≈ %.4f ±%.4f" % [name, val, target, tol])
	else:
		_fail(name, "%.4f ≠ %.4f ±%.4f" % [val, target, tol])

func _pass(detail: String) -> void:
	_passed += 1
	print("  ✓ %s" % detail)

func _fail(test_name: String, err: String) -> void:
	_failed += 1
	print("  ✗ %s — %s" % [test_name, err])

func _skip(test_name: String, reason: String) -> void:
	_skipped += 1
	print("  ⏭ %s — %s" % [test_name, reason])
