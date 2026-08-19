extends SceneTree

## Unit tests for Specular Reflections (Dynamic Lighting)
## Validates:
## 1. Material uniform updates on FoveaCoreSplatRenderer.
## 2. Material uniform updates on FoveaInstancedSplatRenderer.
## 3. CPU specular calculations in SplatLightingAnimator under varying view/light configurations.

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n" + "======================================================================")
	print("FoveaEngine - Specular Reflections Unit Tests")
	print("======================================================================")

	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	# ------------------------------------------------------------------
	# TEST 1: Shader Uniform Updates
	# ------------------------------------------------------------------
	print("\n--- Test 1: Shader Uniform Updates ---")
	
	# 1. Setup Camera3D
	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3(0, 0, 5)
	root.add_child(camera)

	# 2. Setup DirectionalLight3D
	var light := DirectionalLight3D.new()
	# Rotate the light to point towards Vector3(0.0, -0.7071, -0.7071)
	light.rotation = Vector3(deg_to_rad(-45.0), 0.0, 0.0)
	root.add_child(light)
	
	# The forward direction of the light is -Basis.z
	var expected_light_dir = -light.global_transform.basis.z.normalized()
	print("  Active DirectionalLight3D forward vector: ", expected_light_dir)

	# 3. Setup FoveaCoreSplatRenderer
	var core_renderer := FoveaCoreSplatRenderer.new()
	# Baked 3DGS radiance is intentionally unlit by default. This suite tests
	# the explicit dynamic-lighting opt-in, so enable it before _ready/_process.
	core_renderer.enable_dynamic_lighting = true
	root.add_child(core_renderer)
	
	# 4. Setup FoveaInstancedSplatRenderer
	var instanced_renderer := FoveaInstancedSplatRenderer.new()
	root.add_child(instanced_renderer)

	# Wait a frame for _ready and _process to run
	await create_timer(0.1).timeout

	# 5. Assertions on core splat renderer
	var core_mat = core_renderer.material_override as ShaderMaterial
	_assert("Core renderer material is ShaderMaterial", core_mat != null)
	if core_mat:
		var core_light_dir = core_mat.get_shader_parameter("light_direction")
		_assert("Core renderer set light_direction uniform", core_light_dir != null)
		if core_light_dir != null:
			_assert("Core renderer light_direction matches light orientation", core_light_dir.is_equal_approx(expected_light_dir))

	# 6. Assertions on instanced splat renderer
	var inst_mat = instanced_renderer.material_override as ShaderMaterial
	_assert("Instanced renderer material is ShaderMaterial", inst_mat != null)
	if inst_mat:
		var inst_light_dir = inst_mat.get_shader_parameter("light_direction")
		_assert("Instanced renderer set light_direction uniform", inst_light_dir != null)
		if inst_light_dir != null:
			_assert("Instanced renderer light_direction matches light orientation", inst_light_dir.is_equal_approx(expected_light_dir))

	# Cleanup Test 1 nodes
	core_renderer.queue_free()
	instanced_renderer.queue_free()
	light.queue_free()
	camera.queue_free()

	# ------------------------------------------------------------------
	# TEST 2: CPU Specular Highlight in SplatLightingAnimator
	# ------------------------------------------------------------------
	print("\n--- Test 2: CPU Specular Highlight in SplatLightingAnimator ---")
	
	var animator = SplatLightingAnimator.new()
	animator.shadow_offset_multiplier = 0.5
	animator.highlight_intensity = 1.0
	root.add_child(animator)

	var splattable = FoveaSplattable.new()
	root.add_child(splattable)
	
	# Create a splat facing positive Z (camera direction)
	var splat = GaussianSplat.new()
	splat.position = Vector3(0.0, 0.0, 0.0)
	splat.normal = Vector3(0.0, 0.0, 1.0)
	splat.surface_normal = Vector3(0.0, 0.0, 1.0)
	splat.layer_type = GaussianSplat.LayerType.LIGHT
	var splats_arr: Array[GaussianSplat] = [splat]
	splattable.loaded_splats = splats_arr
	
	# Scenario A: Camera and Light perfectly aligned with Splat Normal
	# Camera is at (0, 0, 5), pointing at (0, 0, 0) -> view vector is (0, 0, 1)
	# Light shines along -Z: Vector3(0, 0, -1) -> -light_dir is (0, 0, 1)
	var test_cam := Camera3D.new()
	test_cam.position = Vector3(0, 0, 5)
	test_cam.current = true
	root.add_child(test_cam)
	
	var light_dir_a = Vector3(0.0, 0.0, -1.0)
	animator._animate_splat_layers(light_dir_a)
	
	# View vector V = (0, 0, 5).normalized() = (0, 0, 1)
	# Light vector L = -light_dir_a = (0, 0, 1)
	# H = (V + L).normalized() = (0, 0, 1)
	# specular_align = surface_normal.dot(H) = (0,0,1).dot(0,0,1) = 1.0
	# specular_intensity = pow(1.0, 16.0) = 1.0
	# alignment (diffuse) = surface_normal.dot(-light_dir_a) = 1.0
	# expected opacity = (0.3 * 1.0 + 0.7 * 1.0) * 1.0 = 1.0
	_assert("Perfect alignment gives max opacity (1.0)", is_equal_approx(splat.opacity, 1.0))

	# Scenario B: Camera slightly off-angle, Light slightly off-angle
	# Camera is at (3, 0, 4) -> V = (3, 0, 4).normalized() = (0.6, 0.0, 0.8)
	# Light dir = (-0.6, 0.0, -0.8) -> L = (0.6, 0.0, 0.8)
	# H = (V + L).normalized() = (0.6, 0.0, 0.8)
	# specular_align = normal.dot(H) = 0.8
	# specular_intensity = pow(0.8, 16.0) ≈ 0.028147
	# alignment (diffuse) = normal.dot(L) = 0.8
	# expected opacity = (0.3 * 0.8 + 0.7 * 0.028147) * 1.0 ≈ 0.24 + 0.0197 = 0.2597
	test_cam.position = Vector3(3.0, 0.0, 4.0)
	var light_dir_b = Vector3(-0.6, 0.0, -0.8)
	animator._animate_splat_layers(light_dir_b)
	var expected_opacity_b = (0.3 * 0.8 + 0.7 * pow(0.8, 16.0)) * 1.0
	_assert("Off-angle Blinn-Phong calculation matches expected", is_equal_approx(splat.opacity, expected_opacity_b))

	# Cleanup Test 2 nodes
	test_cam.queue_free()
	splattable.queue_free()
	animator.queue_free()
	
	_finish()

func _finish() -> void:
	print("\n" + "======================================================================")
	print("Specular Reflections Tests: %d passed, %d failed (%.0f%%)" % [
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
