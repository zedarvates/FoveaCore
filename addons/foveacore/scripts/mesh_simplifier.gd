class_name MeshSimplifier
extends Resource

## MeshSimplifier - Quadric Error Metrics (QEM) mesh simplification
## Implements Garland & Heckbert (1997) algorithm
## Reduces triangle count while preserving shape

class SimplificationResult:
	var simplified_mesh: ArrayMesh = null
	var original_triangles: int = 0
	var simplified_triangles: int = 0
	var reduction_ratio: float = 0.0
	var processing_time_ms: float = 0.0

class Quadric:
	var q: Array = []
	
	func _init():
		q.resize(10)
		q.fill(0.0)
	
	func add_plane(a: float, b: float, c: float, d: float):
		q[0] += a * a
		q[1] += a * b
		q[2] += a * c
		q[3] += a * d
		q[4] += b * b
		q[5] += b * c
		q[6] += b * d
		q[7] += c * c
		q[8] += c * d
		q[9] += d * d
	
	func add(other: Quadric):
		for i in range(10):
			q[i] += other.q[i]
	
	func clone() -> Quadric:
		var copy = Quadric.new()
		for i in range(10):
			copy.q[i] = q[i]
		return copy
	
	func compute_error_point(x: float, y: float, z: float) -> float:
		var w = 1.0
		return (q[0] * x * x + 2.0 * q[1] * x * y + 2.0 * q[2] * x * z + 2.0 * q[3] * x * w +
				q[4] * y * y + 2.0 * q[5] * y * z + 2.0 * q[6] * y * w +
				q[7] * z * z + 2.0 * q[8] * z * w +
				q[9] * w * w)
	
	func compute_error(v: Vector3) -> float:
		return compute_error_point(v.x, v.y, v.z)

class Edge:
	var v1: int
	var v2: int
	var error: float = 0.0
	var optimal_pos: Vector3 = Vector3.ZERO

class VertexData:
	var position: Vector3
	var normal: Vector3
	var quadric: Quadric
	var is_active: bool = true

