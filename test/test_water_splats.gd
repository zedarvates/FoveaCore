extends Node3D

## Script de test pour le système de splats d'eau volatils et recyclés
## Génère procéduralement le nuage de splats d'eau et anime l'obstacle

@export var water_renderer: MultiMeshInstance3D
@export var obstacle_node: Node3D
@export var obstacle_node_2: Node3D
@export var obstacle_radius_2 := 0.8
@export var box_obstacle_node: Node3D
@export var use_heightmap := false
@export var heightmap_texture: Texture2D
@export var heightmap_size := Vector3(10.0, 2.0, 10.0)
@export var heightmap_offset := Vector3(-5.0, -1.0, -5.0)

@export_group("Flux d'Eau")
@export var flow_direction := Vector3(1.0, 0.0, 0.0)
@export var flow_speed := 4.0
@export var flow_cycle_duration := 3.0
## Facteur multiplicateur du rayon pour la distance locale d'advection (ex: 2.0 fois le rayon)
@export var max_distance := 2.0
@export_range(0.0, 1.0) var water_opacity := 0.7

@export_group("Obstacle & Rebond")
@export var obstacle_radius := 1.2
@export var splash_velocity := Vector3(1.5, 3.5, 0.0)
@export var gravity := 9.8
@export var splash_duration := 1.0

# Animation de l'obstacle
@export var animate_obstacle := true
@export var obstacle_animation_speed := 1.2
var _time_passed := 0.0
var _obstacle_base_pos := Vector3.ZERO
var _obstacle_base_pos_2 := Vector3.ZERO

func _ready() -> void:
	if water_renderer == null:
		water_renderer = get_node_or_null("WaterRenderer") as MultiMeshInstance3D

	if water_renderer == null:
		push_error("test_water_splats.gd: water_renderer n'est pas assigné !")
		return

	# 1. Configurer le shader
	var shader = load("res://addons/foveacore/shaders/water_splat_particle.gdshader")
	if shader == null:
		push_error("test_water_splats.gd: Impossible de charger water_splat_particle.gdshader")
		return

	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("splat_subdivisions", water_renderer.splat_subdivisions)
	mat.set_shader_parameter("use_palette", false)
	mat.set_shader_parameter("palette_size", 0)
	water_renderer.material_override = mat

	# 2. Générer le nuage de splats d'eau de façon procédurale
	print("test_water_splats.gd: Génération procédurale du nuage de splats d'eau...")
	var splats: Array[GaussianSplat] = []
	var rng = RandomNumberGenerator.new()
	rng.seed = 1337

	# Générer un flot de 3000 splats
	for i in range(3000):
		# Placer les splats en amont (X négatif si flow est vers X positif)
		# Répartis le long d'une bande de rivière
		var p = Vector3(
			rng.randf_range(-4.0, -1.0),
			rng.randf_range(-0.1, 0.1),
			rng.randf_range(-1.2, 1.2)
		)
		var s = GaussianSplat.new(p)
		
		# Variantes de couleurs bleutées / écume
		var r = rng.randf_range(0.1, 0.3)
		var g = rng.randf_range(0.5, 0.7)
		var b = rng.randf_range(0.8, 1.0)
		s.color = Color(r, g, b)
		
		s.opacity = rng.randf_range(0.6, 0.9)
		
		# Échelle et rotation de base
		s.scale = Vector3(
			rng.randf_range(0.15, 0.35),
			rng.randf_range(0.15, 0.35),
			rng.randf_range(0.02, 0.08)
		)
		s.rotation = Quaternion.IDENTITY
		splats.append(s)

	# Charger les splats dans le renderer
	var count = water_renderer.render_splats(splats)
	print("test_water_splats.gd: %d splats chargés dans le FoveaSplatRenderer." % count)

	# 3. Enregistrer la position de base de l'obstacle
	if obstacle_node:
		_obstacle_base_pos = obstacle_node.position
	if obstacle_node_2:
		_obstacle_base_pos_2 = obstacle_node_2.position

func _process(delta: float) -> void:
	_time_passed += delta

	# Animer doucement l'obstacle de gauche à droite sur l'axe Z
	# pour observer la collision de façon dynamique
	if obstacle_node and animate_obstacle:
		var z_offset = sin(_time_passed * obstacle_animation_speed) * 0.8
		obstacle_node.position = _obstacle_base_pos + Vector3(0.0, 0.0, z_offset)
	if obstacle_node_2 and animate_obstacle:
		var z_offset = cos(_time_passed * obstacle_animation_speed * 0.9) * 0.7
		obstacle_node_2.position = _obstacle_base_pos_2 + Vector3(0.0, 0.0, z_offset)

	# Auto-quit pour la validation automatisée
	if OS.has_feature("headless") or "--quit" in OS.get_cmdline_args():
		if _time_passed > 0.5: # Laisser tourner au moins 0.5s pour tester
			print("test_water_splats.gd: Validation automatique complétée. Fermeture.")
			get_tree().quit()

	if water_renderer == null or water_renderer.material_override == null:
		return
		
	var mat = water_renderer.material_override as ShaderMaterial
	if mat == null:
		return

	# Synchroniser les uniforms du shader
	if obstacle_node:
		mat.set_shader_parameter("obstacle_position", obstacle_node.global_position)
		mat.set_shader_parameter("obstacle_radius", obstacle_radius)
	else:
		mat.set_shader_parameter("obstacle_radius", 0.0)

	if obstacle_node_2:
		mat.set_shader_parameter("obstacle_position_2", obstacle_node_2.global_position)
		mat.set_shader_parameter("obstacle_radius_2", obstacle_radius_2)
	else:
		mat.set_shader_parameter("obstacle_radius_2", 0.0)

	if box_obstacle_node:
		mat.set_shader_parameter("box_obstacle_enabled", true)
		var mesh_instance = box_obstacle_node as MeshInstance3D
		if mesh_instance and mesh_instance.mesh:
			var aabb: AABB = mesh_instance.mesh.get_aabb()
			var world_aabb_min = box_obstacle_node.global_transform * aabb.position
			var world_aabb_max = box_obstacle_node.global_transform * aabb.end
			mat.set_shader_parameter("box_obstacle_min", world_aabb_min.min(world_aabb_max))
			mat.set_shader_parameter("box_obstacle_max", world_aabb_min.max(world_aabb_max))
		else:
			var box_min = box_obstacle_node.global_position - Vector3(0.5, 0.5, 0.5)
			var box_max = box_obstacle_node.global_position + Vector3(0.5, 0.5, 0.5)
			mat.set_shader_parameter("box_obstacle_min", box_min)
			mat.set_shader_parameter("box_obstacle_max", box_max)
	else:
		mat.set_shader_parameter("box_obstacle_enabled", false)

	mat.set_shader_parameter("use_heightmap", use_heightmap)
	if use_heightmap:
		mat.set_shader_parameter("heightmap_texture", heightmap_texture)
		mat.set_shader_parameter("heightmap_size", heightmap_size)
		mat.set_shader_parameter("heightmap_offset", heightmap_offset)

	mat.set_shader_parameter("flow_direction", flow_direction)
	mat.set_shader_parameter("flow_speed", flow_speed)
	mat.set_shader_parameter("flow_cycle_duration", flow_cycle_duration)
	mat.set_shader_parameter("max_distance", max_distance)
	mat.set_shader_parameter("water_opacity", water_opacity)
	mat.set_shader_parameter("splash_velocity", splash_velocity)
	mat.set_shader_parameter("gravity", gravity)
	mat.set_shader_parameter("splash_duration", splash_duration)
