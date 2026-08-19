extends SceneTree

class CountingRenderer:
	extends Node
	var submissions: int = 0
	var last_count: int = 0

	func render_splats(splats: Array[GaussianSplat]) -> int:
		submissions += 1
		last_count = splats.size()
		return last_count

class VisibilityFixture:
	extends RefCounted
	var per_node_results: Dictionary = {}

var _passed: int = 0
var _failed: int = 0

func _init() -> void:
	print("\n=== Static Splat Cache Tests ===")
	await create_timer(0.1).timeout
	_run_tests()
	quit(1 if _failed > 0 else 0)

func _run_tests() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.global_transform = Transform3D.IDENTITY

	var splattable := FoveaSplattable.new()
	splattable.is_static = true
	splattable.splatting_enabled = true
	splattable.has_ply_splats = true
	var source_splat := GaussianSplat.new()
	source_splat.position = Vector3(0.0, 0.0, -2.0)
	splattable.loaded_splats = [source_splat]
	root.add_child(splattable)

	var visibility := VisibilityFixture.new()
	visibility.per_node_results[splattable] = null
	var renderer := CountingRenderer.new()
	var pipeline := FoveaSplatSubsystem.new()
	var temporal_reprojector := TemporalReprojector.new()
	pipeline.add_child(temporal_reprojector)
	pipeline.temporal_reprojector = temporal_reprojector
	pipeline.splat_renderer = renderer
	root.add_child(renderer)
	root.add_child(pipeline)

	pipeline.process_frame(visibility, camera, camera.global_position, true)
	_assert("First static frame is submitted", renderer.submissions == 1)
	pipeline.process_frame(visibility, camera, camera.global_position, true)
	_assert("Identical static frame reuses the cache", renderer.submissions == 1)
	_assert("Cache reuse is observable", pipeline.did_reuse_static_cache_last_frame())

	camera.position = Vector3(0.1, 0.0, 0.0)
	pipeline.process_frame(visibility, camera, camera.global_position, true)
	_assert("Camera movement invalidates depth order", renderer.submissions == 2)

	splattable.position = Vector3(1.0, 0.0, 0.0)
	pipeline.process_frame(visibility, camera, camera.global_position, true)
	_assert("Asset transform invalidates the cache", renderer.submissions == 3)

	pipeline.process_frame(visibility, camera, camera.global_position, false)
	_assert("Per-frame effects explicitly disable reuse", renderer.submissions == 4)
	_assert("Disabled reuse invalidates the prior cache", not pipeline.did_reuse_static_cache_last_frame())

	pipeline.free()
	renderer.free()
	splattable.free()
	camera.free()
	print("Static splat cache: %d passed, %d failed" % [_passed, _failed])

func _assert(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % name)
	else:
		_failed += 1
		push_error("  [FAIL] %s" % name)