static func simplify_mesh(
	mesh: ArrayMesh,
	target_ratio: float = 0.5,
	preserve_boundaries: bool = true,
	aggressiveness: float = 7.0
) -> SimplificationResult:
	var start_time = Time.get_ticks_usec()
	var result = SimplificationResult.new()
	result.original_triangles = _count_triangles(mesh)
	
	if result.original_triangles == 0:
		return result
	
	var new_mesh = ArrayMesh.new()
	
	for surface_idx in range(mesh.get_surface_count()):
		var mesh_data = mesh.surface_get_arrays(surface_idx)
		if mesh_data.size() < Mesh.ARRAY_VERTEX:
			continue
		
		var vertices = mesh_data[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals = mesh_data[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var indices = mesh_data[Mesh.ARRAY_INDEX] as PackedInt32Array
		
		if vertices.is_empty() or indices.is_empty():
			continue
		
		var simplified = _collapse_edges(vertices, normals, indices, target_ratio, preserve_boundaries, aggressiveness)
		
		var new_data = []
		new_data.resize(Mesh.ARRAY_MAX)
		new_data[Mesh.ARRAY_VERTEX] = simplified.vertices
		new_data[Mesh.ARRAY_NORMAL] = simplified.normals
		new_data[Mesh.ARRAY_INDEX] = simplified.indices
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_data)
	
	result.simplified_mesh = new_mesh
	result.simplified_triangles = _count_triangles(new_mesh)
	result.reduction_ratio = float(result.simplified_triangles) / max(result.original_triangles, 1)
	
	var end_time = Time.get_ticks_usec()
	result.processing_time_ms = (end_time - start_time) / 1000.0
	
	return result

static func _count_triangles(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var count = 0
	for surface_idx in range(mesh.get_surface_count()):
		var indices = mesh.surface_get_arrays(surface_idx)[Mesh.ARRAY_INDEX] as PackedInt32Array
		if indices.size() >= 3:
			count += indices.size() / 3
	return count

static func _collapse_edges(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	target_ratio: float,
	preserve_boundaries: bool,
	aggressiveness: float
) -> Dictionary:
	var vertex_count = vertices.size()
	var triangle_count = indices.size() / 3
	var target_triangles = max(1, int(triangle_count * target_ratio))
	
	var vertex_data: Array[VertexData] = []
	for i in range(vertex_count):
		var vd = VertexData.new()
		vd.position = vertices[i]
		vd.normal = normals[i] if i < normals.size() else Vector3.UP
		vd.quadric = Quadric.new()
		vertex_data.append(vd)
	
	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i + 1]
		var i2 = indices[i + 2]
		
		var v0 = vertices[i0]
		var v1 = vertices[i1]
		var v2 = vertices[i2]
		
		var edge1 = v1 - v0
		var edge2 = v2 - v0
		var face_normal = edge1.cross(edge2)
		var face_len = face_normal.length()
		
		if face_len < 0.0001:
			continue
		
		face_normal = face_normal.normalized()
		var area = face_len * 0.5
		var weight = area
		var d = -face_normal.dot(v0)
		
		var face_quadric = Quadric.new()
		face_quadric.add_plane(face_normal.x * weight, face_normal.y * weight, face_normal.z * weight, d * weight)
		
		vertex_data[i0].quadric.add(face_quadric)
		vertex_data[i1].quadric.add(face_quadric)
		vertex_data[i2].quadric.add(face_quadric)
	
	if preserve_boundaries:
		_enhance_boundary_quadrics(vertex_data, indices)
	
	var edges: Array[Edge] = []
	var edge_map = {}
	
	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i + 1]
		var i2 = indices[i + 2]
		
		_add_edge(edges, edge_map, i0, i1, vertex_data)
		_add_edge(edges, edge_map, i1, i2, vertex_data)
		_add_edge(edges, edge_map, i2, i0, vertex_data)
	
	edges.sort_custom(func(a, b): return a.error < b.error)
	
	var current_triangles = triangle_count
	var max_iterations = triangle_count * 2
	var iteration = 0
	
	while current_triangles > target_triangles and edges.size() > 0 and iteration < max_iterations:
		iteration += 1
		
		if edges.is_empty():
			break
		
		var best_edge = edges[0]
		edges.remove_at(0)
		
		var v1 = best_edge.v1
		var v2 = best_edge.v2
		
		if not vertex_data[v1].is_active or not vertex_data[v2].is_active:
			continue
		
		if not _is_collapse_valid(v1, v2, vertex_data, indices, preserve_boundaries, aggressiveness):
			continue
		
		var optimal_pos = best_edge.optimal_pos
		var combined_quadric = vertex_data[v1].quadric.clone()
		combined_quadric.add(vertex_data[v2].quadric)
		
		optimal_pos = _find_optimal_position(vertex_data[v1].position, vertex_data[v2].position, combined_quadric)
		
		vertex_data[v1].position = optimal_pos
		vertex_data[v1].quadric = combined_quadric
		vertex_data[v2].is_active = false
		
		var new_edges: Array[Edge] = []
		var new_edge_map = {}
		
		for e in edges:
			if e.v1 == v2:
				e.v1 = v1
			elif e.v2 == v2:
				e.v2 = v1
			
			if e.v1 == e.v2:
				continue
			
			if e.v1 == v1 or e.v2 == v1:
				var min_v = min(e.v1, e.v2)
				var max_v = max(e.v1, e.v2)
				var key = str(min_v) + "_" + str(max_v)
				
				e.error = _compute_edge_error(vertex_data[e.v1].position, vertex_data[e.v2].position, vertex_data[e.v1].quadric, vertex_data[e.v2].quadric)
				e.optimal_pos = _find_optimal_position(vertex_data[e.v1].position, vertex_data[e.v2].position, vertex_data[e.v1].quadric.clone().add(vertex_data[e.v2].quadric))
			
			new_edges.append(e)
		
		edges = new_edges
		edges.sort_custom(func(a, b): return a.error < b.error)
		current_triangles -= 1
	
	return _rebuild_mesh(vertex_data, indices)

