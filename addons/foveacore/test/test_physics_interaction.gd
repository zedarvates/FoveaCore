extends SceneTree

## Unit tests for Soft Matter & Liquid Interaction (Task 59)
## Validates: Repulsion displacement, Spring-back force, Liquid swirl vortex, and Spatial Optimization.

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n======================================================================")
	print("Soft Matter & Liquid Interaction (Task 59) Unit Tests")
	print("======================================================================")
	
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	# Setup test nodes
	var splattable = FoveaSplattable.new()
	splattable.name = "TestSplattable"
	splattable.add_to_group("splattables")
	root.add_child(splattable)

	var controller = SplatInteractionController.new()
	controller.name = "TestController"
	controller.interaction_radius = 0.3
	controller.repulsion_force = 2.0
	controller.liquid_swirl_strength = 1.0
	controller.damping = 0.1
	root.add_child(controller)

	var source = Node3D.new()
	source.name = "TestInteractionSource"
	source.add_to_group("interaction_sources")
	root.add_child(source)

	# --- Test 1: Repulsion / Displacement ---
	print("\n--- Test 1: Repulsion / Displacement ---")
	var splat1 = GaussianSplat.new()
	splat1.position = Vector3(0.0, 0.0, 0.0)
	splat1.layer_type = GaussianSplat.LayerType.BASE
	splat1.stiffness = 5.0
	
	var splats_arr1: Array[GaussianSplat] = [splat1]
	splattable.loaded_splats = splats_arr1
	
	# Position source close to the splat (displacement in -X direction)
	source.global_position = Vector3(0.1, 0.0, 0.0)
	
	# Simulate 1 frame (delta = 0.1s)
	controller._process(0.1)
	
	print("Splat 1 Position offset: ", splat1.origin_offset)
	_assert("Splat 1 moved away from source (negative X offset)", splat1.origin_offset.x < 0.0)
	_assert("Splat 1 has non-zero velocity", splat1.velocity.length_squared() > 0.0)
	_assert("Splat 1 index is registered as active", controller._active_splats.has(splattable) and 0 in controller._active_splats[splattable])

	# --- Test 2: Spring-Back to Rest ---
	print("\n--- Test 2: Spring-Back to Rest ---")
	# Move source far away so repulsion no longer applies
	source.global_position = Vector3(10.0, 10.0, 10.0)
	
	# Simulate multiple steps to let the splat spring back and settle to rest
	# With stiffness = 5.0, it should return to origin_offset = Vector3.ZERO quickly
	var settled := false
	for i in range(100):
		controller._process(0.1)
		if splat1.origin_offset.is_equal_approx(Vector3.ZERO) and splat1.velocity.is_equal_approx(Vector3.ZERO):
			settled = true
			break
			
	_assert("Splat 1 returned exactly to rest position (Vector3.ZERO)", splat1.origin_offset.is_equal_approx(Vector3.ZERO))
	_assert("Splat 1 velocity is reset to Vector3.ZERO", splat1.velocity.is_equal_approx(Vector3.ZERO))
	_assert("Splat 1 is no longer registered in active splats dictionary", not controller._active_splats.has(splattable))

	# --- Test 3: Liquid Swirl (Vortex) ---
	print("\n--- Test 3: Liquid Swirl (Vortex) ---")
	var liquid_splat = GaussianSplat.new()
	liquid_splat.position = Vector3(0.0, 0.0, 0.0)
	liquid_splat.layer_type = GaussianSplat.LayerType.LIQUID
	liquid_splat.surface_normal = Vector3.UP
	liquid_splat.stiffness = 2.0
	
	var splats_arr2: Array[GaussianSplat] = [liquid_splat]
	splattable.loaded_splats = splats_arr2
	splattable.spatial_grid = null # Reset grid
	
	# Position source along +Z axis
	source.global_position = Vector3(0.0, 0.0, 0.1)
	
	# Simulate 1 frame
	controller._process(0.1)
	
	# With source at (0, 0, 0.1), dist_vec is (0, 0, -0.1).
	# dist_vec.cross(UP) is (0, 0, -0.1).cross(0, 1, 0) = (0.1, 0, 0).
	# Thus, the liquid swirl force should push the splat in the +X direction.
	print("Liquid Splat Position offset: ", liquid_splat.origin_offset)
	_assert("Liquid splat shifted in swirl direction (positive X offset)", liquid_splat.origin_offset.x > 0.0)
	_assert("Liquid splat also pushed away in repulsion direction (negative Z offset)", liquid_splat.origin_offset.z < 0.0)

	# --- Test 4: Spatial Optimization ---
	print("\n--- Test 4: Spatial Optimization ---")
	var close_splat = GaussianSplat.new()
	close_splat.position = Vector3(0.0, 0.0, 0.0)
	
	var far_splat = GaussianSplat.new()
	far_splat.position = Vector3(5.0, 5.0, 5.0) # Far outside 0.3 radius
	
	var splats_arr3: Array[GaussianSplat] = [close_splat, far_splat]
	splattable.loaded_splats = splats_arr3
	splattable.spatial_grid = null # Reset grid
	
	# Position source near close_splat
	source.global_position = Vector3(0.05, 0.0, 0.0)
	
	controller._process(0.1)
	
	_assert("Close splat was activated and moved", close_splat.origin_offset.length_squared() > 0.0)
	_assert("Far splat remained completely static", far_splat.origin_offset.is_equal_approx(Vector3.ZERO))
	_assert("Only index 0 (close splat) is in active list", controller._active_splats[splattable].size() == 1 and 0 in controller._active_splats[splattable])

	# Cleanup nodes
	splattable.queue_free()
	controller.queue_free()
	source.queue_free()
	
	_finish()

func _finish() -> void:
	print("\n======================================================================")
	print("Physics Interaction Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("======================================================================")
	
	quit(1 if _failed > 0 else 0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		if detail.is_empty():
			print("  ✗ %s" % name)
		else:
			print("  ✗ %s — %s" % [name, detail])
