extends SceneTree
const AnimSys = preload("res://addons/foveacore/scripts/animation/fovea_animation_subsystem.gd")
var _passed := 0; var _failed := 0
func _init() -> void:
	print("\n=== FoveaAnimationSubsystem Tests ===")
	_run_all(); await create_timer(0.1).timeout; quit(_failed)
func _run_all() -> void:
	var s = AnimSys.new()
	assert(s != null, "AnimSys created")
	assert(s.anim_time == 0.0, "Time starts at 0")
	s._process(0.1)
	assert(abs(s.anim_time - 0.1) < 0.001, "Time advances")
	s.enabled = false; s._process(0.1)
	assert(abs(s.anim_time - 0.1) < 0.001, "No advance when disabled")
	_passed += 4; _fail(4); print(f"  {_passed}/{_passed+_failed}")
func _fail(c:int) -> void: _failed += c
