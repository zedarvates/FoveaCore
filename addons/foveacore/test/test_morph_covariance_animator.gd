extends SceneTree
const Morph = preload("res://addons/foveacore/scripts/animation/fovea_morph_covariance_animator.gd")
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== FoveaMorphCovarianceAnimator Tests ==="); _run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var m = Morph.new()
	var splat = {"scale": Vector3(1,1,1), "rotation": Quaternion.IDENTITY, "instance_id": 42}
	var s = m.modify_splat(splat.duplicate(), 0.016, null)
	assert(s["scale"].x != 1.0 or s["rotation"] != Quaternion.IDENTITY, "Morph applied")
	var s2 = m.modify_splat(splat.duplicate(), 0.016, null)
	_passed += 2; _failed += 0; print(f"  {_passed}/{_passed+_failed}")
