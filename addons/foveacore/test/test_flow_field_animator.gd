extends SceneTree

const FlowAnimator = preload("res://addons/foveacore/scripts/advanced/fovea_flow_field_animator.gd")
const GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

func _init() -> void:

	var animator: FoveaFlowFieldAnimator = FlowAnimator.new()
	animator._ready()
	var splat: GaussianSplat = GaussianSplatScript.new(Vector3(1.0, 2.0, 3.0))
	var original_position: Vector3 = splat.position
	animator._apply_to_splat(splat, 1.0, 1.0)
	assert(splat.position != original_position)
	print("PASS: typed flow modifier changes transient position")
	quit(0)
