extends SceneTree
const Flow = preload("res://addons/foveacore/scripts/animation/fovea_flow_field_animator.gd")
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== FoveaFlowFieldAnimator Tests ==="); _run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var f = Flow.new()
	assert(f.amplitude > 0, "Default amplitude")
	f.preset = Flow.Preset.WATER
	assert(f.amplitude == 0.15, "Water preset amplitude")
	var splat = {"position": Vector3(1,2,3), "layer": 0}
	var s2 = f.modify_splat(splat.duplicate(), 0.016, null)
	assert(s2["position"] != splat["position"], "Position changed")
	_passed += 4; _failed += 0; print(f"  {_passed}/{_passed+_failed}")
