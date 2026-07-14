extends SceneTree

const SkinBinder = preload("res://addons/foveacore/scripts/advanced/fovea_splat_skin_binder.gd")
const GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

func _init() -> void:

	var splat: GaussianSplat = GaussianSplatScript.new(Vector3.ZERO)
	var bone_positions := PackedVector3Array([Vector3.ZERO, Vector3(2.0, 0.0, 0.0)])
	SkinBinder._bind_single_splat(splat, bone_positions, 2)
	assert(splat.bone_indices[0] == 0)
	assert(is_equal_approx(splat.bone_weights[0] + splat.bone_weights[1], 1.0))
	assert(splat.bind_pose_position == Vector3.ZERO)
	print("PASS: splat skin binding stores normalized typed weights")
	quit(0)
