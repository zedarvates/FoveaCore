extends SceneTree

const FRAME_COUNT: int = 60
const OUTPUT_DIRECTORY: String = "res://reconstructions/horse_statue_cc0_v1/render_frames"
const MASK_OUTPUT_DIRECTORY: String = "res://reconstructions/horse_statue_cc0_v1/render_masks"
const MODEL_PATH: String = "res://reconstructions/horse_statue_cc0_v1/source_model/horse_statue_01_1k.gltf"


func _initialize() -> void:
	call_deferred("_render_turntable")


func _render_turntable() -> void:
	var absolute_output: String = ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var absolute_mask_output: String = ProjectSettings.globalize_path(MASK_OUTPUT_DIRECTORY)
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_output)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("Unable to create turntable output directory: %s" % absolute_output)
		quit(1)
		return
	var mask_mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_mask_output)
	if mask_mkdir_error != OK and mask_mkdir_error != ERR_ALREADY_EXISTS:
		push_error("Unable to create turntable mask directory: %s" % absolute_mask_output)
		quit(1)
		return

	var model_scene: PackedScene = load(MODEL_PATH) as PackedScene
	if model_scene == null:
		push_error("Unable to load CC0 source model: %s" % MODEL_PATH)
		quit(1)
		return

	var scene_root: Node3D = Node3D.new()
	get_root().add_child(scene_root)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.075, 0.085, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.74, 0.86)
	environment.ambient_light_energy = 0.18
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment_node.environment = environment
	scene_root.add_child(environment_node)

	var model: Node3D = model_scene.instantiate() as Node3D
	if model == null:
		push_error("CC0 source model did not instantiate as Node3D")
		quit(1)
		return
	scene_root.add_child(model)

	await process_frame
	var bounds: AABB = _calculate_visual_bounds(model)
	if bounds.size.is_zero_approx():
		push_error("CC0 source model has no usable visual bounds")
		quit(1)
		return

	var center: Vector3 = bounds.get_center()
	var max_extent: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var floor_y: float = bounds.position.y - max_extent * 0.025
	var floor_instance: MeshInstance3D = _add_floor(scene_root, center, floor_y, max_extent)
	_add_lighting(scene_root, center, max_extent)
	var model_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(model, model_meshes)
	var original_overrides: Dictionary = {}
	for mesh_instance: MeshInstance3D in model_meshes:
		original_overrides[mesh_instance] = mesh_instance.material_override
	var mask_material: StandardMaterial3D = StandardMaterial3D.new()
	mask_material.albedo_color = Color.WHITE
	mask_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var color_background: Color = environment.background_color

	var camera: Camera3D = Camera3D.new()
	camera.fov = 42.0
	camera.near = maxf(0.001, max_extent * 0.01)
	camera.far = maxf(10.0, max_extent * 20.0)
	camera.current = true
	scene_root.add_child(camera)

	var half_fov_radians: float = deg_to_rad(camera.fov * 0.5)
	var orbit_radius: float = (max_extent * 0.62) / tan(half_fov_radians)
	var camera_height: float = center.y + bounds.size.y * 0.12
	var target: Vector3 = center + Vector3.UP * bounds.size.y * 0.04

	for frame_index: int in range(FRAME_COUNT):
		var angle: float = TAU * float(frame_index) / float(FRAME_COUNT)
		camera.global_position = Vector3(
			center.x + sin(angle) * orbit_radius,
			camera_height,
			center.z + cos(angle) * orbit_radius
		)
		camera.look_at(target, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_root().get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Viewport capture failed at frame %d" % frame_index)
			quit(1)
			return
		var output_path: String = "%s/frame_%04d.png" % [absolute_output, frame_index]
		var save_error: Error = image.save_png(output_path)
		if save_error != OK:
			push_error("Unable to save %s (error %d)" % [output_path, save_error])
			quit(1)
			return

		floor_instance.visible = false
		environment.background_color = Color.BLACK
		for mesh_instance: MeshInstance3D in model_meshes:
			mesh_instance.material_override = mask_material
		await process_frame
		await RenderingServer.frame_post_draw
		var mask_image: Image = get_root().get_texture().get_image()
		if mask_image == null or mask_image.is_empty():
			push_error("Mask capture failed at frame %d" % frame_index)
			quit(1)
			return
		var mask_output_path: String = "%s/frame_%04d.png" % [absolute_mask_output, frame_index]
		var mask_save_error: Error = mask_image.save_png(mask_output_path)
		if mask_save_error != OK:
			push_error("Unable to save %s (error %d)" % [mask_output_path, mask_save_error])
			quit(1)
			return
		for mesh_instance: MeshInstance3D in model_meshes:
			mesh_instance.material_override = original_overrides[mesh_instance] as Material
		environment.background_color = color_background
		floor_instance.visible = true

	print(
		"TURN_TABLE_RENDER_OK frames=%d bounds=%s output=%s masks=%s"
		% [FRAME_COUNT, bounds, absolute_output, absolute_mask_output]
	)
	quit(0)


func _calculate_visual_bounds(root_node: Node3D) -> AABB:
	var points: Array[Vector3] = []
	_collect_visual_points(root_node, points)
	if points.is_empty():
		return AABB()
	var minimum: Vector3 = points[0]
	var maximum: Vector3 = points[0]
	for point: Vector3 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return AABB(minimum, maximum - minimum)


func _collect_visual_points(node: Node, points: Array[Vector3]) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh != null:
			var mesh_bounds: AABB = mesh_instance.mesh.get_aabb()
			for corner_index: int in range(8):
				points.append(mesh_instance.global_transform * mesh_bounds.get_endpoint(corner_index))
	for child: Node in node.get_children():
		_collect_visual_points(child, points)


func _collect_mesh_instances(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_mesh_instances(child, meshes)


func _add_floor(
	parent: Node3D,
	center: Vector3,
	floor_y: float,
	max_extent: float
) -> MeshInstance3D:
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size = Vector2.ONE * max_extent * 7.0
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.16, 0.18, 0.22)
	floor_material.metallic = 0.0
	floor_material.roughness = 0.78
	floor_mesh.material = floor_material
	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position = Vector3(center.x, floor_y, center.z)
	parent.add_child(floor_instance)
	return floor_instance


func _add_lighting(parent: Node3D, center: Vector3, max_extent: float) -> void:
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.88, 0.74)
	key.light_energy = 0.92
	key.directional_shadow_max_distance = max_extent * 8.0
	key.directional_shadow_fade_start = 0.85
	key.light_angular_distance = 2.5
	key.shadow_enabled = true
	key.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	parent.add_child(key)

	var fill: OmniLight3D = OmniLight3D.new()
	fill.light_color = Color(0.48, 0.68, 1.0)
	fill.light_energy = 0.62
	fill.omni_range = max_extent * 6.0
	fill.position = center + Vector3(-max_extent * 1.8, max_extent * 1.6, max_extent * 1.2)
	parent.add_child(fill)

	var rim: OmniLight3D = OmniLight3D.new()
	rim.light_color = Color(1.0, 0.58, 0.34)
	rim.light_energy = 0.48
	rim.omni_range = max_extent * 5.0
	rim.position = center + Vector3(max_extent * 1.5, max_extent * 1.2, -max_extent * 1.7)
	parent.add_child(rim)
