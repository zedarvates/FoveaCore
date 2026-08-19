extends SceneTree

## Unit tests for FoveaLODTextureBaker & FoveaHybridLODController Atlas Integration
## Validates UV-space splat baking, seam dilation, atlas packing, and LOD material overrides.

const FoveaLODTextureBakerScript := preload("res://addons/foveacore/scripts/advanced/fovea_lod_texture_baker.gd")
const HybridLODControllerScript := preload("res://addons/foveacore/scripts/advanced/fovea_hybrid_lod_controller.gd")
const FoveaSplattableScript := preload("res://addons/foveacore/scripts/fovea_splattable.gd")
const GaussianSplatScript := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

var _passed := 0
var _failed := 0

signal all_complete(passed: int, failed: int)

func _init() -> void:
	print("\n" + "─".repeat(70))
	print("FoveaLODTextureBaker & Atlas Integration Unit Tests")
	print("─".repeat(70))

	await create_timer(0.2).timeout
	_run_all()

func _run_all() -> void:
	_test_baking_logic()
	_test_packing_logic()
	_test_controller_integration()
	
	print("\n" + "─".repeat(70))
	print("LOD Texture Baker Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("─".repeat(70))
	all_complete.emit(_passed, _failed)
	
	if _failed > 0:
		quit(1)
	else:
		quit(0)

func _test_baking_logic() -> void:
	print("\n--- _test_baking_logic ---")
	
	# 1. Create a mock Splattable with a few splats
	var splattable = FoveaSplattableScript.new()
	splattable.name = "TestSplatForBake"
	
	# Add splats near the center of our quad
	var splat1 = GaussianSplatScript.new(Vector3(0.5, 0.5, 0.0))
	splat1.color = Color.RED
	splat1.opacity = 1.0
	splat1.scale = Vector3(0.1, 0.1, 0.1)
	splattable.loaded_splats.append(splat1)
	
	var splat2 = GaussianSplatScript.new(Vector3(-0.2, -0.2, 0.0))
	splat2.color = Color.BLUE
	splat2.opacity = 0.8
	splat2.scale = Vector3(0.1, 0.1, 0.1)
	splattable.loaded_splats.append(splat2)
	
	splattable.has_ply_splats = true
	
	# 2. Create a mock low-poly mesh (a simple quad on the XY plane)
	var mesh = ArrayMesh.new()
	var vertices = PackedVector3Array([
		Vector3(-1, -1, 0),
		Vector3(1, -1, 0),
		Vector3(1, 1, 0),
		Vector3(-1, 1, 0)
	])
	var uvs = PackedVector2Array([
		Vector2(0, 0),
		Vector2(1, 0),
		Vector2(1, 1),
		Vector2(0, 1)
	])
	var indices = PackedInt32Array([
		0, 1, 2,
		0, 2, 3
	])
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# 3. Bake texture (using 64x64 size for fast test)
	var baked_img = FoveaLODTextureBakerScript.bake_splats_to_mesh_texture(splattable, mesh, 64, 1.0, 0.5)
	
	_assert("Baked image is not null", baked_img != null)
	if baked_img != null:
		_assert("Baked image dimensions correct", baked_img.get_width() == 64 and baked_img.get_height() == 64)
		
		# Sample a few pixels to verify color was projected
		# Center-right should be close to Red (corresponds to splat1 at (0.5, 0.5) which in UV is (0.75, 0.75))
		# In image coords, (0.75, 0.75) is (48, 48) or (48, 16) depending on Y flip.
		# Let's count non-transparent pixels
		var non_transparent_count := 0
		for y in range(64):
			for x in range(64):
				if baked_img.get_pixel(x, y).a > 0.05:
					non_transparent_count += 1
		
		_assert("Baked image contains projected colors", non_transparent_count > 0, "%d non-transparent pixels found" % non_transparent_count)
		print("  Projected pixels: ", non_transparent_count)

	# This splattable is intentionally never added to the tree; release it and
	# its RefCounted splats explicitly before the standalone SceneTree exits.
	splattable.loaded_splats.clear()
	splattable.free()

func _test_packing_logic() -> void:
	print("\n--- _test_packing_logic ---")
	
	# Create two mock images
	var img1 = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img1.fill(Color.RED)
	var img2 = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img2.fill(Color.GREEN)
	
	var pack_res = FoveaLODTextureBakerScript.pack_textures_to_atlas([img1, img2], 64)
	
	_assert("Pack result is not null", pack_res != null)
	if pack_res != null:
		var atlas = pack_res.get("atlas_texture") as ImageTexture
		var regions = pack_res.get("regions") as Array[Rect2]
		
		_assert("Atlas texture created", atlas != null)
		_assert("Two regions returned", regions.size() == 2)
		
		if regions.size() == 2:
			var r1 = regions[0]
			var r2 = regions[1]
			_assert("Region 1 correct size", r1.size.is_equal_approx(Vector2(0.5, 1.0)) or r1.size.is_equal_approx(Vector2(1.0, 0.5)))
			_assert("Regions do not overlap", not r1.intersects(r2))
			print("  Region 1: ", r1)
			print("  Region 2: ", r2)

func _test_controller_integration() -> void:
	print("\n--- _test_controller_integration ---")
	
	var root = Node3D.new()
	get_root().add_child(root)
	
	# Create Camera3D
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 15) # far away
	root.add_child(camera)
	camera.make_current()
	
	# Create Splattable
	var splattable = FoveaSplattableScript.new()
	splattable.name = "TestSplattable"
	root.add_child(splattable)
	
	# Create MeshInstance3D
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "TestMeshInstance"
	root.add_child(mesh_instance)
	
	# Create a mock atlas texture
	var atlas_img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	atlas_img.fill(Color.BLUE)
	var atlas_tex = ImageTexture.create_from_image(atlas_img)
	
	# Create Controller
	var controller = HybridLODControllerScript.new()
	controller.splattable = splattable
	controller.mesh_instance = mesh_instance
	controller.transition_distance = 10.0
	controller.evaluation_interval = 0.05
	
	# Assign atlas parameters
	controller.lod_texture_atlas = atlas_tex
	controller.lod_texture_region = Rect2(0.1, 0.2, 0.5, 0.6)
	
	root.add_child(controller)
	
	# Evaluate LOD (force transition to LOD 1 mesh)
	controller._evaluate_lod(true)
	
	_assert("Transitioned to LOD 1", controller._current_lod == 1)
	
	# Check material override on mesh_instance
	var mat = mesh_instance.material_override as StandardMaterial3D
	_assert("Material override is StandardMaterial3D", mat != null)
	if mat != null:
		_assert("Albedo texture is the atlas", mat.albedo_texture == atlas_tex)
		_assert("UV1 scale correct", mat.uv1_scale.is_equal_approx(Vector3(0.5, 0.6, 1.0)))
		_assert("UV1 offset correct", mat.uv1_offset.is_equal_approx(Vector3(0.1, 0.2, 0.0)))
		
	# Clean up
	root.free()

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  ✓ PASS: %s %s" % [name, detail])
	else:
		_failed += 1
		print("  ✗ FAIL: %s %s" % [name, detail])
