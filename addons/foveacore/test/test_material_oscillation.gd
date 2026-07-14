extends SceneTree

const MaterialOscillation = preload("res://addons/foveacore/scripts/advanced/fovea_material_oscillation.gd")
const GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

func _init() -> void:

	var animator: FoveaMaterialOscillation = MaterialOscillation.new()
	var splat: GaussianSplat = GaussianSplatScript.new()
	animator._apply_to_splat(splat, 0.25, 1.0)
	assert(splat.opacity >= 0.0 and splat.opacity <= 1.0)
	assert(splat.color is Color)
	print("PASS: material oscillation keeps typed color and opacity valid")
	quit(0)
