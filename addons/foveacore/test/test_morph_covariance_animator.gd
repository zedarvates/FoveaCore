extends SceneTree

const MorphAnimator = preload("res://addons/foveacore/scripts/advanced/fovea_morph_covariance_animator.gd")
const GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

func _init() -> void:

	var animator: FoveaMorphCovarianceAnimator = MorphAnimator.new()
	animator.amplitude = 0.5
	var splat: GaussianSplat = GaussianSplatScript.new(Vector3(2.0, 1.0, 0.0))
	animator._apply_to_splat(splat, 0.25, 1.0)
	assert(splat.scale.x > 0.0 and splat.covariance.x > 0.0)
	print("PASS: covariance morph keeps valid derived data")
	quit(0)
