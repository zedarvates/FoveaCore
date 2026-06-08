extends SceneTree

## Unit tests for FoveaSplatCloth3D
## Validates Verlet integration, distance constraints, gravity,
## and bulk MultiMesh transform updates.

const FoveaSplatCloth3D = preload("res://addons/foveacore/scripts/advanced/fovea_splat_cloth.gd")

var _passed := 0
var _failed := 0

signal test_passed(test_name: String, details: String)
signal test_failed(test_name: String, error: String)
signal all_complete(passed: int, failed: int)

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("FoveaSplatCloth3D Unit Tests")
	print("=".repeat(70))
	
	await create_timer(0.3).timeout
	_run_all()

func _run_all() -> void:
	# 1. Create a mock FoveaSplattable
	var splattable = FoveaSplattable.new()
	root.add_child(splattable)
	
	# Instantiate mock splats
	var splat1 = GaussianSplat.new(Vector3(-0.5, 0.0, 0.0))
	var splat2 = GaussianSplat.new(Vector3(0.0, 0.0, 0.0))
	var splat3 = GaussianSplat.new(Vector3(0.5, 0.0, 0.0))
	splattable.loaded_splats.append(splat1)
	splattable.loaded_splats.append(splat2)
	splattable.loaded_splats.append(splat3)
	
	# Create and attach a mock MultiMeshInstance3D
	var mm_inst = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 3
	
	# Set initial identities for MultiMesh transforms
	var xf_arr = PackedVector3Array()
	xf_arr.resize(12) # 3 instances * 4 Vector3s
	for i in range(3):
		xf_arr[i * 4] = Vector3.RIGHT
		xf_arr[i * 4 + 1] = Vector3.UP
		xf_arr[i * 4 + 2] = Vector3.BACK
		# Splat positions start at origin
		xf_arr[i * 4 + 3] = splattable.loaded_splats[i].position
	mm.transform_array = xf_arr
	
	mm_inst.multimesh = mm
	splattable.add_child(mm_inst)
	
	# 2. Instantiate FoveaSplatCloth3D
	var cloth = FoveaSplatCloth3D.new()
	cloth.splattable = splattable
	cloth.enable_internal_sim = true
	cloth.grid_size = Vector2i(4, 4) # 16 points
	cloth.grid_dimensions = Vector2(1.0, 1.0)
	cloth.anchor_points = [0, 3] # Pinned top corners
	cloth.gravity = Vector3(0, -10.0, 0) # Simple gravity
	cloth.damping = 0.0
	cloth.stiffness = 1.0
	
	splattable.add_child(cloth)
	
	# Run first process loop to let it initialize and bind
	cloth._process(0.016)
	
	_assert("Splats bound to cloth simulation", cloth._is_bound, "Binding should succeed on first process frame")
	_assert("Bindings list size matches splat count", cloth._bindings.size() == 3, "All 3 splats should be bound")
	
	# Capture initial positions of the simulation points
	var p_pinned = cloth._points[0].pos
	var p_free = cloth._points[12].pos # Bottom row
	
	# 3. Simulate 10 physics steps under gravity
	var dt = 0.016
	for step in range(10):
		cloth._physics_process(dt)
		
	# Update bindings
	cloth._update_internal_sim_binding()
	
	# Assertions
	var p_pinned_after = cloth._points[0].pos
	var p_free_after = cloth._points[12].pos
	
	_assert_approx("Pinned point remained stationary in space", p_pinned.y, p_pinned_after.y, 0.01)
	_assert("Free point fell down under gravity", p_free_after.y < p_free.y, "Free point should fall")
	
	# Retrieve updated MultiMesh transforms
	var updated_xf = mm.transform_array
	var s1_pos = updated_xf[3] # Splat 1 position
	var s2_pos = updated_xf[7] # Splat 2 position
	var s3_pos = updated_xf[11] # Splat 3 position
	
	_assert("Splat transforms in MultiMesh updated", s1_pos != splat1.position or s2_pos != splat2.position, "MultiMesh coordinates should shift")
	
	# Cleanup
	splattable.queue_free()
	
	# Report
	print("\n" + "=".repeat(70))
	print("FoveaSplatCloth3D Tests: %d passed, %d failed (%.0f%%)" % [
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

func _assert_approx(name: String, val: float, target: float, tol: float) -> void:
	if abs(val - target) <= tol:
		_passed += 1
		print("  ✓ %s (%.4f ≈ %.4f)" % [name, val, target])
		test_passed.emit(name, "")
	else:
		_failed += 1
		print("  ✗ %s — %.4f ≠ %.4f ±%.4f" % [name, val, target, tol])
		test_failed.emit(name, "Not approximate")
