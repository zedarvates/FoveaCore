extends Node
class_name SplatLightingAnimator

## SplatLightingAnimator — Dynamic lighting simulation for Gaussian Splats
## Moves "Shadow" and "Light" layers based on scene light sources

@export var main_light: DirectionalLight3D = null
@export var shadow_offset_multiplier: float = 0.2
@export var highlight_intensity: float = 1.0

func _process(_delta: float) -> void:
	if main_light == null:
		return
		
	var light_dir = -main_light.global_transform.basis.z.normalized()
	_animate_splat_layers(light_dir)

func _animate_splat_layers(light_dir: Vector3) -> void:
	# 1. Get all Splattables in scene
	# 2. For each splat in its data, check LayerType
	# 3. If SHADOW: move splat in direction OF light (projection)
	# 4. If LIGHT: adjust opacity based on Dot(Light, Normal)
	
	# Implementation note: In a real GDExtension, this would be a Compute Shader.
	# Here we define the logic for the hybrid system.
	
	for splattable in get_tree().get_nodes_in_group("splattables"):
		if not splattable is FoveaSplattable: continue
		
		for splat in splattable.loaded_splats:
			match splat.layer_type:
				GaussianSplat.LayerType.SHADOW:
					# Digital Painting Shadow logic: 
					# Offset the shadow splat away from the light source
					var offset = light_dir.project(splat.surface_normal) * shadow_offset_multiplier
					splat.origin_offset = -offset 
					
				GaussianSplat.LayerType.LIGHT:
					# Highlights intensity based on light direction
					var alignment = clamp(splat.surface_normal.dot(light_dir), 0.0, 1.0)
					splat.opacity = alignment * highlight_intensity
					
				GaussianSplat.LayerType.SATURATION:
					# Saturation can also pop more under direct light
					var alignment = clamp(splat.surface_normal.dot(light_dir), 0.5, 1.0)
					splat.opacity = alignment
