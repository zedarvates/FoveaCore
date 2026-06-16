extends SceneTree

## Unit tests for TemporalReprojector (Task 86)
## Validates: fade-in/fade-out, invalidation on movement, history limits, and missing splat generation.

var _passed := 0
var _failed := 0

class MockTriangle:
	var vertices: Array
	var normals: Array
	var area: float

func _init() -> void:
	print("\n======================================================================")
	print("TemporalReprojector (Task 86) Unit Tests")
	print("======================================================================")
	
	# Disable autoload loops to avoid printing warnings/errors in dummy/headless mode
	var mgr = root.get_node_or_null("FoveaCoreManager")
	if mgr:
		mgr.set_process(false)
		mgr.set_physics_process(false)
		print("FoveaCoreManager processing disabled for unit tests.")

	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	var reprojector = TemporalReprojector.new()
	root.add_child(reprojector)

	var dummy_node = RefCounted.new()

	# --- Test 1: Configuration & Default Values ---
	print("\n--- Test 1: Configuration & Default Values ---")
	_assert("max_history_frames defaults to 8", reprojector.config.max_history_frames == 8)
	_assert("fade_in_frames defaults to 2", reprojector.config.fade_in_frames == 2)
	_assert("fade_out_frames defaults to 4", reprojector.config.fade_out_frames == 4)
	_assert("motion_threshold defaults to 0.05", is_equal_approx(reprojector.config.motion_threshold, 0.05))

	# --- Test 2: Initial Reprojection & Missing Splat Generation ---
	print("\n--- Test 2: Initial Reprojection & Missing Splats ---")
	var tri1 = MockTriangle.new()
	tri1.vertices = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]
	tri1.normals = [Vector3.BACK]
	tri1.area = 0.5

	var result1 = reprojector.reproject_splats(
		dummy_node,
		[],
		Vector3(0, 0, 5), # Camera pos
		Vector3(0, 0, 5), # Prev Camera pos
		[tri1]
	)

	_assert("Result1 contains 1 splat generated from triangle", result1.size() == 1)
	if result1.size() > 0:
		var s = result1[0]
		_assert("Splat position is center of triangle", s.position.is_equal_approx(Vector3(1.0/3.0, 1.0/3.0, 0)))
		_assert("Splat normal is aligned with triangle", s.normal.is_equal_approx(Vector3.BACK))

	var stats1 = reprojector.get_stats()
	_assert("Stats show 1 total in history", stats1["total_in_history"] == 1)
	_assert("Stats show 1 new generated", stats1["new_generated"] == 1)
	_assert("Stats show 0 reprojected", stats1["reprojected"] == 0)

	# --- Test 3: Fade-In and Age Increment ---
	print("\n--- Test 3: Fade-In and Age Increment ---")
	# Run a second frame. The splat from history should be reprojected.
	# With fade_in_frames = 2 and age = 1 (first reprojected frame),
	# age = 1 -> fade factor = age / fade_in_frames = 0.5.
	var result2 = reprojector.reproject_splats(
		dummy_node,
		[],
		Vector3(0, 0, 5),
		Vector3(0, 0, 5),
		[] # No new triangles
	)

	_assert("Result2 contains 1 reprojected splat", result2.size() == 1)
	if result2.size() > 0:
		var s = result2[0]
		# Initial opacity is 0.8 from create_from_triangle, * 0.5 fade factor = 0.4
		_assert("Splat opacity is faded in by 50% (0.4)", is_equal_approx(s.opacity, 0.4))

	var stats2 = reprojector.get_stats()
	_assert("Stats show 1 reprojected splat", stats2["reprojected"] == 1)
	_assert("Stats show 0 new generated", stats2["new_generated"] == 0)

	# --- Test 4: Motion Invalidation ---
	print("\n--- Test 4: Motion Invalidation ---")
	# If camera moves by more than motion_threshold * age, the splat is invalidated.
	# reprojector.config.motion_threshold = 0.05.
	# age is now 2. threshold limit is 0.05 * 2 = 0.1.
	# Let's move camera by 0.3 (> 0.1).
	var result3 = reprojector.reproject_splats(
		dummy_node,
		[],
		Vector3(0, 0.3, 5), # Moved camera by 0.3 along Y
		Vector3(0, 0, 5),
		[]
	)

	_assert("Reprojected splat is invalidated due to motion", result3.is_empty())
	var stats3 = reprojector.get_stats()
	_assert("Stats show 1 expired splat", stats3["expired"] == 1)
	_assert("Stats show 0 reprojected", stats3["reprojected"] == 0)

	# --- Test 5: Fade-Out and History Limit Expiration ---
	print("\n--- Test 5: Fade-Out and Expiration ---")
	reprojector.clear()
	reprojector.config.max_history_frames = 5
	reprojector.config.fade_in_frames = 1
	reprojector.config.fade_out_frames = 2

	# Seed 1 splat
	reprojector.reproject_splats(dummy_node, [], Vector3.ZERO, Vector3.ZERO, [tri1])

	# Frame 1: age = 1 (age incremented from 0 -> 1)
	# Frame 2: age = 2
	# Frame 3: age = 3 (remaining = 5 - 3 = 2 < fade_out_frames(2) -> fade = 2 / 2 = 1.0)
	# Frame 4: age = 4 (remaining = 5 - 4 = 1 < fade_out_frames(2) -> fade = 1 / 2 = 0.5)
	# Frame 5: age = 5 (remaining = 5 - 5 = 0 < fade_out_frames(2) -> fade = 0 / 2 = 0.0 -> expired)

	# Frame 1
	var r_f1 = reprojector.reproject_splats(dummy_node, [], Vector3.ZERO, Vector3.ZERO, [])
	_assert("Frame 1 reprojected opacity matches full opacity (0.8)", is_equal_approx(r_f1[0].opacity, 0.8))

	# Frame 2
	var r_f2 = reprojector.reproject_splats(dummy_node, [], Vector3.ZERO, Vector3.ZERO, [])
	_assert("Frame 2 reprojected opacity matches full opacity (0.8)", is_equal_approx(r_f2[0].opacity, 0.8))

	# Frame 3
	var r_f3 = reprojector.reproject_splats(dummy_node, [], Vector3.ZERO, Vector3.ZERO, [])
	_assert("Frame 3 reprojected opacity is still full (0.8)", is_equal_approx(r_f3[0].opacity, 0.8))

	# Frame 4
	var r_f4 = reprojector.reproject_splats(dummy_node, [], Vector3.ZERO, Vector3.ZERO, [])
	# fade = (5 - 4) / 2 = 0.5 -> opacity = 0.8 * 0.5 = 0.4
	_assert("Frame 4 reprojected opacity is faded out by 50% (0.4)", is_equal_approx(r_f4[0].opacity, 0.4))

	# Frame 5
	var r_f5 = reprojector.reproject_splats(dummy_node, [], Vector3.ZERO, Vector3.ZERO, [])
	_assert("Frame 5 splat is expired and not reprojected", r_f5.is_empty())

	# Cleanup
	reprojector.queue_free()
	_finish()

func _finish() -> void:
	print("\n======================================================================")
	print("TemporalReprojector Tests: %d passed, %d failed (%.0f%%)" % [
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
