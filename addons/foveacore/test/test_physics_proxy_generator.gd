extends SceneTree

## Unit tests for PhysicsProxyGenerator
## Validates convex shape extraction, parenting, and MeshFlow-driven rigid body pipelines.

const PhysicsProxyGeneratorScript := preload("res://addons/foveacore/scripts/advanced/physics_proxy_generator.gd")
const FoveaSplattableScript := preload("res://addons/foveacore/scripts/fovea_splattable.gd")
const GaussianSplatScript := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

var _passed := 0
var _failed := 0

signal all_complete(passed: int, failed: int)

func _init() -> void:
	print("\n" + "─".repeat(70))
	print("PhysicsProxyGenerator Unit Tests")
	print("─".repeat(70))

	await create_timer(0.2).timeout
	_run_all()

func _run_all() -> void:
	_test_convex_generation()
	_test_meshflow_physics_pipeline()
	await _test_meshflow_live_integration()
	
	print("\n" + "─".repeat(70))
	print("PhysicsProxyGenerator Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("─".repeat(70))
	all_complete.emit(_passed, _failed)
	
	if _failed > 0:
		quit(1)
	else:
		quit(0)

func _test_convex_generation() -> void:
	print("\n--- _test_convex_generation ---")
	
	var generator = PhysicsProxyGeneratorScript.new()
	
	# Create a dummy triangle mesh (a simple tetrahedron)
	var mesh = ArrayMesh.new()
	var vertices = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0, 1, 0),
		Vector3(0, 0, 1)
	])
	var indices = PackedInt32Array([
		0, 1, 2,
		0, 2, 3,
		0, 3, 1,
		1, 3, 2
	])
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	var convex_shape = generator.generate_convex_collider_from_mesh(mesh)
	_assert("Convex shape generated", convex_shape != null, "generate_convex_collider_from_mesh returned non-null")
	if convex_shape != null:
		_assert("Convex shape has points", convex_shape.points.size() == 4, "Extracted %d points for convex hull" % convex_shape.points.size())
		_assert("Convex point 0 correct", convex_shape.points[0].is_equal_approx(Vector3(0,0,0)), "")
		_assert("Convex point 3 correct", convex_shape.points[3].is_equal_approx(Vector3(0,0,1)), "")
		
	generator.queue_free()

func _test_meshflow_physics_pipeline() -> void:
	print("\n--- _test_meshflow_physics_pipeline ---")
	
	var root = Node3D.new()
	
	# Create FoveaSplattable
	var splattable = FoveaSplattableScript.new()
	splattable.name = "MyTestSplat"
	root.add_child(splattable)
	
	# Add some dummy splats to populate loaded_splats
	for i in range(10):
		var s = GaussianSplatScript.new(Vector3(float(i) * 0.1, 0, 0))
		s.opacity = 0.9
		s.scale = Vector3(0.01, 0.01, 0.01)
		splattable.loaded_splats.append(s)
	splattable.has_ply_splats = true
	
	var generator = PhysicsProxyGeneratorScript.new()
	generator.mass = 5.0
	generator.collision_layers = 2
	root.add_child(generator)
	
	# Run pipeline (it should fallback to AABB Box shape since there's no pre-generated GLB on disk and server is queried on a dummy URL)
	var body = generator.generate_physics_via_meshflow(splattable, "http://localhost:9999/process")
	_assert("Physics body returned", body != null, "generate_physics_via_meshflow returned a RigidBody3D")
	
	if body != null:
		_assert("RigidBody mass correct", is_equal_approx(body.mass, 5.0), "Mass: %f" % body.mass)
		_assert("RigidBody collision layer correct", body.collision_layer == 2, "Layer: %d" % body.collision_layer)
		
		# Verify child structures
		var collision_shape: CollisionShape3D = null
		var splat_child: FoveaSplattable = null
		for child in body.get_children():
			if child is CollisionShape3D:
				collision_shape = child
			elif child is FoveaSplattable:
				splat_child = child
				
		_assert("CollisionShape3D exists", collision_shape != null, "Found collision shape child")
		if collision_shape != null:
			_assert("Box shape fallback used", collision_shape.shape is BoxShape3D, "Shape is BoxShape3D")
			
		_assert("Splattable reparented to RigidBody", splat_child == splattable, "Splat is child of physical body")
		_assert("Splattable transform reset", splattable.transform.is_equal_approx(Transform3D.IDENTITY), "Transform is Identity")
		
		body.queue_free()
		
	# Clean up
	root.queue_free()

func _test_meshflow_live_integration() -> void:
	print("\n--- _test_meshflow_live_integration ---")
	
	var root = Node3D.new()
	
	# Create FoveaSplattable
	var splattable = FoveaSplattableScript.new()
	splattable.name = "MyTestSplatLive"
	root.add_child(splattable)
	
	# Add some dummy splats to populate loaded_splats
	for i in range(10):
		var s = GaussianSplatScript.new(Vector3(float(i) * 0.1, 0, 0))
		s.opacity = 0.9
		s.scale = Vector3(0.01, 0.01, 0.01)
		splattable.loaded_splats.append(s)
	splattable.has_ply_splats = true
	
	var generator = PhysicsProxyGeneratorScript.new()
	generator.mass = 3.5
	generator.collision_layers = 4
	root.add_child(generator)
	
	# Run pipeline against the live local server running on port 8009
	var body = generator.generate_physics_via_meshflow(splattable, "http://127.0.0.1:8009/process")
	_assert("Live physics body returned", body != null, "generate_physics_via_meshflow returned a RigidBody3D")
	
	if body != null:
		_assert("Live RigidBody mass correct", is_equal_approx(body.mass, 3.5), "Mass: %f" % body.mass)
		_assert("Live RigidBody collision layer correct", body.collision_layer == 4, "Layer: %d" % body.collision_layer)
		
		# Verify child structures
		var collision_shape: CollisionShape3D = null
		var splat_child: FoveaSplattable = null
		for child in body.get_children():
			if child is CollisionShape3D:
				collision_shape = child
			elif child is FoveaSplattable:
				splat_child = child
				
		_assert("Live CollisionShape3D exists", collision_shape != null, "Found collision shape child")
		if collision_shape != null:
			_assert("Live ConvexPolygonShape3D used", collision_shape.shape is ConvexPolygonShape3D, "Shape is ConvexPolygonShape3D")
			
		body.queue_free()
		
	# Clean up file generated by test
	var expected_path = "res://reconstructions/physics_MyTestSplatLive.glb"
	# if FileAccess.file_exists(expected_path):
	# 	DirAccess.remove_absolute(expected_path)
		
	root.queue_free()

func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_pass(name if detail.is_empty() else "%s — %s" % [name, detail])
	else:
		_fail(name, detail)

func _pass(detail: String) -> void:
	_passed += 1
	print("  ✓ %s" % detail)

func _fail(test_name: String, err: String) -> void:
	_failed += 1
	print("  ✗ %s — %s" % [test_name, err])
