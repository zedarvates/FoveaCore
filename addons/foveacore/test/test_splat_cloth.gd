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
	var anchors: Array[int] = [0, 3]
	cloth.anchor_points = anchors
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
		
	# 4. Appliquer un écrasement localisé et faire tourner la physique
	cloth.apply_crush(Vector3(-0.5, 0.0, 0.0), 1.0, 50.0)
	cloth._physics_process(dt)
		
	# Update bindings
	cloth._update_internal_sim_binding()
	
	# Assertions
	var p_pinned_after = cloth._points[0].pos
	var p_free_after = cloth._points[12].pos
	
	_assert_approx("Pinned point remained stationary in space", p_pinned.y, p_pinned_after.y, 0.01)
	_assert("Free point fell down under gravity", p_free_after.y < p_free.y, "Free point should fall")
	
	# Vérifier que la déformation s'est bien activée et s'est propagée
	var def_x: float = cloth._points[0]["deformation_x"]
	_assert("Point de controle deformation_x > 0 après apply_crush", def_x > 0.0, "La déformation locale doit être activée")
	
	# Retrieve updated MultiMesh transforms from buffer
	var updated_buf: PackedFloat32Array = mm.buffer
	var stride := FoveaMultiMeshBulk.stride_of(mm)
	
	var s1_basis_x := Vector3(updated_buf[0], updated_buf[4], updated_buf[8])
	var s1_basis_z := Vector3(updated_buf[2], updated_buf[6], updated_buf[10])
	var s1_pos := Vector3(updated_buf[3], updated_buf[7], updated_buf[11])
	
	var s2_pos := Vector3(updated_buf[1 * stride + 3], updated_buf[1 * stride + 7], updated_buf[1 * stride + 11])
	
	_assert("Splat transforms in MultiMesh updated", s1_pos != splat1.position or s2_pos != splat2.position, "MultiMesh coordinates should shift")
	
	# Vérifier que la base (scale/rotation) a été déformée par le squish/Poisson
	_assert("Splat scale Z compressé par l'écrasement", s1_basis_z.length() < 1.0, "La dimension sur l'axe normal Z doit être écrasée (< 1.0)")
	_assert("Splat scale X étiré par l'effet de Poisson", s1_basis_x.length() > 1.0, "La dimension sur l'axe tangent X doit gonfler (> 1.0)")
	
	# 5. Test Manual Sphere Cutting
	var counts := {
		"sphere": 0,
		"line": 0,
		"tension": 0
	}
	var sphere_broken_callback = func(idx: int, p1: int, p2: int, cause: String):
		if cause == "cut_sphere":
			counts["sphere"] += 1
	cloth.spring_broken.connect(sphere_broken_callback)
	
	# Point 0 is at local (-0.5, 0, 0) relative to global_transform.
	# Let's cut around the center (0, 0, 0)
	var center_cut = cloth.global_transform * Vector3(0.0, 0.0, 0.0)
	cloth.cut_cloth_sphere(center_cut, 0.4)
	
	_assert("Sphere cut broke some springs", counts["sphere"] > 0, "Spherical cut should snap intersecting springs")
	cloth.spring_broken.disconnect(sphere_broken_callback)
	
	# 6. Test Manual Line Segment Cutting
	var line_broken_callback = func(idx: int, p1: int, p2: int, cause: String):
		if cause == "cut_line":
			counts["line"] += 1
	cloth.spring_broken.connect(line_broken_callback)
	
	# Find an active spring
	var target_spring_idx := -1
	for s_idx in range(cloth._springs.size()):
		if cloth._springs[s_idx].get("active", true):
			target_spring_idx = s_idx
			break
			
	if target_spring_idx != -1:
		var sp = cloth._springs[target_spring_idx]
		var p1_pos: Vector3 = cloth._points[sp.p1].pos
		var p2_pos: Vector3 = cloth._points[sp.p2].pos
		var mid_pos := (p1_pos + p2_pos) * 0.5
		
		# Define line segment intersecting the spring transversely
		var l_start := mid_pos + Vector3(0, 0, -0.2)
		var l_end := mid_pos + Vector3(0, 0, 0.2)
		cloth.cut_cloth_line(l_start, l_end, 0.05)
		
		_assert("Line cut broke the target spring", not sp.get("active", true), "The targeted spring should be deactivated by the line segment")
		_assert("Line cut emitted signal", counts["line"] > 0, "Signal should be emitted for line cut")
	else:
		_assert("Line cut test skipped (no active springs left)", true, "")
		
	cloth.spring_broken.disconnect(line_broken_callback)
	
	# 7. Test Tension Tearing
	cloth.enable_tearing = true
	cloth.tear_threshold = 1.1 # 10% elongation snaps
	
	var tension_broken_callback = func(idx: int, p1: int, p2: int, cause: String):
		if cause == "tension":
			counts["tension"] += 1
	cloth.spring_broken.connect(tension_broken_callback)
	
	# Manually stretch non-anchored bottom corner points 12 and 15 far apart to trigger massive tension
	cloth._points[12].pos = cloth.global_transform * Vector3(-5.0, -1.0, 0.0)
	cloth._points[15].pos = cloth.global_transform * Vector3(5.0, -1.0, 0.0)
	
	# Run physics process step to evaluate distance constraints and check for tears
	cloth._physics_process(0.016)
	
	_assert("Tension tearing broke springs", counts["tension"] > 0, "Highly stretched springs should snap under tension")
	cloth.spring_broken.disconnect(tension_broken_callback)
	
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
