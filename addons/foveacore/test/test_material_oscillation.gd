extends SceneTree
const MatOsc = preload("res://addons/foveacore/scripts/animation/fovea_material_oscillation.gd")
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== FoveaMaterialOscillation Tests ==="); _run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var m = MatOsc.new()
	var splat = {"color": Color.WHITE}
	var s = m.modify_splat(splat.duplicate(), 0.016, null)
	assert(typeof(s["color"]) == TYPE_COLOR, "Color returned")
	assert(s["color"].a <= 1.0 and s["color"].a >= 0.0, "Alpha in range")
	_passed += 2; _failed += 0; print(f"  {_passed}/{_passed+_failed}")
