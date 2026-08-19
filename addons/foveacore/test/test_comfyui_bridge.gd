extends SceneTree

const COMFYUI_BRIDGE := preload("res://addons/foveacore/scripts/advanced/neural_style_bridge.gd")
const RECONSTRUCTION_SESSION := preload("res://addons/foveacore/scripts/reconstruction/reconstruction_session.gd")
const CORE_SPLAT_RENDERER := preload("res://addons/foveacore/scripts/advanced/fovea_core_splat_renderer.gd")
const RECONSTRUCTION_BACKEND := preload("res://addons/foveacore/scripts/reconstruction/reconstruction_backend.gd")
const CORE_MANAGER_PATH: String = "res://addons/foveacore/scripts/foveacore_manager.gd"
const RECONSTRUCTION_MANAGER_PATH: String = "res://addons/foveacore/scripts/reconstruction/reconstruction_manager.gd"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	_test_photorealistic_defaults()
	_test_checkpoint_preflight()
	_test_workflow_configuration()
	_test_legacy_style_migration()
	_test_output_discovery()
	_test_endpoint_normalization()
	print("ComfyUI bridge: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_photorealistic_defaults() -> void:
	var bridge: NeuralStyleBridge = COMFYUI_BRIDGE.new()
	_expect("default checkpoint is discovered instead of assuming legacy SD 1.5", bridge.checkpoint_name.is_empty())
	var source: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	source.set_pixel(0, 0, Color(0.2, 0.5, 0.8, 1.0))
	var fallback: Image = bridge.apply_style(source)
	_expect("local fallback preserves source colors instead of faking a style", fallback.get_pixel(0, 0).is_equal_approx(source.get_pixel(0, 0)))
	bridge.checkpoint_name = "JuggernautXL-test.safetensors"
	var workflow: Dictionary = bridge.build_img2img_workflow("tree.png", "mature oak tree", 1234)
	var prompt: Dictionary = workflow.get("prompt", {})
	var positive_prompt: String = str(prompt["5"]["inputs"]["text"])
	var negative_prompt: String = str(prompt["6"]["inputs"]["text"])
	_expect("photorealistic generation is the default", positive_prompt.contains("photorealistic"))
	_expect("stylized drawing is rejected by default", negative_prompt.contains("cartoon") and negative_prompt.contains("childlike drawing"))
	_expect("synthetic splat colors are rejected by default", negative_prompt.contains("neon colors") and negative_prompt.contains("cyan color cast"))
	_expect("natural colors are requested by default", positive_prompt.contains("true-to-life natural colors"))
	_expect("default generation preserves high-resolution detail", bridge.output_resolution == Vector2i(1024, 1024))
	_expect("default sampling uses the photorealistic model profile", prompt["3"]["inputs"]["steps"] == 50 and prompt["3"]["inputs"]["sampler_name"] == "dpmpp_2m" and prompt["3"]["inputs"]["scheduler"] == "karras")
	_expect("default Img2Img strength rebuilds low-detail splat previews", is_equal_approx(prompt["3"]["inputs"]["denoise"], 0.85))
	_expect("photorealistic outputs use a neutral filename", prompt["9"]["inputs"]["filename_prefix"] == "FoveaPhotorealistic")
	var renderer: FoveaCoreSplatRenderer = CORE_SPLAT_RENDERER.new()
	_expect("desktop renderer keeps gaze compression opt-in", not renderer.enable_foveated_rendering)
	renderer.free()
	var manager_source: String = FileAccess.get_file_as_string(CORE_MANAGER_PATH)
	_expect("explicit desktop mode disables manager foveation", manager_source.contains("if not vr_enabled:\n\t\tfoveated_enabled = false"))


func _test_checkpoint_preflight() -> void:
	var bridge: NeuralStyleBridge = COMFYUI_BRIDGE.new()
	var object_info: Dictionary = {
		"CheckpointLoaderSimple": {
			"input": {
				"required": {
					"ckpt_name": [[
						"anime_mix.safetensors",
						"RealVisXL_V5.safetensors",
						"Juggernaut-XL_v9.safetensors"
					], {}]
				}
			}
		}
	}
	var available: PackedStringArray = bridge.extract_available_checkpoints(object_info)
	_expect("checkpoint metadata is extracted from ComfyUI object_info", available.size() == 3)
	_expect("auto-selection prefers the highest-priority photorealistic family", bridge.select_photorealistic_checkpoint(available) == "Juggernaut-XL_v9.safetensors")
	_expect("anime-only checkpoint lists fail closed", bridge.select_photorealistic_checkpoint(PackedStringArray(["anime_mix.safetensors"])) == "")
	bridge.checkpoint_name = "realvisxl_v5.safetensors"
	_expect("explicit installed checkpoint override is case-insensitive", bridge.select_photorealistic_checkpoint(available) == "RealVisXL_V5.safetensors")
	bridge.checkpoint_name = "missing.safetensors"
	_expect("missing explicit checkpoint override fails closed", bridge.select_photorealistic_checkpoint(available) == "")
	bridge.comfyui_url = "http://127.0.0.1:8188/"
	bridge.comfyui_fallback_urls = PackedStringArray(["http://127.0.0.1:8000", "http://127.0.0.1:8188"])
	var endpoints: Array[String] = bridge.get_comfyui_endpoint_candidates()
	_expect("ComfyUI Desktop port is an automatic fallback", endpoints == ["http://127.0.0.1:8188", "http://127.0.0.1:8000"])


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


func _test_legacy_style_migration() -> void:
	var session: ReconstructionSession = RECONSTRUCTION_SESSION.new()
	_expect("new reconstruction sessions default to photorealistic", session.visual_style == "Photorealistic")
	_expect("photorealistic sessions preserve full splat density", session.splat_shape == "Triangle" and is_equal_approx(session.splat_count_density, 1.0))
	_expect("photorealistic capture samples more source frames", session.extraction_fps == 4)
	_expect("photorealistic training uses the full quality schedule", session.training_iterations == 30000)
	_expect("photorealistic sessions avoid artistic color tagging", not session.auto_tag_color)
	_expect("training output path follows the configured iteration count", session.get_training_point_cloud_path().contains("iteration_30000"))
	var backend: ReconstructionBackend = RECONSTRUCTION_BACKEND.new()
	_expect("official gsplat bridge is the default training backend", backend.gaussiantrain_script == "gsplat_bridge.py")
	var training_args: Array = backend.build_gaussian_training_args(session)
	_expect("training resolves the bundled gsplat bridge", str(training_args[0]).ends_with("gsplat_bridge.py"))
	var reconstruction_manager_source: String = FileAccess.get_file_as_string(RECONSTRUCTION_MANAGER_PATH)
	_expect(
		"legacy train.py user settings migrate to the gsplat bridge",
		reconstruction_manager_source.contains("configured_training_script == LEGACY_GAUSSIAN_TRAIN_SCRIPT")
	)
	var iterations_index: int = training_args.find("--iterations")
	_expect("3DGS command receives the configured quality schedule", iterations_index >= 0 and training_args[iterations_index + 1] == "30000")
	backend.free()
	_expect("photorealistic sessions disable stylized motion", not session.enable_wind and is_zero_approx(session.wind_strength))
	session.from_dict({"visual_style": "Realistic"})
	_expect("legacy realistic sessions migrate to photorealistic", session.visual_style == "Photorealistic")
	_expect("legacy sessions retain their historical training path", session.training_iterations == 7000)


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
