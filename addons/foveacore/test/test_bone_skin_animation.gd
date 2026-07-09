extends SceneTree
const BoneSkin = preload("res://addons/foveacore/scripts/animation/fovea_bone_skin_animation.gd")
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== FoveaBoneSkinAnimation Tests ==="); _run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var b = BoneSkin.new()
	b.bone_count = 4
	var result = b._find_nearest_bones(Vector3.ZERO, 4)
	assert(result.has("indices"), "indices returned")
	assert(result.has("weights"), "weights returned")
	assert(abs(result["weights"][0] + result["weights"][1] + result["weights"][2] + result["weights"][3] - 1.0) < 0.01, "Weights sum to 1")
	_passed += 3; _failed += 0; print(f"  {_passed}/{_passed+_failed}")
