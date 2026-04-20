extends Node3D
class_name PhysicsProxyGenerator

## PhysicsProxyGenerator — Binds high-fidelity Gaussian Splats to Physical Colliders
## Uses the Low-Poly mesh from StudioTo3D as a proxy for the high-end splats

@export var rigid_body_mode := RigidBody3D.FREEZE_MODE_STATIC
@export var mesh_simplifier: MeshSimplifier = null
@export var collision_layers := 1
@export var mass := 1.0

## Link a Splattable object with a Physics Body (RigidBody3D)
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
	# Current scene setup might need careful handling of transforms
	splattable.get_parent().remove_child(splattable)
	body.add_child(splattable)
	splattable.transform = Transform3D.IDENTITY
	
	print("PhysicsProxyGenerator: Linked ", splattable.name, " to RigidBody with Low-Poly Collider.")
	return body

## Auto-generate proxy from splats (very simplified AABB-based)
func generate_aabb_collider(splattable: FoveaSplattable) -> BoxShape3D:
	# Estimate the volume from the splats list
	# Not as precise as Mesh-based, but faster for quick interaction
	return BoxShape3D.new()
