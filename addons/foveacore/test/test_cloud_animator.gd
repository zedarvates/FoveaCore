extends SceneTree

## Unit tests for FoveaCloudAnimator

const FoveaCloudAnimator = preload("res://addons/foveacore/scripts/advanced/fovea_cloud_animator.gd")

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n" + "=======================================================")
	print("FoveaCloudAnimator Unit Tests")
	print("=======================================================")
	
	await create_timer(0.1).timeout
	_run_all()
	quit(_failed)

func _run_all() -> void:
	# 1. Create mock MultiMesh
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = 1
	
	var initial_buffer := PackedFloat32Array()
	initial_buffer.resize(FoveaMultiMeshBulk.stride_of(mm))
	FoveaMultiMeshBulk.write_transform(initial_buffer, 0, Transform3D(Basis(), Vector3(0.5, 0.5, 0.5)))
	FoveaMultiMeshBulk.write_color(initial_buffer, 12, Color.WHITE)
	mm.buffer = initial_buffer
	
	# 2. Setup Splat Renderer and Cloud Animator
	var renderer := FoveaCoreSplatRenderer.new()
	root.add_child(renderer)
	renderer.multimesh = mm
	
	var animator := FoveaCloudAnimator.new()
	animator.cycle_duration = 10.0
	animator.wind_direction = Vector3(1.0, 0.0, 0.0)
	animator.wind_speed = 2.0
	animator.turbulence_strength = 0.0
	animator.dissipation_spread = 5.0
	renderer.add_child(animator)
	
	# Sync transforms
	animator._process(0.0)
	
	# Phase 1: Creation (e.g. t = 1.0s, phase = 0.1)
	animator._time = 1.0
	animator._process(0.0)
	var custom_data := FoveaMultiMeshBulk.read_color(mm.buffer, 12)
	_assert("Opacity faded in partially during Creation", custom_data.a > 0.0 and custom_data.a < 1.0, "Expected alpha between 0 and 1, got %f" % custom_data.a)
	
	# Phase 2: Drift (e.g. t = 5.0s, phase = 0.5)
	animator._time = 5.0
	animator._process(0.0)
	var pos := FoveaMultiMeshBulk.read_transform(mm.buffer, 0).origin
	_assert("Splat drifted along wind direction (X axis)", pos.x > 0.5, "Expected drift in X direction, got position %s" % pos)
	
	# Phase 3: Dissipation (e.g. t = 9.0s, phase = 0.9)
	animator._time = 9.0
	animator._process(0.0)
	custom_data = FoveaMultiMeshBulk.read_color(mm.buffer, 12)
	_assert("Opacity faded out during Dissipation", custom_data.a < 0.8, "Expected alpha faded out, got %f" % custom_data.a)
	
	print("\n=== All Tests Passed: %d / Failed: %d ===" % [_passed, _failed])

func _assert(name: String, condition: bool, error_msg: String = "") -> void:
	if condition:
		_passed += 1
		print("[PASS] %s" % name)
	else:
		_failed += 1
		print("[FAIL] %s - %s" % [name, error_msg])
