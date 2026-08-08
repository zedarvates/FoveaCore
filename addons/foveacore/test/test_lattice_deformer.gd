extends SceneTree

## Unit tests for FoveaLatticeDeformer and FoveaLatticeAnimator

const FoveaLatticeDeformer = preload("res://addons/foveacore/scripts/advanced/fovea_lattice_deformer.gd")
const FoveaLatticeAnimator = preload("res://addons/foveacore/scripts/advanced/fovea_lattice_animator.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n" + "=======================================================")
	print("FoveaLatticeDeformer & Animator Unit Tests")
	print("=======================================================")
	
	await create_timer(0.1).timeout
	_run_all()
	quit(_failed)

func _run_all() -> void:
	# 1. Create a mock MultiMesh with 1 splat at center
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = QuadMesh.new()
	mm.instance_count = 1
	
	var initial_buffer := PackedFloat32Array()
	initial_buffer.resize(FoveaMultiMeshBulk.stride_of(mm))
	FoveaMultiMeshBulk.write_transform(initial_buffer, 0, Transform3D.IDENTITY)
	mm.buffer = initial_buffer
	
	# 2. Setup Splat Renderer and Lattice Deformer
	var renderer := FoveaCoreSplatRenderer.new()
	root.add_child(renderer)
	renderer.multimesh = mm
	
	var deformer := FoveaLatticeDeformer.new()
	deformer.lattice_size = Vector3(2.0, 2.0, 2.0)
	renderer.add_child(deformer)
	
	# Initial verification (no offset)
	deformer._process(0.016)
	var pos := FoveaMultiMeshBulk.read_transform(mm.buffer, 0).origin
	_assert("Splat at rest position (Vector3.ZERO)", pos.is_equal_approx(Vector3.ZERO), "Expected Vector3.ZERO, got %s" % pos)
	
	# 3. Apply Lattice Cage Offset to top control points (offset +Y by 0.5)
	# Corner indices 2, 3, 6, 7 are +Y (+y in rest is index 2, 3, 6, 7)
	deformer.control_offsets[2] = Vector3(0, 0.5, 0)
	deformer.control_offsets[3] = Vector3(0, 0.5, 0)
	deformer.control_offsets[6] = Vector3(0, 0.5, 0)
	deformer.control_offsets[7] = Vector3(0, 0.5, 0)
	
	deformer._process(0.016)
	pos = FoveaMultiMeshBulk.read_transform(mm.buffer, 0).origin
	# A splat at Y=0 (the middle of the cage) should get deformed by half of the top offsets (0.25)
	_assert_approx("Splat deformed vertically to 0.25 (interpolated)", pos.y, 0.25, 0.01)
	
	# 4. Setup Animator and test Recording / Playback
	var animator := FoveaLatticeAnimator.new()
	deformer.add_child(animator)
	animator.playback_fps = 10.0
	
	animator.start_recording()
	# Record Frame 0
	deformer.control_offsets = [
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
		Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO
	]
	animator.record_keyframe(0.0)
	
	# Record Frame 1 (1.0 second later)
	deformer.control_offsets = [
		Vector3(0, 1.0, 0), Vector3(0, 1.0, 0), Vector3(0, 1.0, 0), Vector3(0, 1.0, 0),
		Vector3(0, 1.0, 0), Vector3(0, 1.0, 0), Vector3(0, 1.0, 0), Vector3(0, 1.0, 0)
	]
	animator.record_keyframe(1.0)
	animator.stop_recording()
	
	_assert("Recorded 2 keyframes", animator._keyframes.size() == 2, "Expected 2 keyframes")
	
	# Playback interpolation check
	animator.play()
	animator._apply_playback_at_time(0.5) # Halfway
	_assert_approx("Animator interpolated offsets at 0.5s", deformer.control_offsets[0].y, 0.5, 0.01)
	
	print("\n=== All Tests Passed: %d / Failed: %d ===" % [_passed, _failed])

func _assert(name: String, condition: bool, error_msg: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s - %s" % [name, error_msg])

func _assert_approx(name: String, val: float, target: float, tolerance: float) -> void:
	if abs(val - target) <= tolerance:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s - Expected around %f, got %f" % [name, target, val])
