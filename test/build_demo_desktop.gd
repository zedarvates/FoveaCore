extends SceneTree

func _init() -> void:
	print("--- Starting Desktop Demo Build Script ---")
	
	# 1. Convert demo_bonsai.ply to demo_bonsai.fovea
	print("Loading res://test/demo_bonsai.ply...")
	var splattable = FoveaSplattable.new()
	splattable.splat_file_path = "res://test/demo_bonsai.ply"
	splattable._load_splats_from_ply()
	
	if splattable.loaded_splats.is_empty():
		push_error("Error: Failed to load demo_bonsai.ply.")
		quit(1)
		return
		
	print("Converting and exporting to res://test/demo_bonsai.fovea...")
	var success = splattable.export_to_fovea("res://test/demo_bonsai.fovea")
	if not success:
		push_error("Error: Failed to export to .fovea.")
		quit(1)
		return
		
	# 2. Build the Demo Desktop Scene
	print("Building scene hierarchy...")
	var root := Node3D.new()
	root.name = "DemoDesktop"
	
	# DirectionalLight3D
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.transform = Transform3D(Basis().rotated(Vector3.RIGHT, -PI/4).rotated(Vector3.UP, PI/4), Vector3.ZERO)
	root.add_child(light)
	light.owner = root
	
	# WorldEnvironment
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.1, 0.1, 0.1)
	env_node.environment = env
	root.add_child(env_node)
	env_node.owner = root
	
	# Flying camera
	var camera := Camera3D.new()
	camera.name = "FlyingCamera"
	camera.transform = Transform3D(Basis(), Vector3(0, 1.5, 3))
	camera.set_script(load("res://test/demo_desktop_camera.gd"))
	root.add_child(camera)
	camera.owner = root
	
	# Splat Renderer
	var splat_renderer = load("res://addons/foveacore/scripts/advanced/fovea_core_splat_renderer.gd").new()
	splat_renderer.name = "SplatRenderer"
	splat_renderer.set("asset_path", "res://test/demo_bonsai.fovea")
	root.add_child(splat_renderer)
	splat_renderer.owner = root
	
	# Desktop UI
	var ui := CanvasLayer.new()
	ui.name = "DesktopUI"
	ui.set_script(load("res://test/demo_desktop_ui.gd"))
	root.add_child(ui)
	ui.owner = root
	
	# 3. Save the Scene
	print("Saving test/demo_desktop.tscn...")
	var packed_scene := PackedScene.new()
	var result := packed_scene.pack(root)
	if result == OK:
		var err := ResourceSaver.save(packed_scene, "res://test/demo_desktop.tscn")
		if err == OK:
			print("Successfully built test/demo_desktop.tscn!")
			quit(0)
		else:
			push_error("Error saving packed scene: " + error_string(err))
			quit(1)
	else:
		push_error("Error packing scene: " + error_string(result))
		quit(1)
