extends SceneTree

## Script to compile and validate all GDScript files in the project
## It recursively finds all .gd files, loads them, and verifies they compile without error.

var _passed := 0
var _failed := 0
var _failed_files := []

func _init() -> void:
	print("\n" + "======================================================================")
	print("Checking compilation of all GDScript files...")
	print("======================================================================")

	await create_timer(0.1).timeout
	_check_directory("res://addons/foveacore/scripts")
	_check_directory("res://addons/foveacore/test")
	if DirAccess.dir_exists_absolute("res://test"):
		_check_directory("res://test")
	
	print("\n" + "======================================================================")
	print("Compilation check summary:")
	print("  Passed: %d" % _passed)
	print("  Failed: %d" % _failed)
	if _failed > 0:
		print("  Failed files:")
		for f in _failed_files:
			print("    - %s" % f)
	print("======================================================================")
	
	quit(1 if _failed > 0 else 0)

func _check_directory(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		print("Error: Could not open directory %s" % path)
		_failed += 1
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != "." and file_name != "..":
				_check_directory(path.path_join(file_name))
		else:
			if file_name.ends_with(".gd"):
				_check_file(path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

func _check_file(file_path: String) -> void:
	# Load the script. In Godot 4, load() will compile the GDScript
	var script = load(file_path)
	if script == null:
		print("  ✗ FAIL: %s (Failed to load/compile)" % file_path)
		_failed += 1
		_failed_files.append(file_path)
	elif not script is GDScript:
		print("  ✗ FAIL: %s (Loaded resource is not a GDScript)" % file_path)
		_failed += 1
		_failed_files.append(file_path)
	else:
		# Check if the script can be instantiated (if it's not a tool/EditorPlugin that requires editor context)
		# Just loading is enough to check for syntax/parse errors, but we can do a sanity check on source code.
		print("  ✓ PASS: %s" % file_path)
		_passed += 1
