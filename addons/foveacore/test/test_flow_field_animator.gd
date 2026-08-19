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

	# Test Preset.CURRENT (painted flow vector stored in normal)
	animator.preset = FoveaFlowFieldAnimator.Preset.CURRENT
	splat.position = Vector3(1.0, 2.0, 3.0)
	splat.normal = Vector3(0.0, 1.0, 0.0)
	var start_pos: Vector3 = splat.position
	animator._apply_to_splat(splat, 0.25, 1.0)
	assert(splat.position.y != start_pos.y)

	animator.free()
	splat = null
	print("PASS: typed flow modifier changes transient position (WIND and CURRENT presets)")
	await process_frame
	quit(0)
