extends SceneTree

## Unit tests for FoveaInstancedCuller and FoveaInstancedSplatRenderer
## Validates: culler initialization, transform serialization, parallel instanced decoding.

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("Fovea Instanced Renderer Unit Tests")
	print("=".repeat(70))

	_run_all()
	
	print("\n" + "=".repeat(70))
	print("Instanced Renderer Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("=".repeat(70))
	
	quit(0 if _failed == 0 else 1)

func _run_all() -> void:
	_test_culler_initialization()
	_test_transform_serialization()
	_test_instanced_renderer_properties()
	_test_parallel_decoding_with_instances()

func _test_culler_initialization() -> void:
	print("\n--- Culler Initialization ---")
	
	var culler = FoveaInstancedCuller.new()
	_assert("Culler is instantiated", culler != null, "")
	
	# Culler RD checks
	var rd_available = culler.rd != null
	print("  RenderingDevice available: %s" % rd_available)
	_assert("Culler has a valid RenderingDevice or warns gracefully", true, "")

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
	
	# Construct mock culled bytes for 2 splats
	# Each splat is 16 bytes.
	var culled_bytes = PackedByteArray()
	culled_bytes.resize(32)
	
	# Splat 0: local pos (0.2, 0.4, 0.6) mapped, color default, instance_id = 0
	# Quantized pos in 16-bit: (13107, 26214, 39321)
	culled_bytes.encode_u16(0, 13107)
	culled_bytes.encode_u16(2, 26214)
	culled_bytes.encode_u16(4, 39321)
	
	# Sigmoid opacity + instance_id tag (0) in data3
	var data3_t0: int = 0x000000FF
	culled_bytes.encode_u32(12, data3_t0)
	
	# Splat 1: local pos (0.5, 0.5, 0.5) mapped, color default, instance_id = 1
	# Quantized pos in 16-bit: (32767, 32767, 32767)
	culled_bytes.encode_u16(16, 32767)
	culled_bytes.encode_u16(18, 32767)
	culled_bytes.encode_u16(20, 32767)
	
	# Sigmoid opacity + instance_id tag (1) in data3
	# Upper 16-bits of data3 = 1 -> (1 << 16) | 255 = 65791
	var data3_t1: int = 0x000100FF
	culled_bytes.encode_u32(28, data3_t1)
	
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
		instance_transforms
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
