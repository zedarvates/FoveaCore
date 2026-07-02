extends Node3D
class_name FoveaSplatCloth3D

signal spring_broken(spring_index: int, p1: int, p2: int, cause: String)

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
var _springs: Array[Dictionary] = [] # keys: "p1", "p2", "rest_len", "active"
var _bindings: Array[Dictionary] = [] # keys: "splat_index", "point_index", "local_offset", "local_basis"
var _is_bound: bool = false

# Cache reference to SoftBody3D if coupled
var _soft_body_ref: SoftBody3D = null

@export_group("Squish & Bounce Parameters")
@export var squish_stiffness: float = 15.0
@export var squish_damping: float = 3.0
@export var poisson_ratio: float = 0.4
@export var squish_intensity: float = 1.0

@export_group("Tearing & Cutting")
@export var enable_tearing: bool = false
@export var tear_threshold: float = 1.3
@export var cut_radius: float = 0.05

# Neighbor mapping for SoftBody3D frame computation
var _vertex_neighbors: Array[Array] = []
var _sb_deformation_states: Array[Dictionary] = []


func _ready() -> void:
	if not splattable:
		# Try to auto-detect parent
		var parent = get_parent()
		if parent is FoveaSplattable:
			splattable = parent

	if splattable and splattable.is_static:
		print("FoveaSplatCloth3D: Asset is static. Skipping physics simulation initialization.")
		return

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
	
	# Task 268: Connection du Verlet Solver ou des forces physiques aux entités dynamiques uniquement.
	# Si l'objet est configuré comme statique/stable (is_static == true), on évite complètement de faire tourner le Verlet Solver
	# ou d'appliquer les calculs de déformations physiques sur l'objet.
	if splattable and splattable.is_static:
		return

	if _soft_body_ref:
		# Mettre à jour l'oscillateur d'écrasement/rebond pour SoftBody3D
		for i: int in range(_sb_deformation_states.size()):
			var state: Dictionary = _sb_deformation_states[i]
			var x: float = state.get("deformation_x", 0.0) as float
			var v: float = state.get("deformation_v", 0.0) as float
			var ext_force: float = state.get("external_force", 0.0) as float
			
			state["external_force"] = move_toward(ext_force, 0.0, delta * 4.0)
			
			var a: float = (-squish_stiffness * x - squish_damping * v + ext_force) / 0.1
			v += a * delta
			x += v * delta
			
			state["deformation_x"] = x
			state["deformation_v"] = v
			
		_update_soft_body_binding()
	elif enable_internal_sim:
		# Mettre à jour l'oscillateur d'écrasement/rebond pour la grille interne
		for pt: Dictionary in _points:
			var x: float = pt.get("deformation_x", 0.0) as float
			var v: float = pt.get("deformation_v", 0.0) as float
			var ext_force: float = pt.get("external_force", 0.0) as float
			
			pt["external_force"] = move_toward(ext_force, 0.0, delta * 4.0)
			
			var a: float = (-squish_stiffness * x - squish_damping * v + ext_force) / (pt.mass as float)
			v += a * delta
			x += v * delta
			
			pt["deformation_x"] = x
			pt["deformation_v"] = v
			
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
				"init_local_pos": local_pos,
				"deformation_x": 0.0,
				"deformation_v": 0.0,
				"external_force": 0.0
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
		"rest_len": dist,
		"active": true
	})

## Perform one Verlet integration and constraint solving step
func _step_internal_sim(delta: float) -> void:
	# Compute dynamic wind gust with noise
	var wind_gust = wind_force * (1.0 + sin(Time.get_ticks_msec() * 0.003) * 0.25)
	if wind_force.length_squared() > 0.01:
		var t := float(Time.get_ticks_msec()) * 0.001
		var noise := Vector3(
			sin(t * 17.3 + 1.1) * cos(t * 11.5 - 2.3),
			sin(t * 13.1 - 0.7) * cos(t * 19.3 + 1.5),
			sin(t * 23.7 + 0.3) * cos(t * 7.1 - 1.9)
		) * wind_force.length() * 0.15
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
		for s_idx in range(_springs.size()):
			var spring = _springs[s_idx]
			if not spring.get("active", true):
				continue
				
			var p1 = _points[spring.p1]
			var p2 = _points[spring.p2]
			
			var delta_vec = p2.pos - p1.pos
			var dist = delta_vec.length()
			if dist < 0.0001: dist = 0.0001
			
			if enable_tearing and spring.rest_len > 0.0:
				var ratio: float = dist / (spring.rest_len as float)
				if ratio > tear_threshold:
					spring["active"] = false
					spring_broken.emit(s_idx, spring.p1, spring.p2, "tension")
					continue
			
			var diff = (spring.rest_len - dist) / dist * stiffness * 0.5
			var offset = delta_vec * diff
			
			if not p1.is_pinned:
				p1.pos -= offset
			if not p2.is_pinned:
				p2.pos += offset

