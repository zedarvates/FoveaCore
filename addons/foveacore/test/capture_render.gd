extends SceneTree
## Deterministic render capture for visual-regression testing (Phase 0, C4).
##
## Loads a fixture through FoveaSplat3D under a FIXED camera, lets the frame
## settle, and saves the rendered viewport to a PNG. CI compares the default
## reference fixture to a committed golden (perceptual RMSE) or, on first run,
## uploads it as the baseline. Pass --fixture=res://path/to/asset.ply and
## --auto-frame to capture another checked-in asset without changing the
## deterministic CI default.
##
## MUST run with a real (software) rendering driver, NOT --headless (dummy renderer
## = blank image). In CI: xvfb-run + Mesa lavapipe (Vulkan). Example:
##   xvfb-run -a ./godot --rendering-driver vulkan --resolution 800x600 \
##       --path . -s res://addons/foveacore/test/capture_render.gd -- --out=capture.png

const FoveaSplat3DScript := preload("res://addons/foveacore/scripts/fovea_splat_3d.gd")
const DEFAULT_FIXTURE := "res://test/fixtures/reference_3dgs.ply"
const SETTLE_FRAMES := 90  # let PLY load + HLOD + first draw settle (deterministic)

var _out := "user://capture.png"
var _fixture: String = DEFAULT_FIXTURE
var _auto_frame: bool = false
var _local_renderer: bool = false

func _init() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--fixture="):
			_fixture = arg.trim_prefix("--fixture=")
		elif arg == "--auto-frame":
			_auto_frame = true
		elif arg == "--local-renderer":
			_local_renderer = true

	print("Capture: fixture=%s out=%s" % [_fixture, _out])

	# Hard guard: a real rendering driver is required. Under --headless the dummy
	# renderer never emits frame_post_draw, which would hang the capture forever.
	if DisplayServer.get_name() == "headless":
		print("Capture: headless display detected — skipping (use xvfb + a real driver).")
		quit(0)
		return

	await create_timer(0.2).timeout

	var world := Node3D.new()
	get_root().add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.4, 0.4)
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	world.add_child(sun)

	# Fixed camera — reproducible framing is the whole point of a golden image.
	var cam := Camera3D.new()
	cam.current = true
	cam.transform = Transform3D(Basis.IDENTITY, Vector3(2.5, 1.5, 3.5)).looking_at(Vector3.ZERO, Vector3.UP)
	world.add_child(cam)

	var splat: Node3D = FoveaSplat3DScript.new()
	world.add_child(splat)
	if _local_renderer and splat.has_method("get_advanced"):
		var advanced: FoveaSplattable = splat.call("get_advanced") as FoveaSplattable
		if advanced != null:
			advanced.enable_instancing = false
	splat.set("source_path", _fixture)

	var is_framed: bool = not _auto_frame
	for _i in range(SETTLE_FRAMES):
		await process_frame
		if not is_framed:
			is_framed = _try_frame_asset(splat, cam)
	if not is_framed:
		push_error("Capture: could not auto-frame fixture because no splats were loaded.")
		quit(1)
		return
	if _auto_frame:
		for _i in range(30):
			await process_frame
	var rendered_splat_count: int = _get_rendered_splat_count(splat)
	if rendered_splat_count <= 0:
		push_error("Capture: renderer reported zero ready splats.")
		quit(1)
		return
	print("Capture: ready_splats=%d" % rendered_splat_count)
	# Ensure the final frame is fully drawn before grabbing pixels.
	await RenderingServer.frame_post_draw

	var img: Image = get_root().get_texture().get_image()
	if img == null:
		push_error("Capture: viewport image is null (running headless?)")
		quit(1)
		return
	if not _image_has_foreground_signal(img, e.background_color):
		push_error("Capture: rendered image contains no foreground signal.")
		quit(1)
		return
	var err := img.save_png(_out)
	if err != OK:
		push_error("Capture: save_png failed (%d) → %s" % [err, _out])
		quit(1)
		return
	print("Capture: wrote %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	world.queue_free()
	quit(0)


func _try_frame_asset(splat: Node3D, camera: Camera3D) -> bool:
	if not splat.has_method("get_advanced"):
		return false
	var advanced: FoveaSplattable = splat.call("get_advanced") as FoveaSplattable
	if advanced == null or advanced.loaded_splats.is_empty():
		return false

	var bounds: AABB = AABB(advanced.loaded_splats[0].position, Vector3.ZERO)
	for gaussian: GaussianSplat in advanced.loaded_splats:
		bounds = bounds.expand(gaussian.position)

	var center: Vector3 = bounds.get_center()
	var radius: float = maxf(bounds.size.length() * 0.5, 0.1)
	var vertical_half_fov: float = deg_to_rad(camera.fov) * 0.5
	var distance: float = radius / tan(vertical_half_fov) * 1.1
	var view_direction: Vector3 = Vector3(1.0, 0.35, 1.0).normalized()
	camera.near = maxf(radius * 0.001, 0.001)
	camera.far = maxf(distance + radius * 4.0, 1000.0)
	camera.global_position = center + view_direction * distance
	camera.look_at(center, Vector3.UP)
	print("Capture: auto-framed bounds=%s camera=%s" % [bounds, camera.global_position])
	return true


func _get_rendered_splat_count(splat: Node3D) -> int:
	if not splat.has_method("get_advanced"):
		return 0
	var advanced: FoveaSplattable = splat.call("get_advanced") as FoveaSplattable
	if advanced == null:
		return 0
	if not advanced.loaded_splats.is_empty():
		return advanced.loaded_splats.size()

	var local_renderer: MultiMeshInstance3D = advanced.get_node_or_null("FoveaCoreSplatRenderer") as MultiMeshInstance3D
	if local_renderer != null and local_renderer.multimesh != null:
		return local_renderer.multimesh.instance_count

	var manager: Node = get_root().get_node_or_null("FoveaCoreManager")
	if manager == null:
		return 0
	var renderers: Dictionary = manager.get("_instanced_renderers") as Dictionary
	var instanced_renderer: MultiMeshInstance3D = renderers.get(_fixture) as MultiMeshInstance3D
	if instanced_renderer != null and instanced_renderer.multimesh != null:
		return instanced_renderer.multimesh.instance_count
	return 0


func _image_has_foreground_signal(image: Image, background: Color) -> bool:
	var step_x: int = maxi(image.get_width() / 100, 1)
	var step_y: int = maxi(image.get_height() / 75, 1)
	var foreground_samples: int = 0
	for y: int in range(0, image.get_height(), step_y):
		for x: int in range(0, image.get_width(), step_x):
			var pixel: Color = image.get_pixel(x, y)
			var delta: float = (
				absf(pixel.r - background.r)
				+ absf(pixel.g - background.g)
				+ absf(pixel.b - background.b)
			)
			if delta > 0.08:
				foreground_samples += 1
				if foreground_samples >= 8:
					return true
	return false
