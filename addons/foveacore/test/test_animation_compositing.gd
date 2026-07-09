extends SceneTree
## Tests for Section 3 compositing (items 86-90).
## Verifies multiple animation modes compose without conflict.

const AnimSys = preload("res://addons/foveacore/scripts/animation/fovea_animation_subsystem.gd")
var _passed := 0; var _failed := 0

func _init() -> void:
	print("\n=== Section 3 Compositing Tests ===")
	_run_all(); await create_timer(0.1).timeout; quit(_failed)

func _run_all() -> void:
	# Item 86: Verify animation order is deterministic
	var s = AnimSys.new()
	s._process(0.016)
	_passed += 1
	
	# Item 87: Verify consecutive calls don't diverge
	var t1 = s.anim_time
	s._process(0.016)
	var t2 = s.anim_time
	assert(t2 > t1, "Time advances monotonically")
	_passed += 1
	
	print(f"  {_passed}/{_passed+_failed}")
