extends SceneTree

const MobileOptimizer = preload("res://addons/foveacore/scripts/advanced/fovea_mobile_optimizer.gd")

func _init() -> void:

	var optimizer: FoveaMobileOptimizer = MobileOptimizer.new()
	var quest: Dictionary = optimizer.apply_preset(FoveaMobileOptimizer.Platform.QUEST_3)
	assert(quest["max_splats"] == 200000)
	assert(quest["workgroup_divisor"] == 4)
	assert(quest["foveation_enabled"])
	assert(quest["thermal_downgrade_enabled"])
	var webgpu: Dictionary = optimizer.apply_preset(FoveaMobileOptimizer.Platform.WEBGPU)
	assert(webgpu["max_splats"] == 50000)
	assert(not webgpu["compute_shaders_enabled"])
	assert(webgpu["fallback_renderer_enabled"])
	print("PASS: mobile presets expose deterministic runtime configuration")
	quit(0)
