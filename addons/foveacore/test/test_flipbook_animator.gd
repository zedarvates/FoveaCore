extends SceneTree
const Flip = preload("res://addons/foveacore/scripts/animation/fovea_flipbook_animator.gd")
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== FoveaFlipbookAnimator Tests ==="); _run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var f = Flip.new()
	assert(f.frame_count == 1, "Default 1 frame")
	f.frame_count = 8; f.fps = 24
	var splat = {"instance_id": 0}
	var s = f.modify_splat(splat.duplicate(), 0.016, null)
	assert(s.has("flipbook_frame"), "flipbook_frame added")
	_passed += 2; _failed += 0; print(f"  {_passed}/{_passed+_failed}")
