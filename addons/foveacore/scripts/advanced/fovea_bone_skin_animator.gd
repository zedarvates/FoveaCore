extends Node3D
class_name FoveaBoneSkinAnimator

## FoveaBoneSkinAnimator — Phase 7.6 Bone-Driven Splat Animation, runtime step.
##
## Registers a modifier on FoveaAnimationSubsystem that performs linear blend
## skinning (LBS) on splats bound via FoveaSplatSkinBinder: for each bound
## splat, blends the transform of its up-to-4 influencing bones and applies
## the result to bind_pose_position — this is the CPU equivalent of
## `pos = Σ wᵢ (Bᵢ · pos)` from the roadmap.
##
## The rotation part of the blended bone transform is also applied to
## splat.rotation (composed, same quaternion pattern as
## FoveaMorphCovarianceAnimator's WOBBLE preset in Phase 7.2) — this is the
## "Σ must be transformed too" requirement noted in the roadmap: since this
## pipeline derives covariance from scale+rotation via compute_derived(),
## rotating splat.rotation by the bone's blended rotation IS the covariance
## transform Σ' = R Σ Rᵀ for this CPU representation.
##
## Unbound splats (bone_weights all zero) are left completely untouched.

@export var skeleton_path: NodePath
## Blend factor between the splat's un-skinned position/rotation and the
## fully-skinned result. 1.0 = fully bone-driven (typical for a rigged
## character); lower values let skinning fade in/out (e.g. ragdoll blending).
@export_range(0.0, 1.0) var skin_weight: float = 1.0

var _skeleton: Skeleton3D = null
var _modifier_callable: Callable

func _ready() -> void:
	if skeleton_path != NodePath():
		_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	_modifier_callable = _apply_to_splat
	var mgr := _find_manager()
	if mgr:
		var anim: FoveaAnimationSubsystem = mgr.get_animation_subsystem()
		if anim:
			anim.register_modifier(_modifier_callable)

func _exit_tree() -> void:
	var mgr := _find_manager()
	if mgr:
		var anim: FoveaAnimationSubsystem = mgr.get_animation_subsystem()
		if anim:
			anim.unregister_modifier(_modifier_callable)

func _find_manager() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("FoveaCoreManager")

func _apply_to_splat(splat: GaussianSplat, _time: float, global_intensity: float) -> void:
	if _skeleton == null:
		return
	var total_weight: float = splat.bone_weights[0] + splat.bone_weights[1] + splat.bone_weights[2] + splat.bone_weights[3]
	if total_weight <= 0.0001:
		return

	var skinned := skin_position_and_rotation(_skeleton, splat.bind_pose_position, splat.bone_indices, splat.bone_weights, splat.rotation)
	var blend: float = clampf(skin_weight * global_intensity, 0.0, 1.0)
	splat.position = splat.position.lerp(skinned["position"], blend)
	splat.rotation = splat.rotation.slerp(skinned["rotation"], blend)
	splat.compute_derived()

## Computes the linear-blend-skinned world position and a bone-blended
## rotation for a single point, given a skeleton and up-to-4 bone
## influences. Static/pure so it can be unit-tested without a running
## FoveaAnimationSubsystem or scene tree wiring.
static func skin_position_and_rotation(
	skeleton: Skeleton3D,
	bind_pose_world_position: Vector3,
	bone_indices: PackedInt32Array,
	bone_weights: PackedFloat32Array,
	base_rotation: Quaternion
) -> Dictionary:
	var skeleton_xform: Transform3D = skeleton.global_transform
	var local_bind: Vector3 = skeleton_xform.affine_inverse() * bind_pose_world_position

	var blended_local := Vector3.ZERO
	var blended_rotation := Quaternion.IDENTITY
	var rotation_weight_sum: float = 0.0
	var bone_count: int = skeleton.get_bone_count()

	for i in range(4):
		var bone_idx: int = bone_indices[i]
		var w: float = bone_weights[i]
		if bone_idx < 0 or bone_idx >= bone_count or w <= 0.0:
			continue
		var rest: Transform3D = skeleton.get_bone_global_rest(bone_idx)
		var pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
		var skin_xform: Transform3D = pose * rest.affine_inverse()

		blended_local += w * (skin_xform * local_bind)

		var rot: Quaternion = skin_xform.basis.get_rotation_quaternion()
		if rotation_weight_sum <= 0.0:
			blended_rotation = rot
		else:
			blended_rotation = blended_rotation.slerp(rot, w / (rotation_weight_sum + w))
		rotation_weight_sum += w

	var skinned_world: Vector3 = skeleton_xform * blended_local
	var final_rotation: Quaternion = (blended_rotation * base_rotation).normalized() if rotation_weight_sum > 0.0 else base_rotation

	return {"position": skinned_world, "rotation": final_rotation}
