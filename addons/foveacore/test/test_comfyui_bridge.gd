extends SceneTree

const COMFYUI_BRIDGE := preload("res://addons/foveacore/scripts/advanced/neural_style_bridge.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_workflow_configuration()
	_test_output_discovery()
	_test_endpoint_normalization()
	print("ComfyUI bridge: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_workflow_configuration() -> void:
	var bridge: NeuralStyleBridge = COMFYUI_BRIDGE.new()
	bridge.checkpoint_name = "fovea-test.safetensors"
	bridge.positive_prompt_suffix = "studio light"
	bridge.negative_prompt = "watermark"
	bridge.intensity = 0.42

	var workflow: Dictionary = bridge.build_img2img_workflow("source.png", "bonsai splat", 1234)
	var prompt: Dictionary = workflow.get("prompt", {})
	_expect("workflow exposes the ComfyUI API prompt graph", prompt.size() == 8)
	_expect("workflow uses the configured deterministic seed", prompt["3"]["inputs"]["seed"] == 1234)
	_expect("workflow uses the configured denoise value", is_equal_approx(prompt["3"]["inputs"]["denoise"], 0.42))
	_expect("workflow does not hard-code the checkpoint", prompt["4"]["inputs"]["ckpt_name"] == "fovea-test.safetensors")
	_expect("workflow injects the uploaded image name", prompt["11"]["inputs"]["image"] == "source.png")
	_expect("workflow appends the configured prompt suffix", prompt["5"]["inputs"]["text"] == "bonsai splat, studio light")
	_expect("workflow uses the configured negative prompt", prompt["6"]["inputs"]["text"] == "watermark")


func _test_output_discovery() -> void:
	var bridge: NeuralStyleBridge = COMFYUI_BRIDGE.new()
	var history_entry: Dictionary = {
		"outputs": {
			"42": {
				"images": [{
					"filename": "result.png",
					"subfolder": "fovea",
					"type": "output"
				}]
			}
		}
	}
	var image_info: Dictionary = bridge.find_first_output_image(history_entry)
	_expect("output lookup supports arbitrary ComfyUI node IDs", image_info.get("filename", "") == "result.png")
	_expect("output lookup preserves the artifact subfolder", image_info.get("subfolder", "") == "fovea")
	_expect("output lookup fails closed when no image exists", bridge.find_first_output_image({"outputs": {"7": {}}}).is_empty())


func _test_endpoint_normalization() -> void:
	var bridge: NeuralStyleBridge = COMFYUI_BRIDGE.new()
	bridge.comfyui_url = "http://127.0.0.1:8188/"
	_expect("endpoint normalization avoids duplicate slashes", bridge._endpoint("/prompt") == "http://127.0.0.1:8188/prompt")


func _expect(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("PASS: " + label)
	else:
		_failed += 1
		push_error("FAIL: " + label)
