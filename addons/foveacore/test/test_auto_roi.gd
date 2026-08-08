extends SceneTree

## Unit test for Auto-ROI detection (AI/heuristics)
## Validates: Python script execution, output JSON parsing, bounding box accuracy

var _passed := 0
var _failed := 0

func _init() -> void:
	print("\n==============================================================")
	print("Auto-ROI AI Detection Unit Tests")
	print("==============================================================")
	
	await create_timer(0.2).timeout
	_run_tests()

func _run_tests() -> void:
	# 1. Create a temporary image with a defined foreground object in the center
	# Image size: 200x200, background: white, foreground: red square at (50, 50) of size 100x100
	var test_image: Image = Image.create(200, 200, false, Image.FORMAT_RGB8)
	test_image.fill(Color.WHITE)
	
	# Draw a red square in the center
	for y in range(50, 150):
		for x in range(50, 150):
			test_image.set_pixel(x, y, Color.RED)
			
	var temp_img_path: String = OS.get_user_data_dir() + "/test_auto_roi_input.png"
	var err: Error = test_image.save_png(temp_img_path)
	_assert("Temporary test image saved", err == OK)
	
	if err != OK:
		_finish()
		return
		
	# 2. Run the auto_roi.py script using Python
	var python_bin: String = "python"
	
	# Attempt to load path from settings if available
	var config_path = OS.get_user_data_dir() + "/../FoveaEngine/fovea_engine_user_settings.cfg"
	var config = ConfigFile.new()
	if config.load(config_path) == OK:
		python_bin = config.get_value("tools", "python_path", "python")
		
	var script_path: String = ProjectSettings.globalize_path("res://tools/auto_roi.py")
	var args: Array[String] = [script_path, "--input", ProjectSettings.globalize_path(temp_img_path)]
	
	print("Running: ", python_bin, " ", " ".join(args))
	var output: Array = []
	var exit_code: int = OS.execute(python_bin, args, output, true)
	
	_assert("Python process exited successfully (0)", exit_code == 0)
	
	if exit_code == 0:
		_assert("Process output is not empty", not output.is_empty())
		if not output.is_empty():
			print("Script Output: ", output[0])
			var json := JSON.new()
			var raw_output: String = output[0]
			var start_idx = raw_output.find("{")
			var end_idx = raw_output.rfind("}")
			var json_str = raw_output
			if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
				json_str = raw_output.substr(start_idx, end_idx - start_idx + 1)
			var parse_err: Error = json.parse(json_str)
			_assert("Output parsed as valid JSON", parse_err == OK)
			
			if parse_err == OK:
				var data: Dictionary = json.data
				_assert("JSON contains x", data.has("x"))
				_assert("JSON contains y", data.has("y"))
				_assert("JSON contains width", data.has("width"))
				_assert("JSON contains height", data.has("height"))
				
				if data.has("x") and data.has("y") and data.has("width") and data.has("height"):
					var rx: int = int(data["x"])
					var ry: int = int(data["y"])
					var rw: int = int(data["width"])
					var rh: int = int(data["height"])
					
					var expected_padding: int = 10 if str(data.get("method", "")).begins_with("pil") else 15
					var expected_origin: int = 50 - expected_padding
					var expected_size: int = 99 + expected_padding * 2
					_assert("Detected X includes method padding", abs(rx - expected_origin) <= 5, "Got %d" % rx)
					_assert("Detected Y includes method padding", abs(ry - expected_origin) <= 5, "Got %d" % ry)
					_assert("Detected width includes method padding", abs(rw - expected_size) <= 4, "Got %d" % rw)
					_assert("Detected height includes method padding", abs(rh - expected_size) <= 4, "Got %d" % rh)
	
	# Cleanup
	if FileAccess.file_exists(temp_img_path):
		DirAccess.remove_absolute(temp_img_path)
		
	_finish()

func _finish() -> void:
	print("\n==============================================================")
	print("Auto-ROI Tests: %d passed, %d failed (%.0f%%)" % [
		_passed, _failed,
		_passed / float(max(_passed + _failed, 1)) * 100.0
	])
	print("==============================================================")
	quit(1 if _failed > 0 else 0)

func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  ✓ %s" % name)
	else:
		_failed += 1
		if detail.is_empty():
			print("  ✗ %s" % name)
		else:
			print("  ✗ %s — %s" % [name, detail])
