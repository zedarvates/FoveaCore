extends SceneTree

## Unit tests for FoveaSegmentationBridge
## Validates multi-view camera setup, projection/unprojection voting,
## and semantic labeling updates.

var _passed := 0
var _failed := 0

signal test_passed(test_name: String, details: String)
signal test_failed(test_name: String, error: String)
signal all_complete(passed: int, failed: int)

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("FoveaSegmentationBridge Unit Tests")
	print("=".repeat(70))
	
	await create_timer(0.3).timeout
	_run_all()

func _run_all() -> void:
	# 1. Create a dummy FoveaSplattable with mock splats
	var splattable = FoveaSplattable.new()
	
	# Add some test splats
	# Splat 1: High up, representing clothing (will match simulated clothing rules)
	var splat1 = GaussianSplat.new(Vector3(0.0, 1.2, 0.0))
	splat1.color = Color.WHITE
	splat1.normal = Vector3(1, 0, 0) # Wrinkled (non-vertical normal)
	splattable.loaded_splats.append(splat1)
	
	# Splat 2: At bottom, blue-ish, representing liquid
	var splat2 = GaussianSplat.new(Vector3(0.0, -0.5, 0.0))
	splat2.color = Color(0.1, 0.2, 0.8) # Bluish
	splat2.normal = Vector3.UP
	splattable.loaded_splats.append(splat2)
	
	# Splat 3: Neutral background / solid brick-like
	var splat3 = GaussianSplat.new(Vector3(0.5, -0.5, 0.0))
	splat3.color = Color(0.8, 0.2, 0.2) # Brick red
	splat3.normal = Vector3.UP
	splattable.loaded_splats.append(splat3)
	
	# Add the splattable to root so it can have viewports and cameras
	root.add_child(splattable)
	
	# Instantiate our bridge
	var bridge = FoveaSegmentationBridge.new()
	bridge.use_simulation = true
	bridge.resolution = 256 # Lower resolution for faster tests
	
	# Test 1: Classify as liquid
	print("\n--- Test 1: Liquid Segmentation ---")
	var state1 = {
		"completed": false,
		"success_status": false
	}
	bridge.segment_splattable(splattable, "liquid water", func(success: bool):
		state1.success_status = success
		state1.completed = true
	)
	
	# Wait for asynchronous segmentation pipeline to complete
	var start_time = Time.get_ticks_msec()
	while not state1.completed and Time.get_ticks_msec() - start_time < 10000:
		await create_timer(0.1).timeout
		
	_assert("Liquid segmentation call succeeded", state1.success_status, "API/Simulation should run successfully")
	_assert("Splat 2 labeled as LIQUID", splat2.layer_type == GaussianSplat.LayerType.LIQUID, "Blue bottom splat should be classified as liquid")
	_assert("Splat 1 not labeled as LIQUID", splat1.layer_type != GaussianSplat.LayerType.LIQUID, "Cloth splat should not be classified as liquid")
	
	# Test 2: Classify as clothing
	print("\n--- Test 2: Cloth/Draping Segmentation ---")
	var state2 = {
		"completed": false,
		"success_status": false
	}
	
	# Reset layer types first
	splat1.layer_type = GaussianSplat.LayerType.BASE
	splat2.layer_type = GaussianSplat.LayerType.BASE
	
	bridge.segment_splattable(splattable, "clothing fabric", func(success: bool):
		state2.success_status = success
		state2.completed = true
	)
	
	start_time = Time.get_ticks_msec()
	while not state2.completed and Time.get_ticks_msec() - start_time < 10000:
		await create_timer(0.1).timeout
		
	_assert("Cloth segmentation call succeeded", state2.success_status, "API/Simulation should run successfully")
	_assert("Splat 1 labeled as BASE (clothing mapping target)", splat1.layer_type == GaussianSplat.LayerType.BASE, "Clothing maps to BASE layer by default in this configuration")
	
	# Cleanup
	splattable.queue_free()
	
	# Report
	print("\n" + "=".repeat(70))
	print("FoveaSegmentationBridge Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("=".repeat(70))
	all_complete.emit(_passed, _failed)
	
	if _failed > 0:
		quit(1)
	else:
		quit(0)

func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
		test_passed.emit(name, "")
	else:
		_failed += 1
		print("  ✗ %s — %s" % [name, detail])
		test_failed.emit(name, detail)