func _get_grid_point_frame(p: int) -> Basis:
	var x: int = p % grid_size.x
	var y: int = p / grid_size.x
	
	var t_vec: Vector3 = Vector3.RIGHT
	if grid_size.x > 1:
		var left: int = p - 1 if x > 0 else p
		var right: int = p + 1 if x < grid_size.x - 1 else p
		t_vec = (_points[right].pos - _points[left].pos)
		if t_vec.is_zero_approx():
			t_vec = Vector3.RIGHT
		else:
			t_vec = t_vec.normalized()
			
	var b_vec: Vector3 = Vector3.UP
	if grid_size.y > 1:
		var up: int = p - grid_size.x if y > 0 else p
		var down: int = p + grid_size.x if y < grid_size.y - 1 else p
		b_vec = (_points[down].pos - _points[up].pos)
		if b_vec.is_zero_approx():
			b_vec = Vector3.UP
		else:
			b_vec = b_vec.normalized()
			
	var n_vec: Vector3 = t_vec.cross(b_vec)
	if n_vec.is_zero_approx():
		n_vec = Vector3.FORWARD
	else:
		n_vec = n_vec.normalized()
		
	t_vec = b_vec.cross(n_vec).normalized()
	
	return Basis(t_vec, b_vec, n_vec)


func _get_sb_point_frame(p: int) -> Basis:
	if p >= _vertex_neighbors.size() or _vertex_neighbors[p].is_empty():
		return Basis()
		
	var neighbors: Array = _vertex_neighbors[p]
	var p_pos: Vector3 = _soft_body_ref.global_transform * _soft_body_ref.get_point_position(p)
	
	var t_vec: Vector3 = Vector3.RIGHT
	if neighbors.size() > 0:
		var n1: int = neighbors[0]
		var n1_pos: Vector3 = _soft_body_ref.global_transform * _soft_body_ref.get_point_position(n1)
		t_vec = (n1_pos - p_pos)
		if t_vec.is_zero_approx():
			t_vec = Vector3.RIGHT
		else:
			t_vec = t_vec.normalized()
			
	var b_vec: Vector3 = Vector3.UP
	if neighbors.size() > 1:
		var n2: int = neighbors[1]
		var n2_pos: Vector3 = _soft_body_ref.global_transform * _soft_body_ref.get_point_position(n2)
		b_vec = (n2_pos - p_pos)
		if b_vec.is_zero_approx():
			b_vec = Vector3.UP
		else:
			b_vec = b_vec.normalized()
			
	var n_vec: Vector3 = t_vec.cross(b_vec)
	if n_vec.is_zero_approx():
		n_vec = Vector3.FORWARD
	else:
		n_vec = n_vec.normalized()
		
	t_vec = b_vec.cross(n_vec).normalized()
	
	return Basis(t_vec, b_vec, n_vec)


## Applique un impact d'écrasement localisé dans une zone sphérique
func apply_crush(global_pos: Vector3, radius: float, force: float) -> void:
	if _soft_body_ref:
		for i: int in range(_sb_deformation_states.size()):
			var pt_world: Vector3 = _soft_body_ref.global_transform * _soft_body_ref.get_point_position(i)
			var dist: float = global_pos.distance_to(pt_world)
			if dist < radius:
				var weight: float = 1.0 - (dist / radius)
				_sb_deformation_states[i]["external_force"] += force * weight
	elif enable_internal_sim:
		for pt: Dictionary in _points:
			var dist: float = global_pos.distance_to(pt.pos)
			if dist < radius:
				var weight: float = 1.0 - (dist / radius)
				pt["external_force"] = (pt.get("external_force", 0.0) as float) + force * weight


