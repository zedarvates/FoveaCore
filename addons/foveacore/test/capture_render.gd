extends SceneTree
## Deterministic render capture for visual-regression testing (Phase 0, C4).
##
## Loads the reference fixture through FoveaSplat3D under a FIXED camera, lets the
## frame settle, and saves the rendered viewport to a PNG. CI compares the PNG to
## a committed golden (perceptual RMSE) or, on first run, uploads it as the baseline.
##
## MUST run with a real (software) rendering driver, NOT --headless (dummy renderer
## = blank image). In CI: xvfb-run + Mesa lavapipe (Vulkan). Example:
##   xvfb-run -a ./godot --rendering-driver vulkan --resolution 800x600 \
##       --path . -s res://addons/foveacore/test/capture_render.gd -- --out=capture.png

const FoveaSplat3DScript := preload("res://addons/foveacore/scripts/fovea_splat_3d.gd")
const FIXTURE := "res://test/fixtures/reference_3dgs.ply"
const SETTLE_FRAMES := 90  # let PLY load + HLOD + first draw settle (deterministic)

var _out := "user://capture.png"

func _init() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")

	print("Capture: fixture=%s out=%s" % [FIXTURE, _out])

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
	splat.set("source_path", FIXTURE)

	for _i in range(SETTLE_FRAMES):
		await process_frame
	# Ensure the final frame is fully drawn before grabbing pixels.
	await RenderingServer.frame_post_draw

	var img: Image = get_root().get_texture().get_image()
	if img == null:
		push_error("Capture: viewport image is null (running headless?)")
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
