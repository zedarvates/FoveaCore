extends SceneTree

## Opt-in live probe for the real ComfyUI Img2Img path.
##
## This file is deliberately not named test_*.gd so the offline test runner never
## discovers it. Run it explicitly and provide absolute input/output paths after
## `--`; it performs one generation and exits with a non-zero code on failure.

const DEFAULT_PROMPT: String = "a mature Japanese bonsai tree with detailed brown weathered bark, many fine branches, crisp small natural green leaves, planted in a ceramic bonsai pot, true botanical colors, professional full-frame studio photograph, soft natural rim lighting, sharp subject, realistic shadows, non-glowing foliage"

var _bridge: NeuralStyleBridge
var _finished: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var input_path: String = _argument_value("--input")
	var output_path: String = _argument_value("--output")
	if input_path.is_empty() or output_path.is_empty():
		push_error("live_comfyui_photoreal_probe: --input and --output are required.")
		quit(2)
		return

	var source: Image = Image.load_from_file(input_path)
	if source == null or source.is_empty():
		push_error("live_comfyui_photoreal_probe: unable to load input image: %s" % input_path)
		quit(3)
		return

	_bridge = NeuralStyleBridge.new()
	_bridge.comfyui_url = _argument_value("--url", "http://127.0.0.1:8000")
	_bridge.comfyui_fallback_urls = PackedStringArray()
	_bridge.intensity = clampf(float(_argument_value("--denoise", "0.60")), 0.0, 1.0)
	var prompt: String = _argument_value("--prompt", DEFAULT_PROMPT)
	print("live_comfyui_photoreal_probe: submitting denoise=%.2f to %s" % [_bridge.intensity, _bridge.comfyui_url])
	_bridge.stylize_texture_comfy(
		source,
		prompt,
		func(result: Image) -> void:
			if result == null or result.is_empty():
				_finish_with_error("ComfyUI returned no image.", 4)
				return
			var save_error: Error = result.save_png(output_path)
			if save_error != OK:
				_finish_with_error("unable to save output (%d): %s" % [save_error, output_path], 5)
				return
			_finished = true
			print("live_comfyui_photoreal_probe: saved %s" % output_path)
			quit(0)
	)

	await create_timer(240.0).timeout
	if not _finished:
		_finish_with_error("probe timeout after 240 seconds.", 6)


func _argument_value(name: String, default_value: String = "") -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(arguments.size() - 1):
		if arguments[index] == name:
			return arguments[index + 1]
	return default_value


func _finish_with_error(message: String, exit_code: int) -> void:
	if _finished:
		return
	_finished = true
	push_error("live_comfyui_photoreal_probe: %s" % message)
	quit(exit_code)
