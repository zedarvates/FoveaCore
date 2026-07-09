extends SceneTree
const LodStretch = preload("res://addons/foveacore/scripts/animation/fovea_lod_stretch_animator.gd")
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== FoveaLodStretchAnimator Tests ==="); _run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var l = LodStretch.new()
	l.enabled = false
	var splat = {"position": Vector3(0,0,10), "scale": Vector3.ONE}
	var s = l.modify_splat(splat.duplicate(), 0.016, null)
	assert(s["scale"] == Vector3.ONE, "No stretch when disabled")
	_passed += 1; _failed += 0; print(f"  {_passed}/{_passed+_failed}")
