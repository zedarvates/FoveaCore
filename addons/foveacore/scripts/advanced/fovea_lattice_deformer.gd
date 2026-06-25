class_name FoveaLatticeDeformer
extends Node3D

## FoveaEngine — Lattice Cage Deformer (Free-Form Deformation)
## Warp Gaussian Splat coordinates using an 8-point trilinear lattice cage (2x2x2).

@export var enabled: bool = true
@export var lattice_size: Vector3 = Vector3(2.0, 2.0, 2.0)
@export var max_splats_per_frame: int = 50000

## 8 offsets for control points. Ordering:
## 0: (-x, -y, -z), 1: (+x, -y, -z), 2: (-x, +y, -z), 3: (+x, +y, -z)
## 4: (-x, -y, +z), 5: (+x, -y, +z), 6: (-x, +y, +z), 7: (+x, +y, +z)
@export var control_offsets: Array[Vector3] = [
	Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
	Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO
]

var _renderer: FoveaCoreSplatRenderer = null
var _original_transforms_cache: Array[Transform3D] = []
var _last_instance_id: int = 0

func _ready() -> void:
	# Keep control_offsets size validated
	if control_offsets.size() != 8:
		control_offsets.resize(8)
		for i in 8:
			control_offsets[i] = Vector3.ZERO
			
	var parent := get_parent()
	if parent is FoveaCoreSplatRenderer:
		_renderer = parent
		print("FoveaLatticeDeformer: Connected to FoveaCoreSplatRenderer '%s'" % parent.name)

func _process(_delta: float) -> void:
	if not enabled or _renderer == null or _renderer.multimesh == null:
		return
	var mm: MultiMesh = _renderer.multimesh
	if mm.instance_count == 0:
		return
		
	var current_id := mm.get_instance_id()
	if _original_transforms_cache.is_empty() or current_id != _last_instance_id or _original_transforms_cache.size() != mm.instance_count:
		_sync_transforms(mm)
		
	if _original_transforms_cache.is_empty():
		return
		
	_apply_lattice_deformation(mm)

func _sync_transforms(mm: MultiMesh) -> void:
	_last_instance_id = mm.get_instance_id()
	_original_transforms_cache.clear()
	_original_transforms_cache.resize(mm.instance_count)
	for i in mm.instance_count:
		_original_transforms_cache[i] = mm.get_instance_transform(i)
	print("FoveaLatticeDeformer: Synced %d original transforms." % mm.instance_count)

func _apply_lattice_deformation(mm: MultiMesh) -> void:
	var count := mm.instance_count
	var limit := count if max_splats_per_frame <= 0 else mini(count, max_splats_per_frame)
	
	var h_size := lattice_size * 0.5
	var local_points: Array[Vector3] = []
	local_points.resize(8)
	
	# Compute current positions of control points in lattice local space
	local_points[0] = Vector3(-h_size.x, -h_size.y, -h_size.z) + control_offsets[0]
	local_points[1] = Vector3( h_size.x, -h_size.y, -h_size.z) + control_offsets[1]
	local_points[2] = Vector3(-h_size.x,  h_size.y, -h_size.z) + control_offsets[2]
	local_points[3] = Vector3( h_size.x,  h_size.y, -h_size.z) + control_offsets[3]
	local_points[4] = Vector3(-h_size.x, -h_size.y,  h_size.z) + control_offsets[4]
	local_points[5] = Vector3( h_size.x, -h_size.y,  h_size.z) + control_offsets[5]
	local_points[6] = Vector3(-h_size.x,  h_size.y,  h_size.z) + control_offsets[6]
	local_points[7] = Vector3( h_size.x,  h_size.y,  h_size.z) + control_offsets[7]
	
	var deformer_inv_xf := global_transform.affine_inverse()
	var deformer_xf := global_transform
	
	var stride := FoveaMultiMeshBulk.stride_of(mm)
	var buf := mm.buffer
	
	for i in limit:
		if i >= _original_transforms_cache.size():
			break
			
		var orig_xf := _original_transforms_cache[i]
		var world_pos := orig_xf.origin
		
		# 1. Map world coordinates to lattice local coordinates
		var local_pos := deformer_inv_xf * world_pos
		
		# 2. Normalize coordinates into [0, 1] range inside lattice box
		var u := clampf((local_pos.x + h_size.x) / lattice_size.x, 0.0, 1.0)
		var v := clampf((local_pos.y + h_size.y) / lattice_size.y, 0.0, 1.0)
		var w := clampf((local_pos.z + h_size.z) / lattice_size.z, 0.0, 1.0)
		
		# 3. Trilinear interpolation of deformed control point positions
		var interp_pos := (
			(1.0 - u) * (1.0 - v) * (1.0 - w) * local_points[0] +
			u * (1.0 - v) * (1.0 - w) * local_points[1] +
			(1.0 - u) * v * (1.0 - w) * local_points[2] +
			u * v * (1.0 - w) * local_points[3] +
			(1.0 - u) * (1.0 - v) * w * local_points[4] +
			u * (1.0 - v) * w * local_points[5] +
			(1.0 - u) * v * w * local_points[6] +
			u * v * w * local_points[7]
		)
		
		# 4. Convert deformed local position back to world coordinates
		var deformed_world_pos := deformer_xf * interp_pos
		
		var final_xf := orig_xf
		final_xf.origin = deformed_world_pos
		
		FoveaMultiMeshBulk.write_transform(buf, i * stride, final_xf)
		
	mm.buffer = buf
