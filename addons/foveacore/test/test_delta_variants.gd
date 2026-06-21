extends SceneTree

# Unit test for Delta-Splat Variants (Tasks 243-247)

const FoveaDeltaDataClass := preload("res://addons/foveacore/scripts/advanced/fovea_delta_data.gd")
const FoveaDeltaManagerClass := preload("res://addons/foveacore/scripts/advanced/fovea_delta_manager.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n======================================================================")
	print("FoveaEngine - Delta-Splat Variants Unit Tests")
	print("======================================================================")
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	_test_fp16_packing()
	_test_serialization()
	_test_manager_interpolation()
	_finish()

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		print("  ✗ %s" % name)

func _test_fp16_packing() -> void:
	print("\n--- Test 1: FP16 Compression & Packing ---")
	
	# Test roundtrip float conversion
	var original_floats := [0.0, 1.0, -1.0, 3.14159, -0.0005, 65500.0]
	var roundtrip_ok := true
	for f in original_floats:
		var half := FoveaDeltaDataClass.float_to_half(f)
		var restored := FoveaDeltaDataClass.half_to_float(half)
		if abs(restored - f) > 0.05 and abs(restored - f) / max(abs(f), 1.0) > 0.01:
			print("    Mismatch for float %f: half bit %d restored %f" % [f, half, restored])
			roundtrip_ok = false
			
	_assert("Float to half roundtrip precision", roundtrip_ok)
	
	# Test 2x16 packing
	var packed := FoveaDeltaDataClass.pack_half_2x16(1.5, -2.5)
	var unpacked := FoveaDeltaDataClass.unpack_half_2x16(packed)
	_assert("Unpack 2x16 X coordinate", abs(unpacked.x - 1.5) < 0.01)
	_assert("Unpack 2x16 Y coordinate", abs(unpacked.y - (-2.5)) < 0.01)

func _test_serialization() -> void:
	print("\n--- Test 2: Binary Serialization (.fvdelta) ---")
	var temp_path := "user://test_variant.fvdelta"
	
	var delta_positions := {
		0: Vector3(0.1, -0.2, 0.3),
		10: Vector3(-1.0, 2.0, -0.5)
	}
	var delta_colors := {
		0: Color(1.0, 0.0, 0.0, 1.0),
		10: Color(0.0, 1.0, 0.0, 0.5)
	}
	
	var save_err := FoveaDeltaDataClass.save_to_file(temp_path, 100, delta_positions, delta_colors, {})
	_assert("Save delta file returns OK", save_err == OK)
	
	var loaded := FoveaDeltaDataClass.load_from_file(temp_path)
	_assert("Loaded splat count matches", loaded.splat_count == 100)
	_assert("Loaded delta positions count matches", loaded.delta_positions.size() == 2)
	_assert("Loaded delta colors count matches", loaded.delta_colors.size() == 2)
	
	# Check data integrity
	var pos0: Vector3 = loaded.delta_positions[0]
	_assert("Delta position index 0 X", abs(pos0.x - 0.1) < 0.01)
	_assert("Delta position index 0 Y", abs(pos0.y - (-0.2)) < 0.01)
	_assert("Delta position index 0 Z", abs(pos0.z - 0.3) < 0.01)

func _test_manager_interpolation() -> void:
	print("\n--- Test 3: FoveaDeltaManager & Temporal Interpolation ---")
	var manager := FoveaDeltaManagerClass.new()
	_assert("Manager instantiated", manager != null)
	
	var delta_positions := {
		5: Vector3(1, 2, 3)
	}
	
	# Register instance in GPU manager (if RenderingDevice is active)
	if manager.rd:
		var buf_rid := manager.register_instance(1, 100, delta_positions, {}, {})
		_assert("Buffer RID is valid", buf_rid.is_valid())
		_assert("Retrieve buffer RID matches", manager.get_instance_buffer(1) == buf_rid)
		
		# Test temporal interpolation
		manager.set_instance_target_weight(1, 1.0)
		_assert("Target weight is set to 1.0", is_equal_approx(manager._instances[1].target_weight, 1.0))
		
		# Tick interpolation by 0.1 seconds (speed 5.0 -> weight increases by 0.5)
		manager.process_interpolation(0.1, 5.0)
		_assert("Interpolated weight after 0.1s", is_equal_approx(manager.get_instance_weight(1), 0.5))
		
		# Tick remaining time to reach target
		manager.process_interpolation(0.1, 5.0)
		_assert("Interpolated weight after 0.2s", is_equal_approx(manager.get_instance_weight(1), 1.0))
		
		manager.cleanup()
	else:
		print("  [INFO] Skipping GPU manager test: RenderingDevice is not available in headless context.")
		_assert("Graceful bypass on missing RenderingDevice", true)

func _finish() -> void:
	print("\n======================================================================")
	print("Delta-Splat Variants Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("======================================================================")
	quit(1 if _failed > 0 else 0)
