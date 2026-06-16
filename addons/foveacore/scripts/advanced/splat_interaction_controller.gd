extends Node
class_name SplatInteractionController

## SplatInteractionController — Handling soft body and liquid interactions
## Moves splats based on proximity to interaction sources (Hands/Tools)

@export var interaction_radius: float = 0.3
@export var repulsion_force: float = 1.2
@export var liquid_swirl_strength: float = 0.5
@export var damping: float = 0.1

# Stores active splat indices: FoveaSplattable -> Array[int]
var _active_splats: Dictionary = {}

func _process(delta: float) -> void:
	if delta <= 0.0:
		return

	# Clean up any invalid or deleted splattable references
	var active_keys = _active_splats.keys()
	for splattable in active_keys:
		if not is_instance_valid(splattable) or not splattable.is_inside_tree():
			_active_splats.erase(splattable)

	# Find all interaction sources
	var sources = get_tree().get_nodes_in_group("interaction_sources")
	
	# Process splattables
	var splattables = get_tree().get_nodes_in_group("splattables")
	for splattable in splattables:
		if not splattable is FoveaSplattable:
			continue
		
		if splattable.loaded_splats.is_empty():
			continue

		_interact_with_splats(splattable, sources, delta)

func _interact_with_splats(splattable: FoveaSplattable, sources: Array, delta: float) -> void:
	# 1. Ensure spatial grid is initialized and matches the interaction radius
	if splattable.spatial_grid == null or not is_equal_approx(splattable.spatial_grid.cell_size, interaction_radius):
		splattable.spatial_grid = FoveaSplattable.SplatSpatialHashGrid.new(interaction_radius, splattable.loaded_splats)

	# 2. Get the current active indices for this splattable
	var active_set: Dictionary = {}
	var current_active: Array = _active_splats.get(splattable, [])
	for idx in current_active:
		active_set[idx] = true

	# 3. For each interaction source, query near splats and activate them
	var global_scale = splattable.global_transform.basis.get_scale().x
	var local_radius = interaction_radius / (global_scale if global_scale > 0.001 else 1.0)
	
	# If we have active sources, find the splats near them
	for source in sources:
		if not is_instance_valid(source) or not source.is_inside_tree():
			continue
		var local_source_pos = splattable.to_local(source.global_position)
		var near_indices = splattable.spatial_grid.get_indices_in_radius(local_source_pos, local_radius)
		for idx in near_indices:
			active_set[idx] = true

	# 4. If there are no active splats to update, we can return early
	if active_set.is_empty():
		return

	# 5. Process physics and spring-back for all active splats
	var next_active: Array[int] = []
	
	# Cache local positions of the sources for fast distance checks
	var local_sources_pos: Array[Vector3] = []
	for source in sources:
		if is_instance_valid(source) and source.is_inside_tree():
			local_sources_pos.append(splattable.to_local(source.global_position))

	for idx in active_set:
		var splat: GaussianSplat = splattable.loaded_splats[idx]
		var total_force: Vector3 = Vector3.ZERO
		var splat_current_pos = splat.position + splat.origin_offset

		for local_src in local_sources_pos:
			var dist_vec = splat_current_pos - local_src
			var dist = dist_vec.length()
			
			if dist < local_radius and dist > 0.0001:
				# Direct repulsion in local space
				var push = dist_vec.normalized() * (1.0 - dist / local_radius) * repulsion_force
				
				# Special Liquid Swirl behavior
				if splat.layer_type == GaussianSplat.LayerType.LIQUID:
					var up_dir = splat.surface_normal.normalized() if splat.surface_normal.length_squared() > 0.01 else Vector3.UP
					var swirl = dist_vec.cross(up_dir).normalized() * liquid_swirl_strength
					push += swirl
					
				total_force += push
		
		# Physics update (simplified Verlet/Euler)
		splat.velocity += total_force * delta
		
		# Spring back to original position (stiffness)
		var spring_force = -splat.origin_offset * splat.stiffness
		splat.velocity += spring_force * delta
		
		# Apply damping (frame-rate independent approximation based on 60 FPS reference)
		var damping_factor = clamp(1.0 - damping * delta * 60.0, 0.0, 1.0)
		splat.velocity *= damping_factor
		
		splat.origin_offset += splat.velocity * delta

		# Check if the splat is back to rest
		# Using a tiny epsilon (0.001) for performance and stability
		if splat.origin_offset.length_squared() < 0.0001 and splat.velocity.length_squared() < 0.0001:
			splat.origin_offset = Vector3.ZERO
			splat.velocity = Vector3.ZERO
		else:
			next_active.append(idx)

	# Store the remaining active splats
	if next_active.is_empty():
		_active_splats.erase(splattable)
	else:
		_active_splats[splattable] = next_active
