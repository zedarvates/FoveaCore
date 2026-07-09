class_name FoveaBoneSkinAnimation
extends Node3D

## FoveaEngine — Bone Skin Animation
## Linear Blend Skinning (LBS) of splats to a Skeleton3D.

@export var enabled: bool = true
@export var skeleton: Skeleton3D = null
@export var bone_count: int = 0

# Per-splat skinning data: bone_indices (4 uints), bone_weights (4 floats)
var _bone_data: Dictionary = {}  # instance_id → {indices: PackedInt32Array, weights: PackedFloat32Array}

func bind_splats(splat_data: Array[Dictionary], skeleton_node: Skeleton3D) -> void:
	"""Bind splats to skeleton using distance-based heuristic."""
	skeleton = skeleton_node
	bone_count = skeleton.get_bone_count()
	
	# For each splat, find the 4 nearest bones
	for splat in splat_data:
		var pos = splat.get("position", Vector3.ZERO)
		var nearest = _find_nearest_bones(pos, 4)
		var instance_id = splat.get("instance_id", 0)
		_bone_data[instance_id] = nearest

func _find_nearest_bones(pos: Vector3, k: int) -> Dictionary:
	"""Find k nearest bones and compute weights (sum = 1)."""
	var distances: Array[float] = []
	var indices: Array[int] = []
	
	if skeleton == null:
		return {"indices": [0,0,0,0], "weights": [1.0,0.0,0.0,0.0]}
	
	for i in range(min(bone_count, 64)):
		var bone_pos = skeleton.get_bone_global_pose(i).origin
		var dist = pos.distance_squared_to(bone_pos)
		distances.append(dist)
		indices.append(i)
	
	# Sort by distance ascending, keep k nearest
	var pairs: Array[Array] = []
	for i in indices:
		pairs.append([i, distances[i]])
	pairs.sort_custom(func(a, b): return a[1] < b[1])
	
	var selected = pairs.slice(0, k)
	var weights: Array[float] = []
	var selected_idx: Array[int] = []
	var total_inv: float = 0.0
	
	for pair in selected:
		var inv = 1.0 / max(pair[1], 0.001)
		weights.append(inv)
		selected_idx.append(pair[0])
		total_inv += inv
	
	# Normalize
	for i in range(weights.size()):
		weights[i] /= max(total_inv, 0.001)
	
	# Pad to 4
	while weights.size() < 4:
		weights.push_back(0.0)
		selected_idx.push_back(0)
	
	return {"indices": selected_idx, "weights": weights}

func apply_animation(subsystem: FoveaAnimationSubsystem, delta: float) -> void:
	# Skinning is applied each frame by reading the skeleton pose
	pass

func modify_splat(splat: Dictionary, delta: float, subsystem: FoveaAnimationSubsystem) -> Dictionary:
	if not enabled or skeleton == null or bone_count == 0:
		return splat
	
	var instance_id = splat.get("instance_id", 0)
	var bone_info = _bone_data.get(instance_id)
	if bone_info == null:
		return splat
	
	var bind_pos = splat.get("_bind_position", splat.get("position", Vector3.ZERO))
	var indices = bone_info["indices"]
	var weights = bone_info["weights"]
	
	# Linear Blend Skinning
	var skinned_pos = Vector3.ZERO
	for i in range(4):
		if weights[i] > 0.001 and indices[i] < bone_count:
			var bone_xform = skeleton.get_bone_global_pose(indices[i])
			skinned_pos += bone_xform * bind_pos * weights[i]
	
	splat["position"] = skinned_pos
	return splat
