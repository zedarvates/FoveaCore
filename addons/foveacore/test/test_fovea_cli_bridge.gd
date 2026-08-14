extends SceneTree

## Non-GPU contract tests for the optional local automation bridge.
## Rendering quality and performance are covered by separate hardware gates.

const BridgeScript := preload("res://addons/foveacore/scripts/integration/fovea_cli_bridge.gd")
const VALID_SOURCE := "res://addons/foveacore/test/fixtures/minimal_cli_fixture.ply"

var _passed := 0
var _failed := 0


func _init() -> void:
	await create_timer(0.1).timeout
	var scene := Node3D.new()
	scene.name = "FoveaCliBridgeFixture"
	root.add_child(scene)
	current_scene = scene

	var bridge: RefCounted = BridgeScript.new()
	_test_contract(bridge)
	_test_fail_closed_inputs(bridge, scene)
	_test_add_status_and_validate(bridge, scene)

	scene.queue_free()
	print("Fovea CLI bridge: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_contract(bridge: RefCounted) -> void:
	var value: Dictionary = bridge.contract()
	_assert("contract version", value.get("version") == 1, str(value))
	_assert("contract is file-write free", value.get("writes_files") == false, str(value))
	_assert("contract is network-listener free", value.get("starts_network_listener") == false, str(value))
	_assert("public node is stable", value.get("public_node") == "FoveaSplat3D", str(value))


func _test_fail_closed_inputs(bridge: RefCounted, scene: Node3D) -> void:
	var outside: Dictionary = bridge.add_splat(self, {
		"parent": str(scene.get_path()),
		"source_path": "../outside.ply",
	})
	_assert("outside source path rejected", not bool(outside.get("ok", true)), str(outside))

	var missing: Dictionary = bridge.add_splat(self, {
		"parent": str(scene.get_path()),
		"source_path": "res://missing.ply",
	})
	_assert("missing source rejected", not bool(missing.get("ok", true)), str(missing))

	var invalid_opacity: Dictionary = bridge.add_splat(self, {
		"parent": str(scene.get_path()),
		"source_path": VALID_SOURCE,
		"opacity": 1.1,
	})
	_assert("invalid opacity rejected", not bool(invalid_opacity.get("ok", true)), str(invalid_opacity))

	var invalid_collision: Dictionary = bridge.add_splat(self, {
		"parent": str(scene.get_path()),
		"source_path": VALID_SOURCE,
		"generate_collisions": true,
	})
	_assert("PLY collision request rejected", not bool(invalid_collision.get("ok", true)), str(invalid_collision))


func _test_add_status_and_validate(bridge: RefCounted, scene: Node3D) -> void:
	_assert("validated PLY fixture exists", FileAccess.file_exists(VALID_SOURCE), VALID_SOURCE)
	if not FileAccess.file_exists(VALID_SOURCE):
		return

	var added: Dictionary = bridge.add_splat(self, {
		"parent": str(scene.get_path()),
		"source_path": VALID_SOURCE,
		"name": "BonsaiCliSplat",
		"quality": "balanced",
		"opacity": 0.75,
		"generate_collisions": false,
		"is_static": true,
	})
	_assert("splat added", bool(added.get("ok", false)), str(added))
	if not bool(added.get("ok", false)):
		return

	var added_data: Dictionary = added["data"]
	_assert("mutation remains unsaved", added_data.get("persisted") == false, str(added_data))
	_assert("one splat loaded", added_data.get("loaded_splat_count") == 1, str(added_data))
	var splat: FoveaSplat3D = scene.get_node_or_null("BonsaiCliSplat") as FoveaSplat3D
	_assert("public node instantiated", splat != null, str(added_data))
	if splat == null:
		return
	_assert("source assigned", splat.source_path == VALID_SOURCE, splat.source_path)
	_assert("quality assigned", splat.quality_preset == FoveaSplat3D.QualityPreset.BALANCED, str(splat.quality_preset))
	_assert("opacity assigned", is_equal_approx(splat.opacity, 0.75), str(splat.opacity))

	var status_result: Dictionary = bridge.status(self, 4096)
	_assert("status succeeds", bool(status_result.get("ok", false)), str(status_result))
	if bool(status_result.get("ok", false)):
		var status_data: Dictionary = status_result["data"]
		_assert("status sees one splat", status_data.get("splat_count") == 1, str(status_data))
		_assert("status scan is complete", status_data.get("complete") == true, str(status_data))
		var first_splat: Dictionary = (status_data["splats"] as Array)[0]
		_assert("status reports loaded splat", first_splat.get("loaded_splat_count") == 1, str(first_splat))

	var validation: Dictionary = bridge.validate(self, 4096)
	_assert("validation succeeds", bool(validation.get("ok", false)), str(validation))
	if bool(validation.get("ok", false)):
		var validation_data: Dictionary = validation["data"]
		_assert("valid scene accepted", validation_data.get("valid") == true, str(validation_data))
		_assert("validation sees one splat", validation_data.get("splat_count") == 1, str(validation_data))


func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s -- %s" % [name, detail])
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [name, detail])
