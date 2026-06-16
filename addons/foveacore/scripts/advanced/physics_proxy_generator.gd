extends Node3D
class_name PhysicsProxyGenerator

## PhysicsProxyGenerator — Binds high-fidelity Gaussian Splats to Physical Colliders
## Uses the Low-Poly mesh from StudioTo3D or MeshFlow as a proxy for the high-end splats

const FoveaPointCloudExporter = preload("res://addons/foveacore/scripts/advanced/fovea_point_cloud_exporter.gd")
const MeshSimplifier = preload("res://addons/foveacore/scripts/mesh_simplifier.gd")

@export var rigid_body_mode := RigidBody3D.FREEZE_MODE_STATIC
@export var mesh_simplifier: MeshSimplifier = null
@export var collision_layers := 1
@export var mass := 1.0

## Link a Splattable object with a Physics Body (RigidBody3D) using a Concave Collider
func create_hybrid_body(splattable: FoveaSplattable, mesh: ArrayMesh) -> RigidBody3D:
	var body = RigidBody3D.new()
	body.name = "HybridPhysics_" + splattable.name
	body.freeze_mode = rigid_body_mode
	body.mass = mass
	body.collision_layer = collision_layers
	
	# Create the collision shape from the low-poly mesh
	var shape = CollisionShape3D.new()
	var collider = ConcavePolygonShape3D.new()
	collider.set_faces(mesh.get_faces())
	shape.shape = collider
	
	body.add_child(shape)
	
	# Parent the splattable to the body to follow physics transform
	splattable.get_parent().remove_child(splattable)
	body.add_child(splattable)
	splattable.transform = Transform3D.IDENTITY
	
	print("PhysicsProxyGenerator: Linked ", splattable.name, " to RigidBody with Low-Poly Concave Collider.")
	return body

## Generate a ConvexPolygonShape3D from an ArrayMesh (suitable for active rigid bodies)
func generate_convex_collider_from_mesh(mesh: ArrayMesh) -> ConvexPolygonShape3D:
	if mesh == null:
		return null
	var collider := ConvexPolygonShape3D.new()
	
	# Extract vertices from the mesh to build the convex hull
	var vertices := PackedVector3Array()
	for surface_idx in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_idx)
		if arrays.size() > Mesh.ARRAY_VERTEX:
			var surface_verts = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			vertices.append_array(surface_verts)
			
	if vertices.is_empty():
		push_error("PhysicsProxyGenerator: No vertices found in mesh to generate convex shape.")
		return null
		
	collider.points = vertices
	return collider

## Link a Splattable object with a Physics Body using a Convex Collider
func create_hybrid_body_with_convex(splattable: FoveaSplattable, mesh: ArrayMesh) -> RigidBody3D:
	var body = RigidBody3D.new()
	body.name = "HybridPhysicsConvex_" + splattable.name
	body.freeze_mode = rigid_body_mode
	body.mass = mass
	body.collision_layer = collision_layers
	
	var shape = CollisionShape3D.new()
	var collider = generate_convex_collider_from_mesh(mesh)
	if collider == null:
		return null
	shape.shape = collider
	body.add_child(shape)
	
	# Parent the splattable to the body to follow physics transform
	splattable.get_parent().remove_child(splattable)
	body.add_child(splattable)
	splattable.transform = Transform3D.IDENTITY
	
	print("PhysicsProxyGenerator: Linked ", splattable.name, " to RigidBody with Convex Collider.")
	return body

