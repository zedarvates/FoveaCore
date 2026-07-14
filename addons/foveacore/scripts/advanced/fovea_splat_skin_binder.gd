extends RefCounted
class_name FoveaSplatSkinBinder

## FoveaSplatSkinBinder — Phase 7.6 Bone-Driven Splat Animation, binding step.
##
## One-shot (author-time) utility: for each splat, finds the [param max_bones]
## nearest bones of a [Skeleton3D] (by rest-pose world distance) and stores
## normalized inverse-distance weights on the splat, plus its world position
## at bind time as [member GaussianSplat.bind_pose_position]. The skeleton
## MUST be in its rest pose when this runs (bind pose == rest pose is the
## standard skinning assumption).
##
## This is intentionally a simple heuristic (inverse-distance weighting to
## the nearest bones), not heat-diffusion/geodesic binding — sufficient for a
## first working GPU-skinning-equivalent CPU path per the roadmap; a proper
## authoring tool (paint weights, heat diffusion) is future work.

## Binds every splat in [param splats] to the [param skeleton]'s rest pose.
## Mutates each splat's bone_indices/bone_weights/bind_pose_position in place.
static func bind_splats(splats: Array[GaussianSplat], skeleton: Skeleton3D, max_bones: int = 4) -> void:
	if skeleton == null or skeleton.get_bone_count() == 0:
		return

	var bone_count: int = skeleton.get_bone_count()
	var bone_rest_world: PackedVector3Array = PackedVector3Array()
	bone_rest_world.resize(bone_count)
	for i in range(bone_count):
		var rest_local: Transform3D = skeleton.get_bone_global_rest(i)
		bone_rest_world[i] = (skeleton.global_transform * rest_local).origin

	for splat: GaussianSplat in splats:
		_bind_single_splat(splat, bone_rest_world, max_bones)

## Binds a single splat given precomputed bone rest-pose world positions.
## Exposed separately so tests can exercise the weighting math directly.
static func _bind_single_splat(splat: GaussianSplat, bone_rest_world: PackedVector3Array, max_bones: int) -> void:
	var bone_count: int = bone_rest_world.size()
	var candidate_indices: Array[int] = []
	var candidate_dists: Array[float] = []
	for i in range(bone_count):
		candidate_indices.append(i)
		candidate_dists.append(splat.position.distance_to(bone_rest_world[i]))

	# Partial selection sort for the max_bones nearest (bone counts are small,
	# so an O(n * max_bones) selection is fine and avoids allocating a sorter).
	var picked: int = min(max_bones, bone_count)
	for slot in range(picked):
		var best: int = slot
		for j in range(slot + 1, candidate_indices.size()):
			if candidate_dists[j] < candidate_dists[best]:
				best = j
		if best != slot:
			var tmp_i: int = candidate_indices[slot]
			candidate_indices[slot] = candidate_indices[best]
			candidate_indices[best] = tmp_i
			var tmp_d: float = candidate_dists[slot]
			candidate_dists[slot] = candidate_dists[best]
			candidate_dists[best] = tmp_d

	var indices := PackedInt32Array([-1, -1, -1, -1])
	var weights := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var weight_sum: float = 0.0
	const EPSILON: float = 0.0001
	for slot in range(picked):
		var w: float = 1.0 / (candidate_dists[slot] + EPSILON)
		indices[slot] = candidate_indices[slot]
		weights[slot] = w
		weight_sum += w

	if weight_sum > 0.0:
		for slot in range(picked):
			weights[slot] /= weight_sum

	splat.bone_indices = indices
	splat.bone_weights = weights
	splat.bind_pose_position = splat.position
