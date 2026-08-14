extends SceneTree
## Regression test for assigning a native asset after FoveaSplat3D is ready.
## This is the lifecycle used by the editor file picker and runtime code that
## changes source_path dynamically. Non-GPU group.

const FIXTURE: String = "res://test/demo_bonsai.fovea"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	await process_frame

	var manager: Node = get_root().get_node_or_null("FoveaCoreManager")
	_assert("manager autoload exists", manager != null)
	if manager == null:
		_finish()
		return

	var splat: FoveaSplat3D = FoveaSplat3D.new()
	get_root().add_child(splat)
	await process_frame

	splat.source_path = FIXTURE
	await process_frame

	var renderers: Dictionary = manager.get("_instanced_renderers") as Dictionary
	_assert("dynamic path creates instanced renderer", renderers.has(FIXTURE))
	if renderers.has(FIXTURE):
		var renderer: FoveaInstancedSplatRenderer = renderers[FIXTURE] as FoveaInstancedSplatRenderer
		_assert("renderer keeps assigned path", renderer != null and renderer.asset_path == FIXTURE)

	splat.queue_free()
	await process_frame
	await process_frame

	renderers = manager.get("_instanced_renderers") as Dictionary
	_assert("unused renderer is released", not renderers.has(FIXTURE))
	_finish()


func _assert(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("  ✓ ", label)
	else:
		_failed += 1
		push_error("  ✗ " + label)


func _finish() -> void:
	print("Dynamic .fovea registration: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
