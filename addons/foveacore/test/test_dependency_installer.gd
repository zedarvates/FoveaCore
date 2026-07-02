extends SceneTree
## Unit tests for FoveaDependencyInstaller & Path Resolution (Phase 1, F2-F4).
## Structural and local extraction testing using ZIPPacker and tar extraction.

const DepMgr := preload("res://addons/foveacore/scripts/reconstruction/fovea_dependency_manager.gd")
const DepInstaller := preload("res://addons/foveacore/scripts/reconstruction/fovea_dependency_installer.gd")

var _passed := 0
var _failed := 0
var _installer: Node = null

func _init() -> void:
	print("\n" + "=".repeat(70))
	print("FoveaDependencyInstaller Unit & Extraction Tests")
	print("=".repeat(70))
	
	# Wait a brief moment
	await create_timer(0.1).timeout
	_run_tests()

func _run_tests() -> void:
	# 1. Instantiate installer
	_installer = DepInstaller.new()
	root.add_child(_installer)
	_assert("Installer instantiated", _installer != null, "")
	
	# 2. Test ZIPPacker and Async Extraction / Flattening
	var test_zip := "user://test_archive.zip"
	var err := _create_mock_zip(test_zip)
	_assert("Created mock ZIP file", err == OK, "Error: %d" % err)
	
	if err == OK:
		# We hook into the installer signals to check completion
		_installer.install_completed.connect(_on_test_install_completed.bind(test_zip))
		_installer.install_failed.connect(_on_test_install_failed.bind(test_zip))
		
		# Trigger the async extraction on our mock zip as if it was ffmpeg
		print("Starting extraction of mock ZIP...")
		_installer._async_extract(test_zip, "test_ffmpeg")
	else:
		_finish()

func _create_mock_zip(path: String) -> int:
	var packer := ZIPPacker.new()
	var err := packer.open(path)
	if err != OK:
		return err
	
	# Write a nested file to test flattening component stripping
	var bin_name := "ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"
	err = packer.start_file("ffmpeg-v1.0-essentials/" + bin_name)
	if err != OK:
		packer.close()
		return err
	
	packer.write_file("Mock ffmpeg binary".to_utf8_buffer())
	packer.close_file()
	
	packer.close()
	return OK

func _on_test_install_completed(tool_name: String, zip_path: String) -> void:
	_assert("Install completed signal received", tool_name == "test_ffmpeg", tool_name)
	
	# Verify that the nested structure was successfully flattened
	var bin_name := "ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"
	var target_file := "user://fovea_tools/test_ffmpeg/".path_join(bin_name)
	var exists := FileAccess.file_exists(target_file)
	_assert("Nested archive contents were extracted and flattened", exists, target_file)
	
	if exists:
		var fa := FileAccess.open(target_file, FileAccess.READ)
		var content := fa.get_as_text()
		_assert("Content matches mock content", content == "Mock ffmpeg binary", content)
		fa.close()
		
	# Create a dummy local binary for ffmpeg to test resolution
	var local_ffmpeg_dir := "user://fovea_tools/ffmpeg"
	DirAccess.make_dir_recursive_absolute(local_ffmpeg_dir)
	var ext := ".exe" if OS.get_name() == "Windows" else ""
	var dummy_bin := local_ffmpeg_dir + "/ffmpeg" + ext
	var f_dummy := FileAccess.open(dummy_bin, FileAccess.WRITE)
	if f_dummy:
		f_dummy.store_string("dummy")
		f_dummy.close()

	# Clear setting temporarily to let local resolution happen
	var old_setting = ""
	if ProjectSettings.has_setting("fovea/tools/ffmpeg_path"):
		old_setting = ProjectSettings.get_setting("fovea/tools/ffmpeg_path")
		ProjectSettings.set_setting("fovea/tools/ffmpeg_path", "")

	# Verify path resolution routes to local install
	var resolved := DepMgr.resolve("ffmpeg")
	var is_local := "user://fovea_tools" in resolved or "fovea_tools" in resolved
	_assert("FoveaDependencyManager resolves to local path", is_local, resolved)
	
	# Restore setting and cleanup
	if old_setting != "":
		ProjectSettings.set_setting("fovea/tools/ffmpeg_path", old_setting)
	_installer._delete_file(dummy_bin)
	_installer._delete_dir_recursive(local_ffmpeg_dir)
	_installer._delete_file(zip_path)
	_installer._delete_dir_recursive("user://fovea_tools/test_ffmpeg")
	
	_finish()

func _on_test_install_failed(tool_name: String, error_msg: String, zip_path: String) -> void:
	_assert("Install completed successfully (failed instead)", false, "%s failed: %s" % [tool_name, error_msg])
	_installer._delete_file(zip_path)
	_finish()

func _assert(name: String, cond: bool, detail: String) -> void:
	if cond:
		_passed += 1
		print("  ✓ %s %s" % [name, "— " + detail if detail != "" else ""])
	else:
		_failed += 1
		print("  ✗ %s %s" % [name, "— " + detail if detail != "" else ""])

func _finish() -> void:
	if _installer:
		_installer.queue_free()
		
	print("\n" + "=".repeat(70))
	print("FoveaDependencyInstaller Tests: %d passed, %d failed" % [_passed, _failed])
	print("=".repeat(70))
	quit(1 if _failed > 0 else 0)
