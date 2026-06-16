extends SceneTree

## Unit tests for SplatDecalTool (Task 63)
## Validates decal generation, normal alignment, and color profiles.

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n======================================================================")
	print("SplatDecalTool (Task 63) Unit Tests")
	print("======================================================================")
	
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	# Setup test nodes
	var splattable: FoveaSplattable = FoveaSplattable.new()
	splattable.name = "TestSplattable"
	root.add_child(splattable)
	
	var decal_tool: SplatDecalTool = SplatDecalTool.new()
	decal_tool.name = "TestDecalTool"
	decal_tool.brush_radius = 0.3
	decal_tool.splat_density = 10
	decal_tool.splat_size = 0.05
	root.add_child(decal_tool)
	
	# --- Test 1: Moss Decal Spray ---
	print("\n--- Test 1: Moss Decal Spray ---")
	decal_tool.decal_type = SplatDecalTool.DecalType.MOSS
	
	var impact_pos := Vector3(1.0, 0.0, 0.0)
	var impact_normal := Vector3.UP
	
	decal_tool.spray_at_global_position(splattable, impact_pos, impact_normal)
	
	_assert("Splats were added to loaded_splats", splattable.loaded_splats.size() == 10)
	if splattable.loaded_splats.size() == 10:
		var splat: GaussianSplat = splattable.loaded_splats[0]
		_assert("Splat positioned near impact point", splat.position.distance_to(impact_pos) < 0.35)
		_assert("Splat normal aligned with impact normal", splat.surface_normal.dot(impact_normal) > 0.8)
		_assert("Moss splat has green color profile", splat.color.g > splat.color.r and splat.color.g > splat.color.b)
		_assert("Moss splat has LEAVES layer type", splat.layer_type == GaussianSplat.LayerType.LEAVES)
		_assert("Moss splat has SPONGE brush type", splat.brush_type == GaussianSplat.BrushType.SPONGE)

	# --- Test 2: Rust Decal Spray ---
	print("\n--- Test 2: Rust Decal Spray ---")
	splattable.loaded_splats.clear()
	decal_tool.decal_type = SplatDecalTool.DecalType.RUST
	
	decal_tool.spray_at_global_position(splattable, impact_pos, impact_normal)
	
	_assert("Splats were added to loaded_splats", splattable.loaded_splats.size() == 10)
	if splattable.loaded_splats.size() == 10:
		var splat: GaussianSplat = splattable.loaded_splats[0]
		_assert("Rust splat has red-brown color profile", splat.color.r > splat.color.g and splat.color.r > splat.color.b)
		_assert("Rust splat has TRUNK layer type", splat.layer_type == GaussianSplat.LayerType.TRUNK)
		_assert("Rust splat has STONE brush type", splat.brush_type == GaussianSplat.BrushType.STONE)

	# --- Test 3: Snow Decal Spray ---
	print("\n--- Test 3: Snow Decal Spray ---")
	splattable.loaded_splats.clear()
	decal_tool.decal_type = SplatDecalTool.DecalType.SNOW
	
	decal_tool.spray_at_global_position(splattable, impact_pos, impact_normal)
	
	_assert("Splats were added to loaded_splats", splattable.loaded_splats.size() == 10)
	if splattable.loaded_splats.size() == 10:
		var splat: GaussianSplat = splattable.loaded_splats[0]
		_assert("Snow splat has white/blue tint", splat.color.r > 0.8 and splat.color.g > 0.8 and splat.color.b > 0.8)
		_assert("Snow splat has BASE layer type", splat.layer_type == GaussianSplat.LayerType.BASE)
		_assert("Snow splat has GAUSSIAN brush type", splat.brush_type == GaussianSplat.BrushType.GAUSSIAN)

	# Cleanup
	splattable.queue_free()
	decal_tool.queue_free()
	_finish()

func _finish() -> void:
	print("\n======================================================================")
	print("SplatDecalTool Tests: %d passed, %d failed (%.0f%%)" % [
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
