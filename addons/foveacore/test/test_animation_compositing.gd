extends SceneTree

const AnimationSubsystem = preload("res://addons/foveacore/scripts/fovea_animation_subsystem.gd")

func _init() -> void:

	var subsystem: FoveaAnimationSubsystem = AnimationSubsystem.new()
	subsystem._process(0.016)
	var first_time: float = subsystem.get_time()
	subsystem._process(0.016)
	assert(subsystem.get_time() > first_time)
	print("PASS: animation time advances monotonically")
	quit(0)
