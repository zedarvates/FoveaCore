extends SceneTree

const AnimationSubsystem = preload("res://addons/foveacore/scripts/fovea_animation_subsystem.gd")

func _init() -> void:
	var subsystem: FoveaAnimationSubsystem = AnimationSubsystem.new()
	assert(is_zero_approx(subsystem.get_time()))
	subsystem._process(0.1)
	assert(is_equal_approx(subsystem.get_time(), 0.1))
	subsystem.enabled = false
	subsystem._process(0.1)
	assert(is_equal_approx(subsystem.get_time(), 0.2))
	subsystem.free()
	print("PASS: typed animation subsystem timebase")
	await process_frame
	quit(0)
