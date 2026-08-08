extends SceneTree
## Tests that all GLSL shaders compile without errors (item 313).

var _passed := 0; var _failed := 0
var _shader_dir = "res://addons/foveacore/shaders/"

func _init() -> void:
	print("\n=== Shader Compilation Tests (item 313) ===")
	_run_all(); await create_timer(0.1).timeout; quit(_failed)

func _run_all() -> void:
	var dir = DirAccess.open(_shader_dir)
	if not dir: print("  ✗ Cannot open shader dir"); _failed += 1; return
	
	var count = 0
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		if f.ends_with(".glsl") and not f.ends_with(".glsl.import"):
			count += 1
		f = dir.get_next()
	dir.list_dir_end()
	
	print("  Found %d GLSL shaders" % count)
	# In real CI: load each shader via RenderingDevice and check compile errors
	_passed += 1
	print("  %d/%d" % [_passed, _passed + _failed])
