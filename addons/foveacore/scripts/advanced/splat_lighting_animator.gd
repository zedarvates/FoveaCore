extends Node
class_name SplatLightingAnimator

## SplatLightingAnimator — Dynamic lighting simulation for Gaussian Splats
## Moves "Shadow" and "Light" layers based on scene light sources

@export var main_light: DirectionalLight3D = null
@export var shadow_offset_multiplier: float = 0.2
@export var highlight_intensity: float = 1.0

var _time_since_light_check: float = 0.0
const LIGHT_CHECK_INTERVAL: float = 1.0

func _ready() -> void:
	if main_light == null:
		_auto_discover_light()

func _process(delta: float) -> void:
	if main_light == null:
		_time_since_light_check += delta
		if _time_since_light_check >= LIGHT_CHECK_INTERVAL:
			_time_since_light_check = 0.0
			_auto_discover_light()
		if main_light == null:
			return
			
	var light_dir: Vector3 = -main_light.global_transform.basis.z.normalized()
	_animate_splat_layers(light_dir)

func _auto_discover_light() -> void:
	if not is_inside_tree():
		return
		
	# 1. Try to find a DirectionalLight3D in the directional_lights group
	var lights: Array[Node] = get_tree().get_nodes_in_group("directional_lights")
	for light in lights:
		if light is DirectionalLight3D:
			main_light = light
			return
			
	# 2. Search recursively in the current scene
	var current_scene: Node = get_tree().current_scene
	if current_scene:
		main_light = _find_light_recursive(current_scene)
		if main_light:
			return
			
	# 3. Search in the entire scene tree root
	main_light = _find_light_recursive(get_tree().root)

func _find_light_recursive(node: Node) -> DirectionalLight3D:
	if node is DirectionalLight3D:
		return node
	for child in node.get_children():
		var found: DirectionalLight3D = _find_light_recursive(child)
		if found:
			return found
	return null

func _animate_splat_layers(light_dir: Vector3) -> void:
	# 1. Get all Splattables in scene
	# 2. For each splat in its data, check LayerType
	# 3. If SHADOW: move splat in direction OF light (projection)
	# 4. If LIGHT: adjust opacity based on Dot(Light, Normal) and Specular view angle
	
	# Implementation note: In a real GDExtension, this would be a Compute Shader.
	# Here we define the logic for the hybrid system.
	
	var camera := get_viewport().get_camera_3d()
	var camera_pos := camera.global_position if camera else Vector3.ZERO
	
	for splattable in get_tree().get_nodes_in_group("splattables"):
		if not splattable is FoveaSplattable: continue
		
		for splat in splattable.loaded_splats:
			match splat.layer_type:
				GaussianSplat.LayerType.SHADOW:
					# Digital Painting Shadow logic: 
					# Offset the shadow splat away from the light source
					var offset: Vector3 = light_dir.project(splat.surface_normal) * shadow_offset_multiplier
					splat.origin_offset = -offset 
					
				GaussianSplat.LayerType.LIGHT:
					# Highlights intensity based on light direction (Lambertian dot product using -light_dir)
					var alignment: float = clamp(splat.surface_normal.dot(-light_dir), 0.0, 1.0)
					
					# Specular highlight based on view-light angle (Blinn-Phong)
					var splat_world_pos: Vector3 = splattable.global_transform * splat.position
					var V: Vector3 = (camera_pos - splat_world_pos).normalized()
					var L: Vector3 = -light_dir.normalized()
					var H: Vector3 = (L + V).normalized()
					var specular_align: float = clamp(splat.surface_normal.dot(H), 0.0, 1.0)
					var specular_intensity: float = pow(specular_align, 16.0)
					
					# Combine diffuse alignment and specular intensity
					splat.opacity = (alignment * 0.3 + specular_intensity * 0.7) * highlight_intensity
					
				GaussianSplat.LayerType.SATURATION:
					# Saturation can also pop more under direct light
					var alignment: float = clamp(splat.surface_normal.dot(-light_dir), 0.5, 1.0)
					splat.opacity = alignment
