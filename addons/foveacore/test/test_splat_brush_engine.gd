extends SceneTree

## Unit tests for SplatBrushEngine (Tasks 57 & 79)
## Validates: BrushMode.SCALE, Undo/Redo stack, Stroke begin/commit lifecycle, and Max Undo depth constraint.

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n======================================================================")
	print("SplatBrushEngine (Tasks 57 & 79) Unit Tests")
	print("======================================================================")
	
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	# Setup test node
	var splattable = FoveaSplattable.new()
	splattable.name = "TestSplattable"
	root.add_child(splattable)

	# Setup a few test splats
	var splat1 = GaussianSplat.new()
	splat1.position = Vector3(0.0, 0.0, 0.0)
	splat1.color = Color.WHITE
	splat1.opacity = 1.0
	splat1.normal = Vector3.UP
	splat1.scale = Vector3(1.0, 1.0, 1.0)
	
	var splat2 = GaussianSplat.new()
	splat2.position = Vector3(0.1, 0.1, 0.1)
	splat2.color = Color.WHITE
	splat2.opacity = 1.0
	splat2.normal = Vector3.UP
	splat2.scale = Vector3(1.0, 1.0, 1.0)

	var splats_array: Array[GaussianSplat] = [splat1, splat2]
	splattable.loaded_splats = splats_array

	# Setup SplatBrushEngine
	var brush_engine = SplatBrushEngine.new()
	brush_engine.brush_radius = 0.5
	brush_engine.brush_color = Color.RED
	brush_engine.brush_opacity = 0.5
	brush_engine.brush_scale_factor = 2.0
	root.add_child(brush_engine)

	# --- Test 1: BrushMode.SCALE ---
	print("\n--- Test 1: BrushMode.SCALE ---")
	brush_engine.brush_mode = SplatBrushEngine.BrushMode.SCALE
	
	# Apply brush in SCALE mode. This should trigger a fallback/dynamic single-frame stroke because _is_in_stroke is false.
	# Hit position is (0.0, 0.0, 0.0). Both splats are within 0.5 radius.
	var success = brush_engine.apply_brush(splattable, Vector3.ZERO)
	_assert("Brush application returned true (modified splats)", success)
	_assert("Splat 1 scale multiplied by 2.0", splat1.scale.is_equal_approx(Vector3(2.0, 2.0, 2.0)))
	_assert("Splat 2 scale multiplied by 2.0", splat2.scale.is_equal_approx(Vector3(2.0, 2.0, 2.0)))
	# Also verify that a single-frame stroke was committed to the undo stack
	_assert("Undo stack has 1 entry", brush_engine._undo_stack.size() == 1)

	# --- Test 2: Undo & Redo on dynamic/fallback stroke ---
	print("\n--- Test 2: Undo & Redo on dynamic/fallback stroke ---")
	var undo_success = brush_engine.undo()
	_assert("Undo returned true", undo_success)
	_assert("Splat 1 scale restored to 1.0", splat1.scale.is_equal_approx(Vector3(1.0, 1.0, 1.0)))
	_assert("Splat 2 scale restored to 1.0", splat2.scale.is_equal_approx(Vector3(1.0, 1.0, 1.0)))
	_assert("Undo stack is empty", brush_engine._undo_stack.is_empty())
	_assert("Redo stack has 1 entry", brush_engine._redo_stack.size() == 1)
	
	var redo_success = brush_engine.redo()
	_assert("Redo returned true", redo_success)
	_assert("Splat 1 scale reapplied to 2.0", splat1.scale.is_equal_approx(Vector3(2.0, 2.0, 2.0)))
	_assert("Splat 2 scale reapplied to 2.0", splat2.scale.is_equal_approx(Vector3(2.0, 2.0, 2.0)))
	_assert("Undo stack has 1 entry again", brush_engine._undo_stack.size() == 1)
	_assert("Redo stack is empty", brush_engine._redo_stack.is_empty())

	# --- Test 3: Continuous stroke lifecycle (begin_stroke / commit_stroke) ---
	print("\n--- Test 3: Continuous stroke lifecycle ---")
	# Reset splats to base
	splat1.scale = Vector3(1.0, 1.0, 1.0)
	splat1.color = Color.WHITE
	splat2.scale = Vector3(1.0, 1.0, 1.0)
	splat2.color = Color.WHITE
	brush_engine._undo_stack.clear()
	brush_engine._redo_stack.clear()
	
	# Start a continuous stroke
	brush_engine.begin_stroke(splattable)
	_assert("Brush engine is in stroke", brush_engine._is_in_stroke)
	
	# First frame of painting: PAINT mode with Color.RED
	brush_engine.brush_mode = SplatBrushEngine.BrushMode.PAINT
	brush_engine.brush_color = Color.RED
	brush_engine.apply_brush(splattable, Vector3.ZERO)
	
	_assert("Splat 1 painted RED", splat1.color == Color.RED)
	_assert("Splat 2 painted RED", splat2.color == Color.RED)
	_assert("Undo stack still empty (stroke not committed yet)", brush_engine._undo_stack.is_empty())
	
	# Second frame of painting: PAINT mode with Color.BLUE (same stroke)
	brush_engine.brush_color = Color.BLUE
	brush_engine.apply_brush(splattable, Vector3.ZERO)
	
	_assert("Splat 1 painted BLUE", splat1.color == Color.BLUE)
	_assert("Splat 2 painted BLUE", splat2.color == Color.BLUE)
	_assert("Undo stack still empty (stroke not committed yet)", brush_engine._undo_stack.is_empty())
	
	# Commit stroke
	brush_engine.commit_stroke()
	_assert("Brush engine is no longer in stroke", not brush_engine._is_in_stroke)
	_assert("Undo stack has 1 entry", brush_engine._undo_stack.size() == 1)
	
	# Undo the continuous stroke
	# This should restore both splats to their initial state (Color.WHITE), NOT Color.RED!
	undo_success = brush_engine.undo()
	_assert("Undo continuous stroke returned true", undo_success)
	_assert("Splat 1 restored to original WHITE", splat1.color == Color.WHITE)
	_assert("Splat 2 restored to original WHITE", splat2.color == Color.WHITE)
	
	# Redo the continuous stroke
	# This should reapply the final state of the stroke (Color.BLUE)
	redo_success = brush_engine.redo()
	_assert("Redo continuous stroke returned true", redo_success)
	_assert("Splat 1 reapplied to final BLUE", splat1.color == Color.BLUE)
	_assert("Splat 2 reapplied to final BLUE", splat2.color == Color.BLUE)

	# --- Test 4: Max Undo depth limit ---
	print("\n--- Test 4: Max Undo depth limit ---")
	brush_engine._undo_stack.clear()
	brush_engine._redo_stack.clear()
	brush_engine._max_undo_depth = 5
	
	for i in range(10):
		# Perform a simple stroke
		brush_engine.begin_stroke(splattable)
		brush_engine.brush_color = Color(float(i) / 10.0, 0.0, 0.0)
		brush_engine.apply_brush(splattable, Vector3.ZERO)
		brush_engine.commit_stroke()
		
	_assert("Undo stack size clamped to max depth (5)", brush_engine._undo_stack.size() == 5)

	# Cleanup
	splattable.queue_free()
	brush_engine.queue_free()
	
	_finish()

func _finish() -> void:
	print("\n======================================================================")
	print("SplatBrushEngine Tests: %d passed, %d failed (%.0f%%)" % [
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
