# ============================================================================
# FoveaEngine : proxy_face_renderer.gd
# LOD Dynamique : Remplace des millions de Splats par un Fake Volume 2D
# ============================================================================

extends Node3D
class_name FoveaProxyFaceRenderer

@export var target_splattable: Node3D # Le FoveaSplattable (MultiMesh) à remplacer
@export var switch_distance: float = 30.0 # Distance d'activation en mètres
@export var proxy_material: ShaderMaterial # Matériau utilisant fake_volume.gdshader
@export var proxy_scale: Vector2 = Vector2(1.0, 1.0)

var _proxy_mesh_instance: MeshInstance3D
var _camera: Camera3D

func _ready() -> void:
	# 1. Création dynamique du Quad (Seulement 2 triangles !)
	_proxy_mesh_instance = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = proxy_scale
	_proxy_mesh_instance.mesh = quad
	
	if proxy_material == null:
		proxy_material = ShaderMaterial.new()
		proxy_material.shader = preload("res://addons/foveacore/shaders/fake_volume.gdshader")
		proxy_material.set_shader_parameter("base_color", Color(1.0, 0.8, 0.6, 1.0))
		proxy_material.set_shader_parameter("radius", 0.5)
		proxy_material.set_shader_parameter("falloff", 2.0)
		proxy_material.set_shader_parameter("depth_scale", 0.5)
		
	_proxy_mesh_instance.material_override = proxy_material
		
	add_child(_proxy_mesh_instance)
	_proxy_mesh_instance.hide() # Caché par défaut si on est près

	# Initialize texture baking if we have target splattable
	if target_splattable:
		call_deferred("update_proxy_texture_from_splats")

func _process(_delta: float) -> void:
	# 2. Recherche robuste de la caméra active (Correction Tâche #44)
	# Compatible avec le mode Desktop ET les casques VR (XRCamera3D)
	if not _camera or not is_instance_valid(_camera):
		var viewport = get_viewport()
		if viewport:
			_camera = viewport.get_camera_3d()
			
	if not _camera or not target_splattable:
		return
		
	# 3. Calcul de la distance
	var dist := global_position.distance_to(_camera.global_position)
	
	# 4. Bascule (Switch) de LOD
	if dist > switch_distance:
		# Trop loin : On affiche le Proxy (1 Quad) et on coupe le rendu lourd
		if not _proxy_mesh_instance.visible:
			_proxy_mesh_instance.show()
			if "visible" in target_splattable:
				target_splattable.visible = false
				
	else:
		# Assez près : On affiche les Splats en haute qualité (Fovéation dynamique)
		if _proxy_mesh_instance.visible:
			_proxy_mesh_instance.hide()
			if "visible" in target_splattable:
				target_splattable.visible = true

func update_proxy_texture_from_splats() -> void:
	if not target_splattable:
		return
		
	var mesh: Mesh = null
	if "original_mesh" in target_splattable and target_splattable.original_mesh != null:
		mesh = target_splattable.original_mesh
	elif "_mesh_instance_ref" in target_splattable and target_splattable._mesh_instance_ref != null:
		mesh = target_splattable._mesh_instance_ref.mesh
		
	if not mesh:
		return
		
	# Generate layered splats using the generator
	var splats = LayeredSplatGenerator.generate_layered_splats(mesh)
	if splats.is_empty():
		return
		
	# Bake splats into a 2D projected image texture
	var baked_texture = bake_splats_to_texture(splats, 256)
	if baked_texture and _proxy_mesh_instance:
		var mat = _proxy_mesh_instance.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("proxy_texture", baked_texture)

func bake_splats_to_texture(splats: Array[GaussianSplat], texture_size: int = 256) -> ImageTexture:
	if splats.is_empty():
		return null
		
	# Find local AABB bounding box of the splats
	var aabb_min := Vector3(INF, INF, INF)
	var aabb_max := Vector3(-INF, -INF, -INF)
	for splat in splats:
		aabb_min = aabb_min.min(splat.position)
		aabb_max = aabb_max.max(splat.position)
		
	var size_x: float = max(aabb_max.x - aabb_min.x, 0.001)
	var size_y: float = max(aabb_max.y - aabb_min.y, 0.001)
	
	# Create a blank transparent image
	var img := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	# Project 3D splats onto the XY plane in local space (front projection)
	for splat in splats:
		var u: float = (splat.position.x - aabb_min.x) / size_x
		var v: float = 1.0 - ((splat.position.y - aabb_min.y) / size_y) # Flip Y for image coords
		
		var px: int = int(u * texture_size)
		var py: int = int(v * texture_size)
		
		# Splat radius in pixel space
		var radius_px: int = max(int((splat.radius / max(size_x, size_y)) * texture_size), 2)
		
		# Rasterize a Gaussian blob into the image
		for dy in range(-radius_px, radius_px + 1):
			for dx in range(-radius_px, radius_px + 1):
				var target_x: int = px + dx
				var target_y: int = py + dy
				
				if target_x >= 0 and target_x < texture_size and target_y >= 0 and target_y < texture_size:
					var dist_sq: int = dx * dx + dy * dy
					var rad_sq: float = float(radius_px * radius_px)
					if dist_sq <= rad_sq:
						# Gaussian falloff formula
						var factor: float = exp(-float(dist_sq) / (0.5 * rad_sq))
						var weight: float = factor * splat.opacity
						
						if weight > 0.01:
							var current_color: Color = img.get_pixel(target_x, target_y)
							var splat_color: Color = splat.color
							
							# Standard Alpha blending: source over destination
							var new_alpha: float = current_color.a + weight * (1.0 - current_color.a)
							if new_alpha > 0.001:
								var current_rgb := Vector3(current_color.r, current_color.g, current_color.b)
								var splat_rgb := Vector3(splat_color.r, splat_color.g, splat_color.b)
								var new_rgb: Vector3 = (current_rgb * current_color.a * (1.0 - weight) + splat_rgb * weight) / new_alpha
								img.set_pixel(target_x, target_y, Color(new_rgb.x, new_rgb.y, new_rgb.z, new_alpha))
								
	return ImageTexture.create_from_image(img)