## Generates a physics proxy body by exporting the point cloud and querying MeshFlow.
## If the MeshFlow server is not reachable or cached output isn't found, it falls back
## to local QEM simplification of the splat's original mesh.
func generate_physics_via_meshflow(splattable: FoveaSplattable, server_url: String = "http://localhost:8000/process") -> RigidBody3D:
	if splattable == null:
		push_error("PhysicsProxyGenerator: Splattable is null.")
		return null
		
	print("PhysicsProxyGenerator: Starting MeshFlow-driven physics generation for ", splattable.name)
	
	# 1. Export point cloud using FoveaPointCloudExporter
	var temp_ply_path = "user://temp_meshflow_input_" + splattable.name + ".ply"
	var config = FoveaPointCloudExporter.ExportConfig.new()
	config.min_opacity = 0.15
	config.max_scale = 0.05
	config.target_points_count = 16384 # Standard size for MeshFlow shape encoder
	config.filter_isolated_floaters = true
	
	var export_ok = FoveaPointCloudExporter.export_splattable_to_ply(splattable, temp_ply_path, config)
	if not export_ok:
		push_error("PhysicsProxyGenerator: Failed to export splat point cloud.")
		return null
		
	# 2. Send request to the MeshFlow Server
	print("PhysicsProxyGenerator: Querying MeshFlow server at ", server_url)
	
	var expected_meshflow_mesh_path = "res://reconstructions/physics_" + splattable.name + ".glb"
	var server_success = _query_meshflow_server(temp_ply_path, expected_meshflow_mesh_path, server_url)
	
	var meshflow_mesh: ArrayMesh = null
	if server_success:
		meshflow_mesh = _load_mesh_from_glb_file(expected_meshflow_mesh_path)
	else:
		if FileAccess.file_exists(expected_meshflow_mesh_path):
			print("PhysicsProxyGenerator: Server connection failed, but cached GLB exists. Loading...")
			meshflow_mesh = _load_mesh_from_glb_file(expected_meshflow_mesh_path)
			
	if meshflow_mesh != null:
		print("PhysicsProxyGenerator: Found MeshFlow mesh. Creating body...")
		return create_hybrid_body_with_convex(splattable, meshflow_mesh)
	else:
		push_warning("PhysicsProxyGenerator: MeshFlow server/cache not found. Falling back to local QEM simplification.")
		
		# Fallback 1: QEM simplification on the original mesh if available
		if splattable.original_mesh != null and splattable.original_mesh is ArrayMesh:
			var orig_mesh = splattable.original_mesh as ArrayMesh
			var target_ratio = 0.1 # Simplify aggressively for physics
			var simplified_res = MeshSimplifier.simplify_mesh(orig_mesh, target_ratio)
			if simplified_res != null and simplified_res.simplified_mesh != null:
				print("PhysicsProxyGenerator: Successfully simplified original mesh using QEM (triangles reduced: ", 
					simplified_res.original_triangles, " -> ", simplified_res.simplified_triangles, ").")
				return create_hybrid_body_with_convex(splattable, simplified_res.simplified_mesh)
				
		# Fallback 2: Simple AABB collider
		print("PhysicsProxyGenerator: No mesh available. Falling back to AABB box shape.")
		var body = RigidBody3D.new()
		body.name = "HybridPhysicsBox_" + splattable.name
		body.freeze_mode = rigid_body_mode
		body.mass = mass
		body.collision_layer = collision_layers
		
		var shape = CollisionShape3D.new()
		var aabb_shape = BoxShape3D.new()
		var aabb = splattable.get_aabb()
		aabb_shape.size = aabb.size
		shape.shape = aabb_shape
		shape.position = aabb.position + aabb.size * 0.5
		body.add_child(shape)
		
		splattable.get_parent().remove_child(splattable)
		body.add_child(splattable)
		splattable.transform = Transform3D.IDENTITY
		return body

# Helper to parse a URL like "http://localhost:8000/process"
# Returns a dictionary with "host", "port", "path"
func _parse_url(url: String) -> Dictionary:
	var result = {
		"host": "127.0.0.1",
		"port": 8000,
		"path": "/process"
	}
	
	if not url.begins_with("http://") and not url.begins_with("https://"):
		push_error("URL must begin with http:// or https://")
		return result
		
	var protocol_split = url.split("://")
	var remainder = protocol_split[1]
	
	var path_split = remainder.split("/", true, 1)
	var host_port = path_split[0]
	if path_split.size() > 1:
		result["path"] = "/" + path_split[1]
	else:
		result["path"] = "/"
		
	var port_split = host_port.split(":")
	result["host"] = port_split[0]
	if port_split.size() > 1:
		result["port"] = port_split[1].to_int()
	else:
		result["port"] = 80 # Default HTTP port
		
	return result