## Coupe manuellement le tissu dans une zone sphérique
func cut_cloth_sphere(center: Vector3, radius: float = -1.0) -> void:
	if not enable_internal_sim:
		return
	var r_val := radius if radius >= 0.0 else cut_radius
	for s_idx in range(_springs.size()):
		var spring = _springs[s_idx]
		if not spring.get("active", true):
			continue
		var p1: Vector3 = _points[spring.p1].pos
		var p2: Vector3 = _points[spring.p2].pos
		
		# Calculer le point le plus proche sur le segment p1-p2 par rapport au centre de la sphère
		var u := p2 - p1
		var t := clampf((center - p1).dot(u) / (u.length_squared() if u.length_squared() > 0.0001 else 1.0), 0.0, 1.0)
		var closest_point := p1 + t * u
		if center.distance_to(closest_point) < r_val:
			spring["active"] = false
			spring_broken.emit(s_idx, spring.p1, spring.p2, "cut_sphere")


## Coupe manuellement le tissu le long d'un segment de ligne en 3D
func cut_cloth_line(start_pos: Vector3, end_pos: Vector3, radius: float = -1.0) -> void:
	if not enable_internal_sim:
		return
	var r_val := radius if radius >= 0.0 else cut_radius
	for s_idx in range(_springs.size()):
		var spring = _springs[s_idx]
		if not spring.get("active", true):
			continue
		var p1: Vector3 = _points[spring.p1].pos
		var p2: Vector3 = _points[spring.p2].pos
		var dist := _get_segments_minimum_distance(start_pos, end_pos, p1, p2)
		if dist < r_val:
			spring["active"] = false
			spring_broken.emit(s_idx, spring.p1, spring.p2, "cut_line")


## Helper pour calculer la distance minimale entre deux segments de droite en 3D (p1-p2 et q1-q2)
func _get_segments_minimum_distance(p1: Vector3, p2: Vector3, q1: Vector3, q2: Vector3) -> float:
	var u := p2 - p1
	var v := q2 - q1
	var w := p1 - q1
	
	var a := u.dot(u)
	var b := u.dot(v)
	var c := v.dot(v)
	var d := u.dot(w)
	var e := v.dot(w)
	
	var D := a * c - b * b
	var sc: float = 0.0
	var tc: float = 0.0
	
	if D < 0.0001:
		sc = 0.0
		tc = e / c if c > 0.0001 else 0.0
	else:
		sc = (b * e - c * d) / D
		tc = (a * e - b * d) / D
		
	# Clamper dans l'intervalle du segment [0, 1]
	if sc < 0.0:
		sc = 0.0
		tc = e / c if c > 0.0001 else 0.0
	elif sc > 1.0:
		sc = 1.0
		tc = (e + b) / c if c > 0.0001 else 0.0
		
	if tc < 0.0:
		tc = 0.0
		sc = clampf(-d / a if a > 0.0001 else 0.0, 0.0, 1.0)
	elif tc > 1.0:
		tc = 1.0
		sc = clampf((b - d) / a if a > 0.0001 else 0.0, 0.0, 1.0)
		
	var closest_p := p1 + sc * u
	var closest_q := q1 + tc * v
	return closest_p.distance_to(closest_q)


