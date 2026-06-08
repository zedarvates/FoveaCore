extends Node3D
class_name FoveaSplatCloth3D

## FoveaSplatCloth3D — Draping and Cloth Simulation for Gaussian Splats
## Binds splats to Godot's SoftBody3D physics or runs an internal Verlet mass-spring solver.

@export var splattable: FoveaSplattable

@export_group("SoftBody3D Coupling Mode")
## Path to a SoftBody3D node in the scene. If set, this mode is prioritized.
@export var soft_body_path: NodePath

@export_group("Internal Simulation Mode")
## Run a self-contained Verlet mass-spring solver on a generated grid.
@export var enable_internal_sim: bool = false
@export var grid_size: Vector2i = Vector2i(8, 8)
@export var grid_dimensions: Vector2 = Vector2(2.0, 2.0)
## Indices of the grid points that are anchored (pinned) in local space.
@export var anchor_points: Array[int] = [0, 7] # Pinned top corners by default for 8x8

@export_group("Physics Parameters")
@export var gravity: Vector3 = Vector3(0, -9.81, 0)
@export var wind_force: Vector3 = Vector3.ZERO
@export_range(0.0, 1.0) var damping: float = 0.05 # Air resistance / weight damping
@export_range(0.0, 1.0) var stiffness: float = 0.8 # Constraint solving stiffness
@export var mass_per_point: float = 0.1
@export var solver_iterations: int = 4

# Internal physics representation
var _points: Array[Dictionary] = [] # keys: "pos", "prev_pos", "mass", "is_pinned", "init_local_pos"
var _springs: Array[Dictionary] = [] # keys: "p1", "p2", "rest_len"
var _bindings: Array[Dictionary] = [] # keys: "splat_index", "point_index", "local_offset"
var _is_bound: bool = false

# Cache reference to SoftBody3D if coupled
var _soft_body_ref: SoftBody3D = null

func _ready() -> void:
	if not splattable:
		# Try to auto-detect parent
		var parent = get_parent()
		if parent is FoveaSplattable:
			splattable = parent

	if not soft_body_path.is_empty():
		_soft_body_ref = get_node_or_null(soft_body_path) as SoftBody3D
		if _soft_body_ref:
			print("FoveaSplatCloth3D: Pinned to SoftBody3D: ", _soft_body_ref.name)
		else:
			push_error("FoveaSplatCloth3D: SoftBody3D not found at path: ", soft_body_path)

	if enable_internal_sim and not _soft_body_ref:
		_initialize_internal_sim()

func _physics_process(delta: float) -> void:
	if delta <= 0.0: return
	
	if _soft_body_ref:
		_update_soft_body_binding()
	elif enable_internal_sim:
		_step_internal_sim(delta)
		_update_internal_sim_binding()

func _process(delta: float) -> void:
	if not _is_bound:
		_try_bind_splats()

## Setup internal Verlet mass-spring grid representation
func _initialize_internal_sim() -> void:
	_points.clear()
	_springs.clear()
	
	var step_x = grid_dimensions.x / float(grid_size.x - 1)
	var step_y = grid_dimensions.y / float(grid_size.y - 1)
	
	# Create points (centered locally on X, hanging down on Y)
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var local_pos = Vector3(
				(x * step_x) - (grid_dimensions.x / 2.0),
				-(y * step_y),
				0.0
			)
			var idx = y * grid_size.x + x
			var is_pinned = idx in anchor_points
			
			var pt = {
				"pos": global_transform * local_pos,
				"prev_pos": global_transform * local_pos,
				"mass": mass_per_point,
				"is_pinned": is_pinned,
				"init_local_pos": local_pos
			}
			_points.append(pt)
			
	# Generate springs
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var idx = y * grid_size.x + x
			
			# Structural: horizontal
			if x < grid_size.x - 1:
				_add_spring(idx, idx + 1)
			# Structural: vertical
			if y < grid_size.y - 1:
				_add_spring(idx, idx + grid_size.x)
				
			# Shear: diagonals
			if x < grid_size.x - 1 and y < grid_size.y - 1:
				_add_spring(idx, idx + grid_size.x + 1)
				_add_spring(idx + 1, idx + grid_size.x)
				
			# Bending: skip 1 node
			if x < grid_size.x - 2:
				_add_spring(idx, idx + 2)
			if y < grid_size.y - 2:
				_add_spring(idx, idx + 2 * grid_size.x)
				
	print("FoveaSplatCloth3D: Internal mass-spring grid initialized. Points: ", _points.size(), " Springs: ", _springs.size())

func _add_spring(p1: int, p2: int) -> void:
	var dist = _points[p1].pos.distance_to(_points[p2].pos)
	_springs.append({
		"p1": p1,
		"p2": p2,
		"rest_len": dist
	})