static func _enhance_boundary_quadrics(vertex_data: Array[VertexData], indices: PackedInt32Array):
	var vertex_count = vertex_data.size()
	var boundary_edges = {}
	
	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i + 1]
		var i2 = indices[i + 2]
		
		_process_edge_boundary(i0, i1, boundary_edges)
		_process_edge_boundary(i1, i2, boundary_edges)
		_process_edge_boundary(i2, i0, boundary_edges)
	
	for key in boundary_edges.keys():
		if boundary_edges[key] == 1:
			var parts = key.split("_")
			var v_idx = int(parts[0])
			if v_idx < vertex_data.size():
				var vd = vertex_data[v_idx]
				var weight = 100.0
				vd.quadric.add_plane(0.0, 0.0, 1.0 * weight, -vd.position.z * weight)

static func _process_edge_boundary(v1: int, v2: int, boundary_edges: Dictionary):
	var key = str(min(v1, v2)) + "_" + str(max(v1, v2))
	if not boundary_edges.has(key):
		boundary_edges[key] = 0
	boundary_edges[key] += 1

static func _add_edge(edges: Array[Edge], edge_map: Dictionary, v1: int, v2: int, vertex_data: Array[VertexData]):
	var key = str(min(v1, v2)) + "_" + str(max(v1, v2))
	if edge_map.has(key):
		return
	
	var edge = Edge.new()
	edge.v1 = v1
	edge.v2 = v2
	
	var combined = vertex_data[v1].quadric.clone()
	combined.add(vertex_data[v2].quadric)
	edge.error = _compute_edge_error(vertex_data[v1].position, vertex_data[v2].position, vertex_data[v1].quadric, vertex_data[v2].quadric)
	edge.optimal_pos = _find_optimal_position(vertex_data[v1].position, vertex_data[v2].position, combined)
	
	edges.append(edge)
	edge_map[key] = edges.size() - 1

static func _compute_edge_error(p1: Vector3, p2: Vector3, q1: Quadric, q2: Quadric) -> float:
	var combined = q1.clone()
	combined.add(q2)
	return combined.compute_error(p2)

static func _find_optimal_position(p1: Vector3, p2: Vector3, quadric: Quadric) -> Vector3:
	var a = quadric.q[0]
	var b = quadric.q[1]
	var c = quadric.q[2]
	var d = quadric.q[3]
	var e = quadric.q[4]
	var f = quadric.q[5]
	var g = quadric.q[6]
	var h = quadric.q[7]
	var i = quadric.q[8]
	var j = quadric.q[9]
	
	var det = (a * (e * j - i * i) - b * (b * j - d * i) + c * (b * i - d * e))
	
	if abs(det) < 0.0000001:
		return (p1 + p2) * 0.5
	
	var inv_a = (e * j - i * i) / det
	var inv_b = (d * i - b * j) / det
	var inv_c = (b * i - d * e) / det
	var inv_d = (c * e - b * f) / det
	var inv_e = (a * j - c * c) / det
	var inv_f = (b * c - a * d) / det
	var inv_g = (f * i - c * e) / det
	var inv_h = (c * b - a * f) / det
	var inv_i = (a * e - b * b) / det
	var inv_j = (a * e - b * b) * 0.0
	
	var x = -inv_a * d - inv_b * g - inv_c * j
	var y = -inv_d * d - inv_e * g - inv_f * j
	var z = -inv_g * d - inv_h * g - inv_i * j
	
	var result = Vector3(x, y, z)
	
	if result.distance_to(p1) > result.distance_to(p2):
		return p1
	return result

static func _is_collapse_valid(v1: int, v2: int, vertex_data: Array[VertexData], indices: PackedInt32Array, preserve_boundaries: bool, aggressiveness: float) -> bool:
	var p1 = vertex_data[v1].position
	var p2 = vertex_data[v2].position
	var dist = p1.distance_to(p2)
	
	var bbox_min = Vector3(INF, INF, INF)
	var bbox_max = Vector3(-INF, -INF, -INF)
	for vd in vertex_data:
		if vd.is_active:
			bbox_min.x = min(bbox_min.x, vd.position.x)
			bbox_min.y = min(bbox_min.y, vd.position.y)
			bbox_min.z = min(bbox_min.z, vd.position.z)
			bbox_max.x = max(bbox_max.x, vd.position.x)
			bbox_max.y = max(bbox_max.y, vd.position.y)
			bbox_max.z = max(bbox_max.z, vd.position.z)
	
	var bbox_size = bbox_max - bbox_min
	var max_dist = bbox_size.length() * 0.1
	
	if dist > max_dist * (aggressiveness * 0.5):
		return false
	
	if preserve_boundaries:
		var is_boundary1 = _is_boundary_vertex(v1, indices)
		var is_boundary2 = _is_boundary_vertex(v2, indices)
		if is_boundary1 and is_boundary2:
			var edge_exists = false
			for i in range(0, indices.size(), 3):
				var i0 = indices[i]
				var i1 = indices[i + 1]
				var i2 = indices[i + 2]
				var count = 0
				if i0 == v1 or i0 == v2: count += 1
				if i1 == v1 or i1 == v2: count += 1
				if i2 == v1 or i2 == v2: count += 1
				if count == 2:
					edge_exists = true
					break
			if not edge_exists:
				return false
	
	return true

