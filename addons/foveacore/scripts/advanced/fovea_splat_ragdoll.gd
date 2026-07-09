class_name FoveaSplatRagdoll
extends Node3D

## FoveaEngine — Splat Ragdoll (item 177)
## Blends between animation-driven skinning and physics simulation.

@export var skeleton: Skeleton3D = null
@export var animation_weight: float = 1.0  # 1 = full anim, 0 = full physics
@export var physics_blend_speed: float = 1.0

var _bone_anim_poses: Dictionary = {}  # bone_idx → Transform3D
var _bone_phys_poses: Dictionary = {}  # bone_idx → Transform3D

func blend_splat(splat: Dictionary, bone_idx: int, delta: float) -> Dictionary:
	"""Blend between animation and physics poses for a given bone."""
	if not skeleton: return splat
	
	var anim_xform = _bone_anim_poses.get(bone_idx, skeleton.get_bone_global_pose(bone_idx))
	var phys_xform = _bone_phys_poses.get(bone_idx, anim_xform)
	
	# Blend translation + rotation
	var blended = anim_xform.interpolate_with(phys_xform, 1.0 - animation_weight)
	
	# Store blend in splat
	splat["_ragdoll_blend"] = animation_weight
	return splat

func set_anim_pose(bone_idx: int, pose: Transform3D) -> void:
	_bone_anim_poses[bone_idx] = pose

func set_phys_pose(bone_idx: int, pose: Transform3D) -> void:
	_bone_phys_poses[bone_idx] = pose
