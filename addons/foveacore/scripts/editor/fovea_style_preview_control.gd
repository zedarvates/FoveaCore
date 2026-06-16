@tool
extends MarginContainer

const FoveaStyle = preload("res://addons/foveacore/scripts/fovea_style.gd")
const FoveaMaterial = preload("res://addons/foveacore/scripts/fovea_material.gd")

var object: Object
var viewport_container: SubViewportContainer
var viewport: SubViewport
var sphere: MeshInstance3D
var camera: Camera3D
var light: DirectionalLight3D
var preview_material: StandardMaterial3D

var dragging := false
var drag_start_mouse := Vector2.ZERO
var rotation_start := Vector3.ZERO

func _init(p_object: Object) -> void:
	object = p_object
	custom_minimum_size = Vector2(0, 200)

func _ready() -> void:
	# Container setup
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	add_child(viewport_container) if viewport_container else null # fallback

	# Build the viewport scene tree
	viewport_container = SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(viewport_container)
	
	viewport = SubViewport.new()
	viewport.size = Vector2i(200, 200)
	viewport.own_world_3d = true
	viewport_container.add_child(viewport)
	
	# Light
	light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	viewport.add_child(light)
	
	# Camera
	camera = Camera3D.new()
	camera.position = Vector3(0, 0, 1.8)
	viewport.add_child(camera)
	
	# Sphere Mesh
	sphere = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radial_segments = 64
	mesh.rings = 32
	sphere.mesh = mesh
	viewport.add_child(sphere)
	
	# Material
	preview_material = StandardMaterial3D.new()
	sphere.material_override = preview_material
	
	# Connect change signals
	if object:
		object.changed.connect(_update_preview)
		_update_preview()
		
	set_process_input(true)

func _update_preview() -> void:
	if not is_inside_tree() or not object:
		return
		
	if object is FoveaMaterial:
		preview_material.albedo_color = object.base_color
		preview_material.roughness = object.roughness
		preview_material.metallic = object.metallic
		preview_material.specular = object.specular_strength
		
		# Show visual cue for bump strength
		if object.bump_strength > 0.05:
			preview_material.roughness = clamp(object.roughness + (float(object.noise_octaves) * 0.02), 0.0, 1.0)
			
	elif object is FoveaStyle:
		# Use global visual style config
		match object.visual_style:
			"Realistic":
				preview_material.albedo_color = Color(0.8, 0.8, 0.8)
				preview_material.roughness = 0.5
				preview_material.metallic = 0.1
			"Cartoon":
				preview_material.albedo_color = Color(0.9, 0.4, 0.4)
				preview_material.roughness = 0.9
				preview_material.metallic = 0.0
			"Pixelated":
				preview_material.albedo_color = Color(0.2, 0.8, 0.3)
				preview_material.roughness = 0.8
				preview_material.metallic = 0.0
			"Watercolor":
				preview_material.albedo_color = Color(0.3, 0.6, 0.9)
				preview_material.roughness = 0.95
				preview_material.metallic = 0.0
			"Oil":
				preview_material.albedo_color = Color(0.8, 0.6, 0.2)
				preview_material.roughness = 0.7
				preview_material.metallic = 0.0
			"Crosshatch":
				preview_material.albedo_color = Color(0.1, 0.1, 0.1)
				preview_material.roughness = 1.0
				preview_material.metallic = 0.0
		
		# Apply grain/detail parameters to modify material properties
		preview_material.roughness = clamp(preview_material.roughness + (object.grain - 0.5) * 0.2, 0.0, 1.0)
		preview_material.metallic = clamp(preview_material.metallic + (object.detail - 1.0) * 0.1, 0.0, 1.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging:
				drag_start_mouse = event.position
				rotation_start = sphere.rotation
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		var delta = event.position - drag_start_mouse
		sphere.rotation.y = rotation_start.y + delta.x * 0.01
		sphere.rotation.x = rotation_start.x + delta.y * 0.01
		accept_event()
