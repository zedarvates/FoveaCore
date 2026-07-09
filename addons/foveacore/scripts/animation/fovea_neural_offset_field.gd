class_name FoveaNeuralOffsetField
extends Resource

## FoveaEngine — Neural Offset Field
## A 3D grid of offset vectors (baked from neural network or STAR cache).
## Sampled trilinearly to produce smooth per-splat displacements.

@export var grid_resolution: int = 16
@export var grid_bounds: AABB = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
@export var frames: Array[Array] = []  # Array of frames, each frame is Array of Vector3 offsets

var _grid: Array[Vector3] = []

func _init() -> void:
	pass

func bake_from_numpy(data: PackedFloat32Array, resolution: int) -> void:
	"""Import baked offsets from Python/NumPy export."""
	grid_resolution = resolution
	_grid.resize(resolution * resolution * resolution)
	for i in range(min(data.size(), _grid.size() * 3)):
		var idx = i / 3
		var axis = i % 3
		var v = _grid[idx]
		match axis:
			0: v.x = data[i]
			1: v.y = data[i]
			2: v.z = data[i]
		_grid[idx] = v

func sample(world_pos: Vector3, time: float = 0.0) -> Vector3:
	"""Trilinear sample of the offset field at a world position."""
	if _grid.size() == 0:
		return Vector3.ZERO
	
	var local_pos = world_pos - grid_bounds.position
	var frac = local_pos / max(grid_bounds.size, Vector3.ONE * 0.001)
	var uvw = Vector3(
		clamp(frac.x, 0.0, 0.999),
		clamp(frac.y, 0.0, 0.999),
		clamp(frac.z, 0.0, 0.999)
	) * (grid_resolution - 1)
	
	var ix = int(uvw.x)
	var iy = int(uvw.y)
	var iz = int(uvw.z)
	var fx = uvw.x - ix
	var fy = uvw.y - iy
	var fz = uvw.z - iz
	
	# Trilinear interpolation
	var s = grid_resolution
	return _trilerp(ix, iy, iz, fx, fy, fz, s)

func _trilerp(ix: int, iy: int, iz: int, fx: float, fy: float, fz: float, s: int) -> Vector3:
	var idx = iz * s * s + iy * s + ix
	if idx + s*s + s + 1 >= _grid.size():
		return Vector3.ZERO
	
	# 8 corners of the grid cell
	var c000 = _grid[idx]
	var c100 = _grid[idx + 1]
	var c010 = _grid[idx + s]
	var c110 = _grid[idx + s + 1]
	var c001 = _grid[idx + s*s]
	var c101 = _grid[idx + s*s + 1]
	var c011 = _grid[idx + s*s + s]
	var c111 = _grid[idx + s*s + s + 1]
	
	# Interpolate along X
	var c00 = c000.lerp(c100, fx)
	var c01 = c001.lerp(c101, fx)
	var c10 = c010.lerp(c110, fx)
	var c11 = c011.lerp(c111, fx)
	
	# Interpolate along Y
	var c0 = c00.lerp(c10, fy)
	var c1 = c01.lerp(c11, fy)
	
	# Interpolate along Z
	return c0.lerp(c1, fz)


class FoveaNeuralOffsetAnimator extends Node3D:
	## Applies a FoveaNeuralOffsetField to splats.
	
	@export var enabled: bool = true
	@export var offset_field: FoveaNeuralOffsetField = null
	@export var intensity: float = 1.0
	
	func modify_splat(splat: Dictionary, delta: float, subsystem: FoveaAnimationSubsystem) -> Dictionary:
		if not enabled or offset_field == null:
			return splat
		var pos = splat.get("position", Vector3.ZERO)
		var offset = offset_field.sample(pos, subsystem.anim_time) * intensity
		splat["position"] = pos + offset
		return splat
