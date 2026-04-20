@tool
extends Node
class_name LayeredFoveatedController

## LayeredFoveatedController — Optimizes rendering based on Gaze and Splat Layer Type
## Concept: Digital Painting (Layered approach to light, color, and saturation)

@export var foveal_radius: float = 0.2 # Focus zone
@export var manager: Node = null # FoveaCoreManager

## Detail multipliers by layer type
var layer_settings = {
	GaussianSplat.LayerType.BASE: {"foveal": 0.8, "peripheral": 0.3},
	GaussianSplat.LayerType.SATURATION: {"foveal": 1.0, "peripheral": 0.0}, # Culled in periphery
	GaussianSplat.LayerType.LIGHT: {"foveal": 1.2, "peripheral": 0.1},      # Highlights only in focus
	GaussianSplat.LayerType.SHADOW: {"foveal": 1.0, "peripheral": 0.0}      # Shadows only in focus
}

func calculate_layered_weight(splat: GaussianSplat, gaze_point: Vector3, camera_pos: Vector3) -> float:
	var distance_to_gaze = splat.position.distance_to(gaze_point)
	var is_in_focus = distance_to_gaze <= foveal_radius
	
	var settings = layer_settings.get(splat.layer_type, layer_settings[GaussianSplat.LayerType.BASE])
	
	# Base weight from focus
	var weight = settings["foveal"] if is_in_focus else settings["peripheral"]
	
	# Distance-based fading
	var dist_to_cam = splat.position.distance_to(camera_pos)
	var distance_factor = clamp(1.0 - (dist_to_cam / 50.0), 0.1, 1.0)
	
	return weight * distance_factor

## Filter and optimize splats for the current frame
func optimize_layered_splats(all_splats: Array[GaussianSplat], gaze_point: Vector3, cam_pos: Vector3) -> Array[GaussianSplat]:
	var optimized: Array[GaussianSplat] = []
	
	for splat in all_splats:
		var weight = calculate_layered_weight(splat, gaze_point, cam_pos)
		
		# Apply the artistic painting logic:
		# Saturation and Light layers are ONLY high-density in the foveal region
		if weight > 0.05:
			# We don't just change opacity, we can change radius to 'blend' like paint
			if not gaze_point.is_equal_approx(Vector3.ZERO):
				# Detail expands in center, blurs in periphery
				var dist = splat.position.distance_to(gaze_point)
				splat.radius = splat.radius * (1.0 + (dist / foveal_radius))
			
			splat.opacity = weight
			optimized.append(splat)
			
	return optimized