func _query_meshflow_server(ply_path: String, out_glb_path: String, server_url: String) -> bool:
	var url_info = _parse_url(server_url)
	var host = url_info["host"]
	var port = url_info["port"]
	var path = url_info["path"]
	
	var client = HTTPClient.new()
	var err = client.connect_to_host(host, port)
	if err != OK:
		push_warning("PhysicsProxyGenerator: Failed to initiate connection to server: " + error_string(err))
		return false
		
	# Wait for connection (with a timeout of 1.0 second to fail fast if offline)
	var start_time = Time.get_ticks_msec()
	var timeout_ms = 1000
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()
		OS.delay_msec(5)
		if Time.get_ticks_msec() - start_time > timeout_ms:
			push_warning("PhysicsProxyGenerator: Connection timeout.")
			client.close()
			return false
			
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		client.close()
		return false
		
	# Load the PLY file
	var file = FileAccess.open(ply_path, FileAccess.READ)
	if not file:
		push_error("PhysicsProxyGenerator: Could not read PLY file at " + ply_path)
		client.close()
		return false
	var ply_data = file.get_buffer(file.get_length())
	file.close()
	
	# Prepare multipart/form-data request
	var boundary = "FoveaBoundary" + str(Time.get_ticks_msec())
	var header_str = "--" + boundary + "\r\n"
	header_str += "Content-Disposition: form-data; name=\"file\"; filename=\"" + ply_path.get_file() + "\"\r\n"
	header_str += "Content-Type: application/octet-stream\r\n\r\n"
	var footer_str = "\r\n--" + boundary + "--\r\n"
	
	var body = PackedByteArray()
	body.append_array(header_str.to_utf8_buffer())
	body.append_array(ply_data)
	body.append_array(footer_str.to_utf8_buffer())
	
	var headers = [
		"Content-Type: multipart/form-data; boundary=" + boundary,
		"Content-Length: " + str(body.size())
	]
	
	err = client.request_raw(HTTPClient.METHOD_POST, path, headers, body)
	if err != OK:
		push_warning("PhysicsProxyGenerator: Failed to send request: " + error_string(err))
		client.close()
		return false
		
	# Wait for response (with a timeout of 10.0 seconds)
	start_time = Time.get_ticks_msec()
	timeout_ms = 10000
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		OS.delay_msec(10)
		if Time.get_ticks_msec() - start_time > timeout_ms:
			push_warning("PhysicsProxyGenerator: Request timeout.")
			client.close()
			return false
			
	if not client.has_response():
		push_warning("PhysicsProxyGenerator: Server did not return a response.")
		client.close()
		return false
		
	var response_code = client.get_response_code()
	if response_code != 200:
		push_warning("PhysicsProxyGenerator: Server returned error code " + str(response_code))
		client.close()
		return false
		
	# Read response body
	var response_data = PackedByteArray()
	start_time = Time.get_ticks_msec()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk = client.read_response_body_chunk()
		if chunk.size() > 0:
			response_data.append_array(chunk)
		else:
			OS.delay_msec(5)
		if Time.get_ticks_msec() - start_time > timeout_ms:
			push_warning("PhysicsProxyGenerator: Body read timeout.")
			client.close()
			return false
			
	client.close()
	
	if response_data.is_empty():
		push_warning("PhysicsProxyGenerator: Received empty response.")
		return false
		
	# Make sure directory exists
	var dir_path = out_glb_path.get_base_dir()
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(dir_path):
		var err_dir = dir.make_dir_recursive(dir_path)
		if err_dir != OK:
			push_error("PhysicsProxyGenerator: Failed to create output directory: " + dir_path)
			return false
			
	# Save the GLB file
	var out_file = FileAccess.open(out_glb_path, FileAccess.WRITE)
	if not out_file:
		push_error("PhysicsProxyGenerator: Failed to open output path for writing: " + out_glb_path)
		return false
	out_file.store_buffer(response_data)
	out_file.close()
	
	print("PhysicsProxyGenerator: Saved MeshFlow mesh to ", out_glb_path)
	return true

func _load_mesh_from_glb_file(file_path: String) -> ArrayMesh:
	var global_path = ProjectSettings.globalize_path(file_path)
	print("PhysicsProxyGenerator: Loading GLB from global path: ", global_path)
	if not FileAccess.file_exists(global_path):
		push_error("PhysicsProxyGenerator: GLB file does not exist at: " + global_path)
		return null
		
	var gltf_doc = GLTFDocument.new()
	var gltf_state = GLTFState.new()
	var err = gltf_doc.append_from_file(global_path, gltf_state)
	if err != OK:
		push_error("PhysicsProxyGenerator: GLTFDocument append_from_file failed with error code: " + error_string(err))
		return null
		
	var node = gltf_doc.generate_scene(gltf_state)
	if node:
		print("PhysicsProxyGenerator: Generated GLB scene root node: ", node.name, " (", node.get_class(), ")")
		var mesh = _find_mesh_in_node(node)
		node.queue_free()
		return mesh
	else:
		push_error("PhysicsProxyGenerator: GLTFDocument generate_scene returned null")
	return null

func _find_mesh_in_node(node: Node) -> ArrayMesh:
	print("  Traversing: ", node.name, " (", node.get_class(), ")")
	if node is MeshInstance3D:
		print("    Found MeshInstance3D. Mesh: ", node.mesh)
		return node.mesh as ArrayMesh
	for child in node.get_children():
		var mesh = _find_mesh_in_node(child)
		if mesh:
			return mesh
	return null

## Auto-generate proxy from splats (very simplified AABB-based)
func generate_aabb_collider(splattable: FoveaSplattable) -> BoxShape3D:
	var shape = BoxShape3D.new()
	var aabb = splattable.get_aabb()
	shape.size = aabb.size
	return shape

