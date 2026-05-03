extends Node
class_name SplatInteractionController

## SplatInteractionController — Handling soft body and liquid interactions
## Moves splats based on proximity to interaction sources (Hands/Tools)

@export var interaction_radius: float = 0.3
@export var repulsion_force: float = 1.2
@export var damping: float = 0.1

func _process(delta: float) -> void:
	# We find all interaction sources (e.g., controllers)
	var sources = get_tree().get_nodes_in_group("interaction_sources")
	
	for splattable in get_tree().get_nodes_in_group("splattables"):
		if not splattable is FoveaSplattable: continue
		_interact_with_splats(splattable, sources, delta)

func _interact_with_splats(splattable: Node, sources: Array, delta: float) -> void:
	for splat in splattable.loaded_splats:
		var total_force: Vector3 = Vector3.ZERO
		var world_pos = splattable.global_transform * (splat.position + splat.origin_offset)
		
		for source in sources:
			var dist_vec = world_pos - source.global_position
			var dist = dist_vec.length()
			
			if dist < interaction_radius:
				# Direct repulsion
				var push = dist_vec.normalized() * (1.0 - dist / interaction_radius) * repulsion_force
				
				# Special Liquid Swirl behavior
				if splat.layer_type == GaussianSplat.LayerType.LIQUID:
					var swirl = dist_vec.cross(Vector3.UP).normalized() * 0.5
					push += swirl
					
				total_force += push
		
		# Physics update (simplified Verlet/Euler)
		splat.velocity += total_force * delta
		splat.origin_offset += splat.velocity * delta
		
		# Spring back to original position (stiffness)
		var spring_force = -splat.origin_offset * splat.stiffness
		splat.velocity += spring_force * delta
		splat.velocity *= (1.0 - damping) # Damping/friction