static func _is_boundary_vertex(v: int, indices: PackedInt32Array) -> bool:
	var edge_count = {}
	
	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i + 1]
		var i2 = indices[i + 2]
		
		if i0 == v or i1 == v or i2 == v:
			var edges = []
			if i0 == v:
				edges.append([i1, i2])
			if i1 == v:
				edges.append([i0, i2])
			if i2 == v:
				edges.append([i0, i1])
			
			for e in edges:
				var key = str(min(e[0], e[1])) + "_" + str(max(e[0], e[1]))
				if edge_count.has(key):
					edge_count[key] += 1
				else:
					edge_count[key] = 1
	
	for key in edge_count.keys():
		if edge_count[key] == 1:
			return true
	
	return false

static func _rebuild_mesh(vertex_data: Array[VertexData], original_indices: PackedInt32Array) -> Dictionary:
	var new_vertex_map = {}
	var new_vertices = PackedVector3Array()
	var new_normals = PackedVector3Array()
	var vertex_index_map = {}
	
	for i in range(vertex_data.size()):
		if vertex_data[i].is_active:
			new_vertex_map[new_vertices.size()] = i
			vertex_index_map[i] = new_vertices.size()
			new_vertices.append(vertex_data[i].position)
			new_normals.append(vertex_data[i].normal)
	
	var new_indices = PackedInt32Array()
	
	for i in range(0, original_indices.size(), 3):
		var i0 = original_indices[i]
		var i1 = original_indices[i + 1]
		var i2 = original_indices[i + 2]
		
		if not vertex_data[i0].is_active or not vertex_data[i1].is_active or not vertex_data[i2].is_active:
			continue
		
		var new_i0 = vertex_index_map.get(i0, -1)
		var new_i1 = vertex_index_map.get(i1, -1)
		var new_i2 = vertex_index_map.get(i2, -1)
		
		if new_i0 == -1 or new_i1 == -1 or new_i2 == -1:
			continue
		
		var v0 = new_vertices[new_i0]
		var v1 = new_vertices[new_i1]
		var v2 = new_vertices[new_i2]
		
		var edge1 = v1 - v0
		var edge2 = v2 - v0
		var normal = edge1.cross(edge2)
		
		if normal.length() < 0.0001:
			continue
		
		new_indices.append(new_i0)
		new_indices.append(new_i1)
		new_indices.append(new_i2)
	
	if new_normals.size() != new_vertices.size():
		new_normals = _recompute_normals(new_vertices, new_indices)
	
	return {
		"vertices": new_vertices,
		"normals": new_normals,
		"indices": new_indices
	}

static func _recompute_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals = PackedVector3Array()
	normals.resize(vertices.size())
	
	for i in range(vertices.size()):
		normals[i] = Vector3.ZERO
	
	for i in range(0, indices.size(), 3):
		var i0 = indices[i]
		var i1 = indices[i + 1]
		var i2 = indices[i + 2]
		
		var v0 = vertices[i0]
		var v1 = vertices[i1]
		var v2 = vertices[i2]
		
		var edge1 = v1 - v0
		var edge2 = v2 - v0
		var normal = edge1.cross(edge2)
		
		normals[i0] += normal
		normals[i1] += normal
		normals[i2] += normal
	
	for i in range(normals.size()):
		if normals[i].length() > 0.0001:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP
	
	return normals
