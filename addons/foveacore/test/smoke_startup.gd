extends SceneTree
## Startup smoke test (Phase 0, C5).
##
## Boots the plugin's autoloads, drops a FoveaSplat3D pointing at the reference
## fixture into a live scene, runs a few frames, and asserts the asset actually
## loaded. This is the "studio-grade stability" guarantee: the plugin must start
## and render a splat cloud cleanly — including in GDScript-only fallback (no
## compiled GDExtension) and across rendering backends.
##
## Exit 0 = OK, exit 1 = failure. CI greps stderr for SCRIPT ERROR / ERROR: on top
## of this exit code, and runs it under each --rendering-method.

const FoveaSplat3DScript := preload("res://addons/foveacore/scripts/fovea_splat_3d.gd")
const PLY_FIXTURE := "res://test/fixtures/reference_3dgs.ply"
const EXPECTED_MIN_SPLATS := 8000

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("FoveaEngine Startup Smoke Test")
	print("  rendering method: %s" % str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")))
	print("  GDExtension native: %s" % str(FileAccess.file_exists("res://addons/foveacore/gdextension/bin/foveacore.dll")))
	print("=".repeat(70))

	# Let autoloads (FoveaCoreManager & co) finish their deferred init.
	await create_timer(0.3).timeout

	if not FileAccess.file_exists(PLY_FIXTURE):
		_die("Fixture missing: %s (run test/fixtures/generate_fixtures.gd)" % PLY_FIXTURE)
		return

	# Build a minimal live scene: root → FoveaSplat3D(fixture).
	var world := Node3D.new()
	world.name = "SmokeWorld"
	get_root().add_child(world)

	var splat: Node3D = FoveaSplat3DScript.new()
	splat.name = "SmokeSplat"
	world.add_child(splat)
	splat.source_path = PLY_FIXTURE

	# Run a handful of frames so _ready/loaders/renderers settle.
	for _i in range(10):
		await process_frame

	var advanced = splat.get_advanced()
	if advanced == null:
		_die("FoveaSplat3D.get_advanced() returned null after frames")
		return

	var count: int = advanced.loaded_splats.size()
	if count < EXPECTED_MIN_SPLATS:
		_die("Loaded %d splats, expected >= %d" % [count, EXPECTED_MIN_SPLATS])
		return

	print("  ✓ FoveaSplat3D loaded %d splats from the fixture" % count)
	print("  ✓ SMOKE OK")
	world.queue_free()
	quit(0)

func _die(msg: String) -> void:
	push_error("SMOKE FAIL: " + msg)
	print("  ✗ SMOKE FAIL: " + msg)
	quit(1)
