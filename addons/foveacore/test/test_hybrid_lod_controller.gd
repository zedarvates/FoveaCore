extends SceneTree

## Unit tests for FoveaHybridLODController
## Validates distance-based transitions between splats (LOD 0) and simplified meshes (LOD 1).

const HybridLODControllerScript := preload("res://addons/foveacore/scripts/advanced/fovea_hybrid_lod_controller.gd")
const FoveaSplattableScript := preload("res://addons/foveacore/scripts/fovea_splattable.gd")

var _passed := 0
var _failed := 0

signal all_complete(passed: int, failed: int)

func _init() -> void:
	print("\n" + "─".repeat(70))
	print("FoveaHybridLODController Unit Tests")
	print("─".repeat(70))

	await create_timer(0.2).timeout
	_run_all()

func _run_all() -> void:
	_test_lod_transitions()
	
	print("\n" + "─".repeat(70))
	print("HybridLODController Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("─".repeat(70))
	all_complete.emit(_passed, _failed)
	
	if _failed > 0:
		quit(1)
	else:
		quit(0)

func _test_lod_transitions() -> void:
	print("\n--- _test_lod_transitions ---")
	
	# Root node for the test scene, added to the SceneTree's root viewport
	var root := Node3D.new()
	get_root().add_child(root)
	
	# Create Camera3D
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 5) # 5 meters away
	root.add_child(camera)
	
	# Create Splattable
	var splattable := FoveaSplattableScript.new()
	splattable.name = "TestSplattable"
	root.add_child(splattable)
	
	# Create MeshInstance3D
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TestMeshInstance"
	root.add_child(mesh_instance)
	
	# Create Controller
	var controller = HybridLODControllerScript.new()
	controller.splattable = splattable
	controller.mesh_instance = mesh_instance
	controller.transition_distance = 10.0 # Switch to mesh if distance >= 10m
	controller.evaluation_interval = 0.05
	root.add_child(controller)
	
	# Bind camera to viewport
	camera.make_current()
	
	# Force initial LOD evaluation
	controller._evaluate_lod(true)
	
	# 1. Close distance test (5m < 10m) -> Should be LOD 0 (Splats active, Mesh inactive)
	_assert("Close LOD active", controller._current_lod == 0, "Current LOD is 0 (Splats)")
	_assert("Close Splat visible", splattable.visible == true, "Splat visible: true")
	_assert("Close Splat enabled", splattable.splatting_enabled == true, "Splatting enabled: true")
	_assert("Close Mesh hidden", mesh_instance.visible == false, "Mesh visible: false")
	
	# 2. Far distance test (Move camera to 15m away, 15m >= 10m) -> Should transition to LOD 1 (Mesh active, Splats inactive)
	camera.position = Vector3(0, 0, 15)
	controller._evaluate_lod(true)
	
	_assert("Far LOD active", controller._current_lod == 1, "Current LOD is 1 (Mesh)")
	_assert("Far Splat hidden", splattable.visible == false, "Splat visible: false")
	_assert("Far Splat disabled", splattable.splatting_enabled == false, "Splatting enabled: false")
	_assert("Far Mesh visible", mesh_instance.visible == true, "Mesh visible: true")
	
	# Clean up
	root.queue_free()

func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_pass(name if detail.is_empty() else "%s — %s" % [name, detail])
	else:
		_fail(name, detail)

func _pass(detail: String) -> void:
	_passed += 1
	print("  ✓ %s" % detail)

func _fail(test_name: String, err: String) -> void:
	_failed += 1
	print("  ✗ %s — %s" % [test_name, err])
