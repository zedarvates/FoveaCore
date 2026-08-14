extends SceneTree

const COMFYUI_SPLAT_BRIDGE := preload(
	"res://addons/foveacore/scripts/reconstruction/comfyui_splat_bridge.gd"
)

var _passed: int = 0
var _failed: int = 0
var _destination_path: String = ""
var _target: FoveaSplat3D = null
var _bridge: Variant = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var server_url: String = _argument_value("--url=")
	if server_url.is_empty():
		_fail_and_quit("Missing --url argument")
		return

	_destination_path = "user://fovea/comfyui/mock_%d.splat" % OS.get_process_id()
	_remove_generated_artifact()
	_target = FoveaSplat3D.new()
	_target.name = "ComfyUIImportedSplat"
	root.add_child(_target)
	await process_frame

	_bridge = COMFYUI_SPLAT_BRIDGE.new()
	_bridge.comfyui_url = server_url
	_bridge.poll_interval_seconds = 0.05
	_bridge.max_poll_attempts = 40
	var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.8, 1.0))
	var workflow: Dictionary = {
		"11": {
			"class_type": "LoadImage",
			"inputs": {"image": "placeholder.png"},
		},
		"20": {
			"class_type": "MockSaveSplat",
			"inputs": {"source": ["11", 0]},
		},
	}
	_bridge.generate_splat_from_image(
		image,
		workflow,
		"11",
		_destination_path,
		_target,
		_on_generation_completed
	)


func _on_generation_completed(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_fail_and_quit(str(result.get("error", "Unknown bridge failure")))
		return
	call_deferred("_verify_import", result)


func _verify_import(result: Dictionary) -> void:
	await process_frame
	_expect("downloaded artifact exists", FileAccess.file_exists(_destination_path))
	_expect("callback returns the destination", result.get("path", "") == _destination_path)
	_expect("artifact is assigned to FoveaSplat3D", _target.source_path == _destination_path)
	var advanced: FoveaSplattable = _target.get_advanced()
	_expect("FoveaSplat3D delegate is available", advanced != null)
	_expect("downloaded .splat reaches the format loader", advanced != null and advanced.loaded_splats.size() == 1)
	_remove_generated_artifact()
	_target.queue_free()
	await process_frame
	print("ComfyUI HTTP bridge: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _argument_value(prefix: String) -> String:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	for argument: String in arguments:
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _expect(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("PASS: " + label)
	else:
		_failed += 1
		push_error("FAIL: " + label)


func _fail_and_quit(detail: String) -> void:
	_failed += 1
	push_error("FAIL: ComfyUI HTTP bridge — " + detail)
	_remove_generated_artifact()
	if _target != null:
		_target.queue_free()
	quit(1)


func _remove_generated_artifact() -> void:
	if not _destination_path.is_empty() and FileAccess.file_exists(_destination_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_destination_path))