## Attempt to bind splats to the simulation points (grid or SoftBody3D)
func _try_bind_splats() -> void:
	if not splattable or splattable.loaded_splats.is_empty():
		return
		
	var multimesh: MultiMesh = _get_multimesh()
	if not multimesh or multimesh.instance_count == 0:
		return
		
	_bindings.clear()
	var splats: Array = splattable.loaded_splats
	
	var stride: int = FoveaMultiMeshBulk.stride_of(multimesh)
	var buf: PackedFloat32Array = multimesh.buffer
	if buf.is_empty():
		var xf_array: PackedVector3Array = multimesh.transform_array
		buf.resize(multimesh.instance_count * stride)
		if not xf_array.is_empty():
			for i: int in range(multimesh.instance_count):
				var s_idx: int = i * 4
				var splat_basis := Basis(xf_array[s_idx], xf_array[s_idx + 1], xf_array[s_idx + 2])
				var splat_pos := xf_array[s_idx + 3]
				var base: int = i * stride
				FoveaMultiMeshBulk.write_transform(buf, base, Transform3D(splat_basis, splat_pos))
		multimesh.buffer = buf
	
	if _soft_body_ref:
		var sb_mesh: Mesh = _soft_body_ref.mesh
		if not sb_mesh or sb_mesh.get_surface_count() == 0:
			return
		var arrays: Array = sb_mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if vertices.is_empty():
			return
			
		# Construire la liste des voisins de chaque sommet
		_vertex_neighbors.clear()
		_vertex_neighbors.resize(vertices.size())
		for idx: int in range(vertices.size()):
			_vertex_neighbors[idx] = []
			
		if not indices.is_empty():
			var num_indices: int = indices.size()
			for t: int in range(0, num_indices, 3):
				var i0: int = indices[t]
				var i1: int = indices[t + 1]
				var i2: int = indices[t + 2]
				
				if not i1 in _vertex_neighbors[i0]: _vertex_neighbors[i0].append(i1)
				if not i2 in _vertex_neighbors[i0]: _vertex_neighbors[i0].append(i2)
				
				if not i0 in _vertex_neighbors[i1]: _vertex_neighbors[i1].append(i0)
				if not i2 in _vertex_neighbors[i1]: _vertex_neighbors[i1].append(i2)
				
				if not i0 in _vertex_neighbors[i2]: _vertex_neighbors[i2].append(i0)
				if not i1 in _vertex_neighbors[i2]: _vertex_neighbors[i2].append(i1)
				
		_sb_deformation_states.clear()
		_sb_deformation_states.resize(vertices.size())
		for idx: int in range(vertices.size()):
			_sb_deformation_states[idx] = {
				"deformation_x": 0.0,
				"deformation_v": 0.0,
				"external_force": 0.0
			}
			
		# Liaison aux sommets de SoftBody3D
		for i: int in range(splats.size()):
			var splat: GaussianSplat = splats[i]
			var splat_world_pos: Vector3 = splattable.global_transform * splat.position
			
			var min_dist: float = INF
			var best_idx: int = 0
			
			# Query closest vertex in SoftBody3D
			for v_idx: int in range(vertices.size()):
				var v: Vector3 = _soft_body_ref.global_transform * vertices[v_idx]
				var d: float = splat_world_pos.distance_to(v)
				if d < min_dist:
					min_dist = d
					best_idx = v_idx
					
			var base: int = i * stride
			var x_axis := Vector3(buf[base + 0], buf[base + 4], buf[base + 8])
			var y_axis := Vector3(buf[base + 1], buf[base + 5], buf[base + 9])
			var z_axis := Vector3(buf[base + 2], buf[base + 6], buf[base + 10])
			var splat_basis := Basis(x_axis, y_axis, z_axis)
			
			var global_splat_basis: Basis = splattable.global_transform.basis * splat_basis
			var rest_frame: Basis = _get_sb_point_frame(best_idx)
			
			_bindings.append({
				"splat_index": i,
				"point_index": best_idx,
				"local_offset": splat_world_pos - (_soft_body_ref.global_transform * vertices[best_idx]),
				"local_basis": rest_frame.inverse() * global_splat_basis
			})
			
	elif enable_internal_sim:
		# Liaison à la grille Verlet interne
		for i: int in range(splats.size()):
			var splat: GaussianSplat = splats[i]
			var splat_world_pos: Vector3 = splattable.global_transform * splat.position
			
			var min_dist: float = INF
			var best_idx: int = 0
			
			for p: int in range(_points.size()):
				var d: float = splat_world_pos.distance_to(_points[p].pos)
				if d < min_dist:
					min_dist = d
					best_idx = p
					
			var base: int = i * stride
			var x_axis := Vector3(buf[base + 0], buf[base + 4], buf[base + 8])
			var y_axis := Vector3(buf[base + 1], buf[base + 5], buf[base + 9])
			var z_axis := Vector3(buf[base + 2], buf[base + 6], buf[base + 10])
			var splat_basis := Basis(x_axis, y_axis, z_axis)
			
			var global_splat_basis: Basis = splattable.global_transform.basis * splat_basis
			var rest_frame: Basis = _get_grid_point_frame(best_idx)
			
			_bindings.append({
				"splat_index": i,
				"point_index": best_idx,
				"local_offset": splat_world_pos - _points[best_idx].pos,
				"local_basis": rest_frame.inverse() * global_splat_basis
			})
			
	_is_bound = true
	print("FoveaSplatCloth3D: Bound ", _bindings.size(), " splats to simulation.")


