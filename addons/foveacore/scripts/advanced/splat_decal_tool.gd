@tool
extends Node3D
class_name SplatDecalTool

## SplatDecalTool — Spray weathering decals (rust, moss, snow) directly onto Gaussian Splats.
## Uses spatial disc projections to add splats aligned to the surface normal.

enum DecalType { RUST, MOSS, SNOW, CUSTOM }

@export var decal_type: DecalType = DecalType.MOSS
@export var brush_radius: float = 0.3
@export var custom_color: Color = Color(1.0, 0.5, 0.0)
@export var splat_density: int = 15 # Number of splats per spray action
@export var splat_size: float = 0.05

## Sprays decal splats around a global target position, projecting them onto the splattable's surface
func spray_at_global_position(splattable: FoveaSplattable, global_pos: Vector3, surface_normal: Vector3) -> void:
	if splattable == null:
		return
		
	var local_pos := splattable.to_local(global_pos)
	var local_normal := splattable.global_transform.basis.inverse() * surface_normal
	local_normal = local_normal.normalized()
	
	var new_splats: Array[GaussianSplat] = []
	
	for i in range(splat_density):
		# Random offset in the plane perpendicular to the normal (disk distribution)
		var offset_2d := _random_disk_point() * brush_radius
		
		# Create local coordinate basis matching the normal direction
		var up := Vector3.UP
		if abs(local_normal.dot(up)) > 0.99:
			up = Vector3.RIGHT
		var right := local_normal.cross(up).normalized()
		var forward := local_normal.cross(right).normalized()
		
		var local_offset := right * offset_2d.x + forward * offset_2d.y
		
		# Add a tiny noise perturbation along the normal so it sits slightly on top
		var height_offset := local_normal * randf_range(0.005, 0.02)
		var final_local_pos := local_pos + local_offset + height_offset
		
		var splat := GaussianSplat.new(final_local_pos)
		
		# Align normal with slight random variation
		var rand_normal := (local_normal + _rand_vec(0.15)).normalized()
		splat.normal = rand_normal
		splat.surface_normal = rand_normal
		
		# Apply scale and orientation rotation
		var size := splat_size * randf_range(0.7, 1.3)
		splat.scale = Vector3(size, size, size * 0.15)
		
		if rand_normal.length_squared() > 0.01:
			var normal_up := Vector3.UP
			if abs(rand_normal.dot(normal_up)) > 0.99:
				normal_up = Vector3.RIGHT
			splat.rotation = Quaternion(Basis.looking_at(rand_normal, normal_up))
			
		# Select Color, layer and brush type based on DecalType
		match decal_type:
			DecalType.RUST:
				# Red-orange-brown variations
				splat.color = Color(
					randf_range(0.45, 0.65), # R
					randf_range(0.15, 0.28), # G
					randf_range(0.05, 0.12)  # B
				)
				splat.layer_type = GaussianSplat.LayerType.TRUNK
				splat.brush_type = GaussianSplat.BrushType.STONE # Quad/stoney
			DecalType.MOSS:
				# Forest green variations
				splat.color = Color(
					randf_range(0.12, 0.28), # R
					randf_range(0.45, 0.65), # G
					randf_range(0.08, 0.18)  # B
				)
				splat.layer_type = GaussianSplat.LayerType.LEAVES
				splat.brush_type = GaussianSplat.BrushType.SPONGE # Sponge/Triangle
			DecalType.SNOW:
				# White/light blue variations
				var blue_tint := randf_range(0.9, 1.0)
				splat.color = Color(blue_tint * 0.95, blue_tint * 0.98, 1.0)
				splat.layer_type = GaussianSplat.LayerType.BASE
				splat.brush_type = GaussianSplat.BrushType.GAUSSIAN # Circle/Gaussian
			DecalType.CUSTOM:
				splat.color = custom_color * randf_range(0.85, 1.15)
				splat.layer_type = GaussianSplat.LayerType.BASE
				splat.brush_type = GaussianSplat.BrushType.GAUSSIAN
				
		splat.opacity = randf_range(0.8, 0.98)
		splat.stiffness = 5.0
		splat.compute_derived()
		new_splats.append(splat)
		
	# Append to the splattable array
	splattable.loaded_splats.append_array(new_splats)
	
	# Reset spatial grid to force rebuild with new splats
	splattable.spatial_grid = null
	
	# Trigger editor/local preview update
	if splattable.has_method("_update_local_renderer"):
		splattable.call("_update_local_renderer")

func _random_disk_point() -> Vector2:
	var r := sqrt(randf())
	var theta := randf() * 2.0 * PI
	return Vector2(r * cos(theta), r * sin(theta))

func _rand_vec(spread: float) -> Vector3:
	return Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)