## Perform one Verlet integration and constraint solving step
func _step_internal_sim(delta: float) -> void:
	# Compute dynamic wind gust with noise
	var wind_gust = wind_force * (1.0 + sin(Time.get_ticks_msec() * 0.003) * 0.25)
	if wind_force.length_squared() > 0.01:
		var noise = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * wind_force.length() * 0.15
		wind_gust += noise
		
	# 1. Verlet integration
	for i in range(_points.size()):
		var pt = _points[i]
		if pt.is_pinned:
			# Pinned points follow the parent node's transform
			pt.pos = global_transform * pt.init_local_pos
			pt.prev_pos = pt.pos
			continue
			
		var force = pt.mass * gravity + wind_gust
		var temp = pt.pos
		var vel = (pt.pos - pt.prev_pos) * (1.0 - damping)
		pt.pos = pt.pos + vel + (force / pt.mass) * delta * delta
		pt.prev_pos = temp
		
	# 2. Enforce spring distance constraints
	for iter in range(solver_iterations):
		for spring in _springs:
			var p1 = _points[spring.p1]
			var p2 = _points[spring.p2]
			
			var delta_vec = p2.pos - p1.pos
			var dist = delta_vec.length()
			if dist < 0.0001: dist = 0.0001
			
			var diff = (spring.rest_len - dist) / dist * stiffness * 0.5
			var offset = delta_vec * diff
			
			if not p1.is_pinned:
				p1.pos -= offset
			if not p2.is_pinned:
				p2.pos += offset

## Attempt to bind splats to the simulation points (grid or SoftBody3D)
func _try_bind_splats() -> void:
	if not splattable or splattable.loaded_splats.is_empty():
		return
		
	var multimesh = _get_multimesh()
	if not multimesh or multimesh.instance_count == 0:
		return
		
	_bindings.clear()
	var splats = splattable.loaded_splats
	
	if _soft_body_ref:
		# Bind to SoftBody3D closest point
		var sb_mesh: Mesh = _soft_body_ref.mesh
		if not sb_mesh:
			return
		var faces = sb_mesh.get_faces()
		if faces.is_empty():
			return
			
		# Cache nearest vertices
		for i in range(splats.size()):
			var splat = splats[i]
			var splat_world_pos = splattable.global_transform * splat.position
			
			var min_dist = INF
			var best_idx = 0
			
			# Query closest vertex in SoftBody3D
			for f in range(faces.size()):
				var v = _soft_body_ref.global_transform * faces[f]
				var d = splat_world_pos.distance_to(v)
				if d < min_dist:
					min_dist = d
					best_idx = f
					
			_bindings.append({
				"splat_index": i,
				"point_index": best_idx,
				"local_offset": splat_world_pos - (_soft_body_ref.global_transform * faces[best_idx])
			})
	elif enable_internal_sim:
		# Bind to internal Verlet grid closest point
		for i in range(splats.size()):
			var splat = splats[i]
			var splat_world_pos = splattable.global_transform * splat.position
			
			var min_dist = INF
			var best_idx = 0
			
			for p in range(_points.size()):
				var d = splat_world_pos.distance_to(_points[p].pos)
				if d < min_dist:
					min_dist = d
					best_idx = p
					
			_bindings.append({
				"splat_index": i,
				"point_index": best_idx,
				"local_offset": splat_world_pos - _points[best_idx].pos
			})
			
	_is_bound = true
	print("FoveaSplatCloth3D: Bound ", _bindings.size(), " splats to simulation.")

func _update_internal_sim_binding() -> void:
	var multimesh = _get_multimesh()
	if not multimesh or _bindings.is_empty():
		return
		
	# Bulk read multimesh transforms
	var xf_array = multimesh.transform_array
	var splat_to_local_matrix = splattable.global_transform.affine_inverse()
	
	for bind in _bindings:
		var pt = _points[bind.point_index]
		var world_pos = pt.pos + bind.local_offset
		var local_pos = splat_to_local_matrix * world_pos
		
		# Update MultiMesh transform position (col3 is at offset 3)
		var offset = bind.splat_index * 4 + 3
		if offset < xf_array.size():
			xf_array[offset] = local_pos
			
	# Bulk write multimesh transforms (high performance)
	multimesh.transform_array = xf_array

func _update_soft_body_binding() -> void:
	if not _soft_body_ref: return
	var multimesh = _get_multimesh()
	if not multimesh or _bindings.is_empty():
		return
		
	var xf_array = multimesh.transform_array
	var splat_to_local_matrix = splattable.global_transform.affine_inverse()
	
	for bind in _bindings:
		# get_point_position returns point position in local space of SoftBody3D
		var pt_local = _soft_body_ref.get_point_position(bind.point_index)
		var pt_world = _soft_body_ref.global_transform * pt_local
		
		var world_pos = pt_world + bind.local_offset
		var local_pos = splat_to_local_matrix * world_pos
		
		var offset = bind.splat_index * 4 + 3
		if offset < xf_array.size():
			xf_array[offset] = local_pos
			
	multimesh.transform_array = xf_array

func _get_multimesh() -> MultiMesh:
	if not splattable:
		return null
	for child in splattable.get_children():
		if child is MultiMeshInstance3D:
			return child.multimesh
	return null