func _update_internal_sim_binding() -> void:
	var multimesh: MultiMesh = _get_multimesh()
	if not multimesh or _bindings.is_empty():
		return
		
	var stride: int = FoveaMultiMeshBulk.stride_of(multimesh)
	var buf: PackedFloat32Array = multimesh.buffer
	var splat_to_local_matrix: Transform3D = splattable.global_transform.affine_inverse()
	
	for bind: Dictionary in _bindings:
		var pt: Dictionary = _points[bind.point_index]
		var world_pos: Vector3 = pt.pos + (bind.local_offset as Vector3)
		var local_pos: Vector3 = splat_to_local_matrix * world_pos
		
		# Calculer le squish amorti
		var x: float = pt.get("deformation_x", 0.0) as float
		var scale_z: float = clampf(1.0 - squish_intensity * x, 0.05, 2.0)
		var scale_xy: float = clampf(1.0 + poisson_ratio * squish_intensity * x, 0.5, 3.0)
		
		var current_frame: Basis = _get_grid_point_frame(bind.point_index)
		var squish_basis: Basis = Basis.from_scale(Vector3(scale_xy, scale_xy, scale_z))
		var new_basis: Basis = current_frame * squish_basis * (bind.get("local_basis", Basis()) as Basis)
		
		var local_basis: Basis = splat_to_local_matrix.basis * new_basis
		var local_xf := Transform3D(local_basis, local_pos)
		
		var base: int = bind.splat_index * stride
		if base + 11 < buf.size():
			FoveaMultiMeshBulk.write_transform(buf, base, local_xf)
			
	multimesh.buffer = buf


func _update_soft_body_binding() -> void:
	if not _soft_body_ref: return
	var multimesh: MultiMesh = _get_multimesh()
	if not multimesh or _bindings.is_empty():
		return
		
	var stride: int = FoveaMultiMeshBulk.stride_of(multimesh)
	var buf: PackedFloat32Array = multimesh.buffer
	var splat_to_local_matrix: Transform3D = splattable.global_transform.affine_inverse()
	
	for bind: Dictionary in _bindings:
		var pt_local: Vector3 = _soft_body_ref.get_point_position(bind.point_index)
		var pt_world: Vector3 = _soft_body_ref.global_transform * pt_local
		
		var world_pos: Vector3 = pt_world + (bind.local_offset as Vector3)
		var local_pos: Vector3 = splat_to_local_matrix * world_pos
		
		# Calculer le squish amorti
		var state: Dictionary = _sb_deformation_states[bind.point_index]
		var x: float = state["deformation_x"] as float
		var scale_z: float = clampf(1.0 - squish_intensity * x, 0.05, 2.0)
		var scale_xy: float = clampf(1.0 + poisson_ratio * squish_intensity * x, 0.5, 3.0)
		
		var current_frame: Basis = _get_sb_point_frame(bind.point_index)
		var squish_basis: Basis = Basis.from_scale(Vector3(scale_xy, scale_xy, scale_z))
		var new_basis: Basis = current_frame * squish_basis * (bind.get("local_basis", Basis()) as Basis)
		
		var local_basis: Basis = splat_to_local_matrix.basis * new_basis
		var local_xf := Transform3D(local_basis, local_pos)
		
		var base: int = bind.splat_index * stride
		if base + 11 < buf.size():
			FoveaMultiMeshBulk.write_transform(buf, base, local_xf)
			
	multimesh.buffer = buf


func _get_multimesh() -> MultiMesh:
	if not splattable:
		return null
	for child in splattable.get_children():
		if child is MultiMeshInstance3D:
			return child.multimesh
	return null
