extends SceneTree

const LodStretchAnimator = preload("res://addons/foveacore/scripts/advanced/fovea_lod_stretch_animator.gd")
const GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

func _init() -> void:

	var animator: FoveaLodStretchAnimator = LodStretchAnimator.new()
	animator.amplitude = 0.5
	var splat: GaussianSplat = GaussianSplatScript.new(Vector3(1.0, 0.0, 0.0))
	animator._apply_to_splat(splat, 0.25, 1.0)
	assert(splat.scale.x > 0.0 and splat.scale.y > 0.0 and splat.scale.z > 0.0)
	print("PASS: LOD stretch preserves positive scale")
	animator.free()
	splat = null
	await process_frame
	quit(0)
