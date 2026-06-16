extends SceneTree

## Unit tests for TexturedSplatGenerator (Task 58)
## Validates:
## 1. Directory creation and PNG file writing on disk.
## 2. Successful texture generation and loading.
## 3. Correct brush type classification based on surface roughness thresholds.
## 4. Successful shader parameter binding on material.

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n==============================================================")
	print("FoveaEngine - TexturedSplatGenerator Unit Tests")
	print("==============================================================")
	
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	# ------------------------------------------------------------------
	# TEST 1: Texture Generation & Loading
	# ------------------------------------------------------------------
	print("\n--- Test 1: Procedural Texture Generation & Disk Storage ---")
	
	# Clean up any existing textures to force regeneration
	var paths := [
		"res://addons/foveacore/textures/sponge.png",
		"res://addons/foveacore/textures/drybrush.png",
		"res://addons/foveacore/textures/stipple.png"
	]
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
			
	# Retrieve textures (forces generation)
	var sponge_tex = TexturedSplatGenerator.get_sponge_texture()
	var drybrush_tex = TexturedSplatGenerator.get_drybrush_texture()
	var stipple_tex = TexturedSplatGenerator.get_stipple_texture()
	
	_assert("Sponge texture generated/loaded successfully", sponge_tex != null)
	_assert("Drybrush texture generated/loaded successfully", drybrush_tex != null)
	_assert("Stipple texture generated/loaded successfully", stipple_tex != null)
	
	# Verify files exist on disk
	_assert("sponge.png exists on disk", FileAccess.file_exists("res://addons/foveacore/textures/sponge.png"))
	_assert("drybrush.png exists on disk", FileAccess.file_exists("res://addons/foveacore/textures/drybrush.png"))
	_assert("stipple.png exists on disk", FileAccess.file_exists("res://addons/foveacore/textures/stipple.png"))
	
	# Verify image dimensions (must be 128x128)
	if sponge_tex:
		var img = sponge_tex.get_image()
		if img:
			_assert("Sponge texture image is 128x128", img.get_width() == 128 and img.get_height() == 128)
	if drybrush_tex:
		var img = drybrush_tex.get_image()
		if img:
			_assert("Drybrush texture image is 128x128", img.get_width() == 128 and img.get_height() == 128)
	if stipple_tex:
		var img = stipple_tex.get_image()
		if img:
			_assert("Stipple texture image is 128x128", img.get_width() == 128 and img.get_height() == 128)

	# ------------------------------------------------------------------
	# TEST 2: Brush Classification Based on Roughness
	# ------------------------------------------------------------------
	print("\n--- Test 2: Brush Classification Based on Roughness ---")
	
	# Create a mock MeshInstance3D geometry with varying normals to test thresholds
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	
	# We will create a sequence of triangles. Normal variance is calculated as dist(n[idx], n[idx-1])
	# Vertices: 24 vertices (6 triangles * 3 vertices plus padding to trigger i % 4 == 0 selection)
	# 24 vertices means indices 0, 4, 8, 12, 16, 20 will be sampled (since i % 4 == 0)
	vertices.resize(24)
	normals.resize(24)
	
	# Assign varying normals to check thresholds:
	# idx 0: roughness = 0 (n[0]=UP, n[0-1]=UP) -> GAUSSIAN (<= 0.12)
	normals[0] = Vector3.UP
	
	# idx 4: roughness = distance(UP, RIGHT) = sqrt(2) ≈ 1.41 -> DRYBRUSH (> 0.6)
	normals[3] = Vector3.UP
	normals[4] = Vector3.RIGHT
	
	# idx 8: roughness = distance(UP, Vector3(0.5, 0.866, 0)) = 0.5176 -> STONE (> 0.4)
	normals[7] = Vector3.UP
	normals[8] = Vector3(0.5, 0.866, 0.0).normalized()
	
	# idx 12: roughness = distance(UP, Vector3(0.3, 0.954, 0)) = 0.309 -> SPONGE (> 0.25)
	normals[11] = Vector3.UP
	normals[12] = Vector3(0.3, 0.954, 0.0).normalized()
	
	# idx 16: roughness = distance(UP, Vector3(0.15, 0.988, 0)) = 0.151 -> STIPPLE (> 0.12)
	normals[15] = Vector3.UP
	normals[16] = Vector3(0.15, 0.988, 0.0).normalized()
	
	# idx 20: roughness = distance(UP, Vector3(0.05, 0.998, 0)) = 0.050 -> GAUSSIAN (<= 0.12)
	normals[19] = Vector3.UP
	normals[20] = Vector3(0.05, 0.998, 0.0).normalized()
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	var splats = TexturedSplatGenerator.generate_textured_splats(mesh)
	
	_assert("Procedural generation returned 6 splats", splats.size() == 6)
	if splats.size() == 6:
		_assert("Splat 0 is GAUSSIAN", splats[0].brush_type == GaussianSplat.BrushType.GAUSSIAN, "Got " + str(splats[0].brush_type))
		_assert("Splat 1 is DRYBRUSH", splats[1].brush_type == GaussianSplat.BrushType.DRYBRUSH, "Got " + str(splats[1].brush_type))
		_assert("Splat 2 is STONE", splats[2].brush_type == GaussianSplat.BrushType.STONE, "Got " + str(splats[2].brush_type))
		_assert("Splat 3 is SPONGE", splats[3].brush_type == GaussianSplat.BrushType.SPONGE, "Got " + str(splats[3].brush_type))
		_assert("Splat 4 is STIPPLE", splats[4].brush_type == GaussianSplat.BrushType.STIPPLE, "Got " + str(splats[4].brush_type))
		_assert("Splat 5 is GAUSSIAN", splats[5].brush_type == GaussianSplat.BrushType.GAUSSIAN, "Got " + str(splats[5].brush_type))

	# ------------------------------------------------------------------
	# TEST 3: Shader Parameter Binding
	# ------------------------------------------------------------------
	print("\n--- Test 3: Shader Parameter Binding ---")
	
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://addons/foveacore/shaders/splat_render_artistic.gdshader")
	
	TexturedSplatGenerator.apply_brush_textures(mat)
	
	var bound_sponge = mat.get_shader_parameter("sponge_texture")
	var bound_drybrush = mat.get_shader_parameter("drybrush_texture")
	var bound_stipple = mat.get_shader_parameter("stipple_texture")
	
	_assert("Sponge texture parameter bound on material", bound_sponge != null)
	_assert("Drybrush texture parameter bound on material", bound_drybrush != null)
	_assert("Stipple texture parameter bound on material", bound_stipple != null)

	_finish()

func _finish() -> void:
	print("\n==============================================================")
	print("TexturedSplatGenerator Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("==============================================================")
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
