extends SceneTree

const FlipbookAnimator = preload("res://addons/foveacore/scripts/advanced/fovea_flipbook_animator.gd")
const GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

func _init() -> void:

	var animator: FoveaFlipbookAnimator = FlipbookAnimator.new()
	var active: GaussianSplat = GaussianSplatScript.new()
	active.flipbook_frame = 0
	active.flipbook_frame_count = 2
	var inactive: GaussianSplat = GaussianSplatScript.new()
	inactive.flipbook_frame = 1
	inactive.flipbook_frame_count = 2
	animator._apply_to_splat(active, 0.0, 1.0)
	animator._apply_to_splat(inactive, 0.0, 1.0)
	assert(active.opacity > 0.0)
	assert(is_zero_approx(inactive.opacity))
	print("PASS: flipbook selects exactly the active frame")
	quit(0)
