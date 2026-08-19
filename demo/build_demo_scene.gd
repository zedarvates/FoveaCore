extends SceneTree
## Builds demo/drop_a_ply.tscn programmatically so the output is always valid
## (Phase 0, E2). Run once; the scene is committed.
##
##   godot --headless --path . -s res://demo/build_demo_scene.gd
##
## The demo: a standard Godot environment (sky + sun), a FoveaSplat3D loading the
## reference fixture, an orbit-friendly camera, and an FPS overlay. Open it and
## press F5.

const FoveaSplat3DScript := preload("res://addons/foveacore/scripts/fovea_splat_3d.gd")
const FpsOverlayScript := preload("res://demo/fps_overlay.gd")
const DefaultSplatDemoScript := preload("res://demo/default_splat_demo.gd")
const VIDEO_SPLAT := "res://reconstructions/horse_statue_cc0_v1/fovea_runtime/horse_statue_6999_runtime_v1.ply"
const OUT := "res://demo/drop_a_ply.tscn"

func _init() -> void:
	var root := Node3D.new()
	root.name = "DropAPlyDemo"
	root.set_script(DefaultSplatDemoScript)

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.06, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.4, 0.4)
	env.environment = e
	_attach(root, env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	_attach(root, sun)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.2, 5)).looking_at(Vector3.ZERO, Vector3.UP)
	_attach(root, cam)

	var splat: Node3D = FoveaSplat3DScript.new()
	splat.name = "FoveaSplat3D"
	splat.set("source_path", VIDEO_SPLAT)
	_attach(root, splat)

	var layer := CanvasLayer.new()
	layer.name = "HUD"
	_attach(root, layer)
	var label: Label = Label.new()
	label.name = "FpsOverlay"
	label.set_script(FpsOverlayScript)
	label.position = Vector2(12, 8)
	label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	layer.add_child(label)
	label.owner = root

	var source_status: Label = Label.new()
	source_status.name = "SourceStatus"
	source_status.position = Vector2(12, 32)
	source_status.text = "Resolving splat source..."
	layer.add_child(source_status)
	source_status.owner = root

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("Demo: pack failed: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	if err != OK:
		push_error("Demo: save failed: %d" % err)
		root.free()
		quit(1)
		return
	print("Demo scene written: %s" % OUT)
	root.free()  # nodes were never in a tree → free to release their RIDs
	quit(0)

func _attach(root: Node, child: Node) -> void:
	root.add_child(child)
	child.owner = root
