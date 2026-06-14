extends SceneTree

## test_node_runner.gd — A generic SceneTree wrapper to run Node-based test scripts headlessly.

func _init() -> void:
	var args = OS.get_cmdline_args()
	var target_script := ""
	
	# Find the script argument that is not the runner itself
	for arg in args:
		if arg.ends_with(".gd") and not arg.contains("test_node_runner.gd") and not arg.contains("run_all_tests.gd"):
			target_script = arg
			break
			
	if target_script == "":
		print("Error: No target test script specified.")
		quit(1)
		return
		
	# Convert relative path to absolute or res://
	if not target_script.begins_with("res://") and not target_script.begins_with("user://"):
		# Ensure we normalize it
		target_script = "res://" + target_script.replace("\\", "/")
		
	var script = load(target_script)
	if not script:
		print("Error: Could not load script %s" % target_script)
		quit(1)
		return
		
	var instance = script.new()
	if not instance:
		print("Error: Could not instantiate script %s" % target_script)
		quit(1)
		return
		
	if instance is Node:
		instance.name = "TestNode"
		root.add_child(instance)
	
	# Give the script time to execute _ready() and any async operations
	await create_timer(1.0).timeout
	
	quit(0)
