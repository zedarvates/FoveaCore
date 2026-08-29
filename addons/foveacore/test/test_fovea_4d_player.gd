extends SceneTree

const PlayerScript := preload("res://addons/foveacore/scripts/advanced/fovea_4d_player.gd")
const LoaderScript := preload("res://addons/foveacore/scripts/fovea_4d_loader.gd")

const BASE_PATH: String = "res://test/fixtures/rust_v2_fixture.fovea"
const SIDECAR_PATH: String = "res://test/fixtures/gdscript_fovea4d_v1_fixture.fovea4d"

var _passed: int = 0
var _failed: int = 0


class FakeRenderer:
	extends Node
	var deformer: Node = null


func _init() -> void:
	var splat := FoveaSplat3D.new()
	splat.name = "Splat"
	splat.source_path = BASE_PATH
	root.add_child(splat)
	await process_frame
	var delegate: FoveaSplattable = splat.get_advanced()
	_assert("delegate exists", delegate != null, "missing delegate")

	var player: Node = PlayerScript.new()
	player.name = "Player"
	player.target_path = NodePath("../Splat")
	player.sidecar_path = SIDECAR_PATH
	player.autoplay = false
	root.add_child(player)
	_assert("player loads matching sidecar", player.load_motion_now() == OK, player.last_error)
	_assert("delegate receives field", delegate.motion_4d_field != null, "missing field")
	_assert("4D target becomes dynamic", not delegate.is_static, "still static")
	player.seek(0.25)
	_assert("seek forwards time", is_equal_approx(delegate.motion_4d_time_seconds, 0.25), str(delegate.motion_4d_time_seconds))
	player.play()
	player._process(0.5)
	_assert("play advances time", is_equal_approx(delegate.motion_4d_time_seconds, 0.75), str(delegate.motion_4d_time_seconds))
	player.playback_rate = 2.0
	player._process(0.25)
	_assert("playback rate scales time", is_equal_approx(delegate.motion_4d_time_seconds, 1.25), str(delegate.motion_4d_time_seconds))
	player.pause()
	player._process(1.0)
	_assert("pause holds time", is_equal_approx(delegate.motion_4d_time_seconds, 1.25), str(delegate.motion_4d_time_seconds))
	player.queue_free()
	await process_frame
	_assert("player cleanup clears field", delegate.motion_4d_field == null, "field retained")
	_assert("player cleanup restores static state", delegate.is_static, "dynamic retained")

	var field_result: Dictionary = LoaderScript.load_sidecar(SIDECAR_PATH, BASE_PATH)
	var field: Fovea4DMotionField = field_result.get("field")
	var conflict := FoveaSplattable.new()
	root.add_child(conflict)
	conflict.delta_positions[0] = Vector3.ONE
	_assert("delta positions block 4D", conflict.configure_4d_motion(field) == ERR_ALREADY_IN_USE, "accepted delta")
	conflict.delta_positions.clear()
	conflict.morph_type = "Bend"
	conflict.morph_weight = 1.0
	_assert("morph blocks 4D", conflict.configure_4d_motion(field) == ERR_ALREADY_IN_USE, "accepted morph")
	conflict.morph_type = "None"
	conflict.morph_weight = 0.0
	var renderer := FakeRenderer.new()
	renderer.name = "FoveaCoreSplatRenderer"
	renderer.deformer = Node.new()
	renderer.add_child(renderer.deformer)
	conflict.add_child(renderer)
	_assert("active renderer deformer blocks 4D", conflict.configure_4d_motion(field) == ERR_ALREADY_IN_USE, "accepted deformer")
	renderer.queue_free()
	await process_frame
	var blocker := Node.new()
	blocker.add_to_group("fovea_position_modifiers")
	conflict.add_child(blocker)
	_assert("position-modifier child blocks 4D", conflict.configure_4d_motion(field) == ERR_ALREADY_IN_USE, "accepted child")
	blocker.queue_free()
	await process_frame
	conflict.is_static = false
	_assert("dynamic target blocks 4D", conflict.configure_4d_motion(field) == ERR_ALREADY_IN_USE, "accepted dynamic")
	conflict.queue_free()

	var deferred_player: Node = PlayerScript.new()
	deferred_player.target_path = NodePath("../Splat")
	deferred_player.sidecar_path = SIDECAR_PATH
	deferred_player.autoplay = true
	root.add_child(deferred_player)
	await process_frame
	await process_frame
	_assert("deferred ready load succeeds", deferred_player.last_error.is_empty(), deferred_player.last_error)
	_assert("autoplay starts after deferred load", deferred_player.playing and delegate.motion_4d_field != null, "autoplay inactive")
	deferred_player.queue_free()
	await process_frame
	splat.queue_free()

	print("Fovea4D player tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
