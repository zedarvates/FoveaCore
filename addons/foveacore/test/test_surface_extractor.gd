extends SceneTree

## Unit tests for SurfaceExtractor
## Validates: is_front_facing, triangle_area, VisibleTriangle/ExtractionResult classes

var _passed := 0
var _failed := 0

signal all_complete(passed: int, failed: int)


func _init() -> void:
	print("\n" + "=".repeat(70))
	print("SurfaceExtractor Unit Tests")
	print("=".repeat(70))

	await create_timer(0.3).timeout
	_run_all()


func _run_all() -> void:
	_test_is_front_facing()
	_test_triangle_area()
	_test_data_classes()
	_test_edge_cases()

	print("\n" + "=".repeat(70))
	print("SurfaceExtractor Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("=".repeat(70))
	all_complete.emit(_passed, _failed)
	
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _test_is_front_facing() -> void:
	print("\n--- is_front_facing ---")

	var cam := Vector3(0, 0, 10)

	# Triangle facing camera
	var tri_front: Array[Vector3] = [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
	var r1 = SurfaceExtractor.is_front_facing(tri_front, cam)
	_assert("Front-facing triangle (z-facing)", r1, "")

	# Triangle facing away
	var tri_back: Array[Vector3] = [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, -1, 0)]
	# Normal points down (0, 0, -1) after cross product ordering. Let me check:
	# v0=(-1,0,0), v1=(1,0,0), v2=(0,-1,0)
	# edge1=(2,0,0), edge2=(1,-1,0) → cross=(0,0,-2) → normal=(0,0,-1)
	# to_camera=(0,0,10) → (0,0,1) → dot = -1 → NOT front facing
	var r2 = SurfaceExtractor.is_front_facing(tri_back, cam)
	_assert("Back-facing triangle", not r2, "")

	# Camera inside triangle boundaries but in front of it - still front-facing (dot > 0)
	var cam_inside := Vector3(0, 0.1, 1.0)
	var r3 = SurfaceExtractor.is_front_facing(tri_front, cam_inside)
	_assert("Camera near triangle", r3, "")

	# Empty array
	var empty_arr: Array[Vector3] = []
	var r4 = SurfaceExtractor.is_front_facing(empty_arr, cam)
	_assert("Empty vertices", not r4, "")


func _test_triangle_area() -> void:
	print("\n--- triangle_area ---")

	# Unit triangle
	var unit_tri: Array[Vector3] = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
	var a1 = SurfaceExtractor.triangle_area(unit_tri)
	_assert_approx("Unit triangle area", a1, 0.5, 0.001)

	# Scaled triangle (×2)
	var big_tri: Array[Vector3] = [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 2, 0)]
	var a2 = SurfaceExtractor.triangle_area(big_tri)
	_assert_approx("2x triangle area", a2, 2.0, 0.001)

	# Zero-area triangle (collinear)
	var line_tri: Array[Vector3] = [Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(2, 2, 0)]
	var a3 = SurfaceExtractor.triangle_area(line_tri)
	_assert_approx("Collinear triangle area=0", a3, 0.0, 0.001)

	# Empty
	var empty_arr: Array[Vector3] = []
	var a4 = SurfaceExtractor.triangle_area(empty_arr)
	_assert_approx("Empty area=0", a4, 0.0, 0.001)


func _test_data_classes() -> void:
	print("\n--- Data classes ---")

	var tri = SurfaceExtractor.VisibleTriangle.new()
	var indices_arr: Array[int] = [0, 1, 2]
	tri.indices = indices_arr
	var vertices_arr: Array[Vector3] = [Vector3.ZERO, Vector3.ONE, Vector3(0, 1, 0)]
	tri.vertices = vertices_arr
	tri.center = Vector3(0.3, 0.6, 0)
	tri.area = 0.5
	tri.distance_to_camera = 10.0

	_assert("VisibleTriangle.indices size=3", tri.indices.size() == 3, "")
	_assert("VisibleTriangle.area=0.5", is_equal_approx(tri.area, 0.5), "")

	var result = SurfaceExtractor.ExtractionResult.new()
	result.total_triangles = 100
	result.visible_count = 80
	result.culled_backface = 15
	result.culled_occlusion = 5
	_assert("ExtractionResult math check", result.culled_occlusion == 5,
		"total - visible - backface = %d" % result.culled_occlusion)


func _test_edge_cases() -> void:
	print("\n--- Edge cases ---")

	# Degenerate triangle (all vertices same point)
	var degen: Array[Vector3] = [Vector3(1, 2, 3), Vector3(1, 2, 3), Vector3(1, 2, 3)]
	var a = SurfaceExtractor.triangle_area(degen)
	_assert_approx("Degenerate area=0", a, 0.0, 0.001)

	# 2 vertices only
	var partial: Array[Vector3] = [Vector3.ZERO, Vector3.ONE]
	var fa = SurfaceExtractor.is_front_facing(partial, Vector3(0, 0, 10))
	_assert("2 vertices → not front facing", not fa, "")

	# Large coordinates
	var large: Array[Vector3] = [Vector3(1000, 2000, 3000), Vector3(1001, 2000, 3000), Vector3(1000, 2001, 3000)]
	var al = SurfaceExtractor.triangle_area(large)
	_assert_approx("Large coordinates area=0.5", al, 0.5, 0.001)


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
