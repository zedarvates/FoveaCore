extends SceneTree

## Unit tests for Splat Layers and SplatLightingAnimator
## Validates: GaussianSplat dynamic fields, SplatLightingAnimator math, and subsystem offset mapping.

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n" + "======================================================================")
	print("Splat Layers & SplatLightingAnimator Unit Tests")
	print("======================================================================")
	
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	# --- Test 1: GaussianSplat fields and serialization ---
	print("\n--- Test 1: GaussianSplat fields & serialization ---")
	var splat = GaussianSplat.new()
	splat.position = Vector3(1.0, 2.0, 3.0)
	splat.normal = Vector3.UP
	splat.surface_normal = Vector3.UP
	splat.layer_type = GaussianSplat.LayerType.SHADOW
	splat.brush_type = GaussianSplat.BrushType.STONE
	splat.origin_offset = Vector3(0.1, -0.2, 0.3)
	
	var serialized = splat.to_dict()
	_assert("Serialized dict contains surface_normal", serialized.has("surface_normal"))
	_assert("Serialized dict contains origin_offset", serialized.has("origin_offset"))
	_assert("Serialized dict contains layer_type", serialized.has("layer_type"))
	_assert("Serialized dict contains brush_type", serialized.has("brush_type"))
	
	var loaded_splat = GaussianSplat.new()
	loaded_splat.from_dict(serialized)
	_assert("Deserialized position matches", loaded_splat.position.is_equal_approx(splat.position))
	_assert("Deserialized surface_normal matches", loaded_splat.surface_normal.is_equal_approx(splat.surface_normal))
	_assert("Deserialized origin_offset matches", loaded_splat.origin_offset.is_equal_approx(splat.origin_offset))
	_assert("Deserialized layer_type matches", loaded_splat.layer_type == splat.layer_type)
	_assert("Deserialized brush_type matches", loaded_splat.brush_type == splat.brush_type)

	# --- Test 2: SplatLightingAnimator dynamic calculations ---
	print("\n--- Test 2: SplatLightingAnimator calculations ---")
	var animator = SplatLightingAnimator.new()
	animator.shadow_offset_multiplier = 0.5
	animator.highlight_intensity = 1.0
	
	var splattable = FoveaSplattable.new()
	
	var shadow_splat = GaussianSplat.new()
	shadow_splat.position = Vector3(0.0, 0.0, 0.0)
	shadow_splat.normal = Vector3.UP
	shadow_splat.surface_normal = Vector3.UP
	shadow_splat.layer_type = GaussianSplat.LayerType.SHADOW
	
	var light_splat = GaussianSplat.new()
	light_splat.position = Vector3(0.0, 0.0, 0.0)
	light_splat.normal = Vector3.UP
	light_splat.surface_normal = Vector3.UP
	light_splat.layer_type = GaussianSplat.LayerType.LIGHT
	
	var sat_splat = GaussianSplat.new()
	sat_splat.position = Vector3(0.0, 0.0, 0.0)
	sat_splat.normal = Vector3.UP
	sat_splat.surface_normal = Vector3.UP
	sat_splat.layer_type = GaussianSplat.LayerType.SATURATION
	
	var splats_array: Array[GaussianSplat] = [shadow_splat, light_splat, sat_splat]
	splattable.loaded_splats = splats_array
	root.add_child(splattable)
	root.add_child(animator)
	
	# Light direction pointing downwards: Vector3(0, -1, 0)
	# This means -light_dir is Vector3(0, 1, 0), which aligns perfectly with surface_normal Vector3.UP.
	var light_dir = Vector3(0.0, -1.0, 0.0)
	animator._animate_splat_layers(light_dir)
	
	# SHADOW offset: should be opposite of projected light direction.
	# light_dir.project(UP) = Vector3(0, -1, 0)
	# offset = project(...) * 0.5 = Vector3(0, -0.5, 0)
	# splat.origin_offset = -offset = Vector3(0, 0.5, 0)
	_assert("Shadow splat origin_offset moved opposite to light", shadow_splat.origin_offset.is_equal_approx(Vector3(0, 0.5, 0)))
	
	# LIGHT opacity: alignment with -light_dir is UP.dot(UP) = 1.0.
	# opacity = 1.0 * highlight_intensity (1.0) = 1.0.
	_assert("Light splat opacity is fully aligned", is_equal_approx(light_splat.opacity, 1.0))
	
	# SATURATION opacity: alignment with -light_dir is 1.0.
	_assert("Saturation splat opacity is fully aligned", is_equal_approx(sat_splat.opacity, 1.0))
	
	# Now light direction pointing sideways (perpendicular to UP): Vector3(1, 0, 0)
	# UP.dot(-light_dir) = 0.0
	light_dir = Vector3(1.0, 0.0, 0.0)
	animator._animate_splat_layers(light_dir)
	
	_assert("Light splat opacity is culled (no alignment)", is_equal_approx(light_splat.opacity, 0.0))
	_assert("Saturation splat opacity is at peripheral limit (0.5)", is_equal_approx(sat_splat.opacity, 0.5))

	# --- Test 3: Subsystem Offset Mapping ---
	print("\n--- Test 3: Subsystem Offset Mapping ---")
	var subsystem = FoveaSplatSubsystem.new()
	subsystem.setup(1.0, 100)
	subsystem.temporal_reprojector = TemporalReprojector.new()
	subsystem.temporal_reprojector.config.reproject_ratio = 0.0 # Force reconstruction/loading
	root.add_child(subsystem.temporal_reprojector)
	
	# Setup visibility results
	var extraction = {
		"visible_triangles": []
	}
	var visibility_result = {
		"per_node_results": {
			splattable: extraction
		}
	}
	
	splattable.has_ply_splats = true
	# Reset splat offsets and colors
	shadow_splat.position = Vector3(1, 2, 3)
	shadow_splat.origin_offset = Vector3(0.5, 0, -0.5)
	
	var camera = Camera3D.new()
	root.add_child(camera)
	
	# Run frame processing
	subsystem.process_frame(visibility_result, camera, Vector3.ZERO)
	
	# Check generated current_splats
	_assert("Subsystem generated current splats", subsystem.current_splats.size() > 0)
	if subsystem.current_splats.size() > 0:
		# The subsystem now performs the renderer-required back-to-front sort, so
		# source index zero is no longer a stable assertion target.
		var final_splat: GaussianSplat = null
		for candidate: GaussianSplat in subsystem.current_splats:
			if candidate.layer_type == GaussianSplat.LayerType.SHADOW:
				final_splat = candidate
				break
		_assert("Subsystem copied LayerType", final_splat != null)
		if final_splat == null:
			_finish()
			return
		# Position should be position + origin_offset
		# (transformed by identity since splattable is at origin)
		var expected_pos = Vector3(1.5, 2.0, 2.5)
		_assert("Subsystem applied origin_offset to final splat position", final_splat.position.is_equal_approx(expected_pos))
	
	# --- Test 4: Auto-connection to Godot light source ---
	print("\n--- Test 4: Auto-connection to Godot light source ---")
	var auto_animator: SplatLightingAnimator = SplatLightingAnimator.new()
	var test_light: DirectionalLight3D = DirectionalLight3D.new()
	test_light.name = "TestDirectionalLight"
	test_light.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0) # pointing straight down
	
	root.add_child(test_light)
	root.add_child(auto_animator)
	
	# Force process tick to trigger _auto_discover_light
	auto_animator._process(0.01)
	
	_assert("Animator automatically discovered DirectionalLight3D", auto_animator.main_light == test_light)
	
	# Cleanup Test 4
	test_light.queue_free()
	auto_animator.queue_free()
	
	# Cleanup
	splattable.queue_free()
	animator.queue_free()
	camera.queue_free()
	subsystem.temporal_reprojector.queue_free()
	subsystem.queue_free()
	
	_finish()

func _finish() -> void:
	print("\n" + "======================================================================")
	print("Splat Layers Tests: %d passed, %d failed (%.0f%%)" % [
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
