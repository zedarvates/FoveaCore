class_name FoveaMobileOptimizer
extends FoveaMobilePresets

## FoveaEngine — Mobile/Quest/WebGPU (items 292-309)
## Quality presets and platform-specific shader variants.

enum Platform { DESKTOP, QUEST_3, WEBGPU, MOBILE_ARM }

@export var platform: Platform = Platform.DESKTOP

var max_splats: int = 500000
var workgroup_divisor: int = 1
var foveation_enabled: bool = false
var thermal_downgrade_enabled: bool = false
var compute_shaders_enabled: bool = true
var fp16_enabled: bool = false
var fallback_renderer_enabled: bool = false

func apply_preset(target_platform: Platform = platform) -> Dictionary:
	_reset_runtime_flags()
	match target_platform:
		Platform.QUEST_3:
			max_splats = 200000
			reduce_workgroups(4)  # Interleaved sorting ×4
			enable_foveation(true)
			enable_thermal_downgrade(true)
		Platform.WEBGPU:
			max_splats = 50000
			disable_compute_shaders(true)
			use_fallback_renderer(true)
		Platform.MOBILE_ARM:
			max_splats = 100000
			reduce_workgroups(2)
			reduce_precision_fp16(true)
	platform = target_platform
	var configuration: Dictionary = get_configuration()
	print("FoveaMobileOptimizer: configured %s preset: %s" % [Platform.keys()[platform], configuration])
	return configuration

func _reset_runtime_flags() -> void:
	max_splats = 500000
	workgroup_divisor = 1
	foveation_enabled = false
	thermal_downgrade_enabled = false
	compute_shaders_enabled = true
	fp16_enabled = false
	fallback_renderer_enabled = false

func reduce_workgroups(factor: int) -> void:
	workgroup_divisor = maxi(factor, 1)

func enable_foveation(enabled: bool) -> void:
	foveation_enabled = enabled

func enable_thermal_downgrade(enabled: bool) -> void:
	thermal_downgrade_enabled = enabled

func disable_compute_shaders(enabled: bool) -> void:
	compute_shaders_enabled = not enabled

func reduce_precision_fp16(enabled: bool) -> void:
	fp16_enabled = enabled

func use_fallback_renderer(enabled: bool) -> void:
	fallback_renderer_enabled = enabled

func get_configuration() -> Dictionary:
	return {
		"max_splats": max_splats,
		"workgroup_divisor": workgroup_divisor,
		"foveation_enabled": foveation_enabled,
		"thermal_downgrade_enabled": thermal_downgrade_enabled,
		"compute_shaders_enabled": compute_shaders_enabled,
		"fp16_enabled": fp16_enabled,
		"fallback_renderer_enabled": fallback_renderer_enabled,
	}
