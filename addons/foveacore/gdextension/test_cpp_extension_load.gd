extends SceneTree

## Manual runtime gate for the experimental Windows C++ extension.
## Build foveacore_cpp.dll first, then run this script with the declared Godot.

const DESCRIPTOR_PATH: String = "res://addons/foveacore/gdextension/foveacore_cpp.gdextension.example"
const BINARY_PATH: String = "res://addons/foveacore/gdextension/bin/foveacore_cpp.dll"

func _init() -> void:
	var binary_path: String = BINARY_PATH
	if OS.get_cmdline_user_args().has("--force-missing-binary"):
		binary_path += ".missing"
	if not FileAccess.file_exists(binary_path):
		push_error("Missing C++ extension binary: %s" % binary_path)
		quit(1)
		return

	var load_status: GDExtensionManager.LoadStatus = GDExtensionManager.load_extension(DESCRIPTOR_PATH)
	if load_status != GDExtensionManager.LOAD_STATUS_OK:
		push_error("C++ extension load failed with status %d" % load_status)
		quit(1)
		return

	var class_registered: bool = ClassDB.class_exists("FoveaRenderer")
	var instance: Object = ClassDB.instantiate("FoveaRenderer") if class_registered else null
	var instance_created: bool = instance != null
	if instance != null:
		instance.free()

	print("CPP_EXTENSION_SMOKE: %s | class_registered=%s instance_created=%s" % [
		"PASS" if class_registered and instance_created else "FAIL",
		str(class_registered),
		str(instance_created),
	])
	quit(0 if class_registered and instance_created else 1)
