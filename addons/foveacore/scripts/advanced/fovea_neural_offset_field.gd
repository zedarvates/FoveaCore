extends Resource
class_name FoveaNeuralOffsetField

## FoveaNeuralOffsetField — Phase 7.5 Neural Offset Field (baked variant).
##
## Stores a pre-baked grid of per-cell, per-frame displacement vectors
## (offline output of a ComfyUI/neural_style_bridge.gd distillation pass, or
## any other offline motion source — see roadmap Phase 7.5) and samples it at
## runtime with trilinear spatial interpolation + nearest-frame temporal
## lookup. This is the "zero runtime inference" half of the roadmap: no MLP
## evaluation happens here, only a texture-like lookup, so it is cheap enough
## to run per-splat on the CPU pipeline (same constraint as the other Phase 7
## animators). A true runtime MLP (hash-grid encoding, weights evaluated in a
## compute shader) is the deferred stretch goal.

## Grid resolution along each axis. Total cells = grid_dims.x * grid_dims.y * grid_dims.z.
@export var grid_dims: Vector3i = Vector3i(2, 2, 2)
## World-space AABB the grid covers. Positions outside are clamped to the border cell.
@export var bounds_min: Vector3 = Vector3(-1, -1, -1)
@export var bounds_max: Vector3 = Vector3(1, 1, 1)
## Number of baked time frames (>= 1). A single-frame field is a static offset field.
@export var frame_count: int = 1
## Playback rate for the baked frames, in frames per second.
@export var fps: float = 24.0
## Flattened offsets, size == grid_dims.x*grid_dims.y*grid_dims.z*frame_count.
## Index = frame * (nx*ny*nz) + (z*ny + y)*nx + x.
@export var offsets: PackedVector3Array = PackedVector3Array()

func _cell_index(x: int, y: int, z: int, frame: int) -> int:
	var cells_per_frame: int = grid_dims.x * grid_dims.y * grid_dims.z
	return frame * cells_per_frame + (z * grid_dims.y + y) * grid_dims.x + x

func _get_offset(x: int, y: int, z: int, frame: int) -> Vector3:
	x = clampi(x, 0, grid_dims.x - 1)
	y = clampi(y, 0, grid_dims.y - 1)
	z = clampi(z, 0, grid_dims.z - 1)
	frame = clampi(frame, 0, max(frame_count - 1, 0))
	var idx := _cell_index(x, y, z, frame)
	if idx < 0 or idx >= offsets.size():
		return Vector3.ZERO
	return offsets[idx]

## Samples the field at a world-space position and time, with trilinear
## spatial interpolation and nearest-frame temporal lookup.
func sample(world_pos: Vector3, time: float) -> Vector3:
	if offsets.is_empty() or grid_dims.x < 1 or grid_dims.y < 1 or grid_dims.z < 1:
		return Vector3.ZERO

	var extent: Vector3 = bounds_max - bounds_min
	var norm := Vector3(
		0.0 if extent.x <= 0.0001 else (world_pos.x - bounds_min.x) / extent.x,
		0.0 if extent.y <= 0.0001 else (world_pos.y - bounds_min.y) / extent.y,
		0.0 if extent.z <= 0.0001 else (world_pos.z - bounds_min.z) / extent.z
	)
	norm = Vector3(clampf(norm.x, 0.0, 1.0), clampf(norm.y, 0.0, 1.0), clampf(norm.z, 0.0, 1.0))

	var fx: float = norm.x * float(grid_dims.x - 1)
	var fy: float = norm.y * float(grid_dims.y - 1)
	var fz: float = norm.z * float(grid_dims.z - 1)

	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var z0 := int(floor(fz))
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var tz: float = fz - float(z0)

	var frame: int = 0
	if frame_count > 1:
		frame = int(floor(fmod(time * fps, float(frame_count))))
		if frame < 0:
			frame += frame_count

	var c000 := _get_offset(x0, y0, z0, frame)
	var c100 := _get_offset(x0 + 1, y0, z0, frame)
	var c010 := _get_offset(x0, y0 + 1, z0, frame)
	var c110 := _get_offset(x0 + 1, y0 + 1, z0, frame)
	var c001 := _get_offset(x0, y0, z0 + 1, frame)
	var c101 := _get_offset(x0 + 1, y0, z0 + 1, frame)
	var c011 := _get_offset(x0, y0 + 1, z0 + 1, frame)
	var c111 := _get_offset(x0 + 1, y0 + 1, z0 + 1, frame)

	var c00: Vector3 = c000.lerp(c100, tx)
	var c10: Vector3 = c010.lerp(c110, tx)
	var c01: Vector3 = c001.lerp(c101, tx)
	var c11: Vector3 = c011.lerp(c111, tx)

	var c0: Vector3 = c00.lerp(c10, ty)
	var c1: Vector3 = c01.lerp(c11, ty)

	return c0.lerp(c1, tz)
