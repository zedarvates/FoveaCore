extends SceneTree

const MaterialOscillation = preload("res://addons/foveacore/scripts/advanced/fovea_material_oscillation.gd")
const GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

func _init() -> void:
	var animator: FoveaMaterialOscillation = MaterialOscillation.new()
	var splat: GaussianSplat = GaussianSplatScript.new()
	animator._apply_to_splat(splat, 0.25, 1.0)
	assert(splat.opacity >= 0.0 and splat.opacity <= 1.0)
	assert(splat.color is Color)

	# Test preset switching
	animator.style_preset = FoveaMaterialOscillation.StylePreset.LIVING_WATERCOLOR
	assert(animator.frequency == 1.0)
	animator.style_preset = FoveaMaterialOscillation.StylePreset.PULSING_METAL
	assert(animator.frequency == 2.5)

	animator.free()
	splat = null
	print("PASS: material oscillation keeps typed color and opacity valid and applies presets")
	await process_frame
	quit(0)
