extends Node3D

## Script de test pour le système de splats d'eau volatils et recyclés
## Génère procéduralement le nuage de splats d'eau et anime l'obstacle

@export var water_renderer: MultiMeshInstance3D
@export var obstacle_node: Node3D

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

func _process(delta: float) -> void:
	_time_passed += delta

	# Animer doucement l'obstacle de gauche à droite sur l'axe Z
	# pour observer la collision de façon dynamique
	if obstacle_node and animate_obstacle:
		var z_offset = sin(_time_passed * obstacle_animation_speed) * 0.8
		obstacle_node.position = _obstacle_base_pos + Vector3(0.0, 0.0, z_offset)

	# Auto-quit pour la validation automatisée
	if OS.has_feature("headless") or "--quit" in OS.get_cmdline_args():
		if _time_passed > 0.5: # Laisser tourner au moins 0.5s pour tester
			print("test_water_splats.gd: Validation automatique complétée. Fermeture.")
			get_tree().quit()

	if water_renderer == null or obstacle_node == null:
		return
		
	var mat = water_renderer.material_override as ShaderMaterial
	if mat == null:
		return

	# Synchroniser les uniforms du shader
	mat.set_shader_parameter("obstacle_position", obstacle_node.global_position)
	mat.set_shader_parameter("obstacle_radius", obstacle_radius)
	mat.set_shader_parameter("flow_direction", flow_direction)
	mat.set_shader_parameter("flow_speed", flow_speed)
	mat.set_shader_parameter("flow_cycle_duration", flow_cycle_duration)
	mat.set_shader_parameter("max_distance", max_distance)
	mat.set_shader_parameter("water_opacity", water_opacity)
	mat.set_shader_parameter("splash_velocity", splash_velocity)
	mat.set_shader_parameter("gravity", gravity)
	mat.set_shader_parameter("splash_duration", splash_duration)
