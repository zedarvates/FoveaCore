extends Node
class_name FoveaDependencyInstaller

## FoveaDependencyInstaller — Automates downloading and installing tools (Phase 1, F2/F3).
## Uses Godot's HTTPRequest for downloads and the OS native 'tar' for extraction.

const DepMgr: GDScript = preload("res://addons/foveacore/scripts/reconstruction/fovea_dependency_manager.gd")

signal progress_updated(tool_name: String, stage: String, pct: float, status_text: String)
signal install_completed(tool_name: String)
signal install_failed(tool_name: String, error_msg: String)

const TOOLS_DIR: String = "user://fovea_tools"
const TEMP_DIR: String = "user://fovea_tools/temp"

var _active_http_request: HTTPRequest = null
var _active_tool: String = ""
## Background extraction/pip thread. Kept in a member so it can be joined
## (a Thread that goes out of scope without wait_to_finish() leaks / errors).
var _extract_thread: Thread = null

func _ready() -> void:
	# Ensure directory structure exists
	DirAccess.make_dir_recursive_absolute(TOOLS_DIR)
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)

func start_install(tool_name: String) -> void:
	if _active_tool != "":
		push_error("FoveaDependencyInstaller: An installation is already active.")
		install_failed.emit(tool_name, "Another installation is already in progress.")
		return

	if not DepMgr.TOOLS.has(tool_name):
		push_error("FoveaDependencyInstaller: Tool '%s' not registered." % tool_name)
		install_failed.emit(tool_name, "Tool '%s' not registered in registry." % tool_name)
		return

	var url: String = DepMgr.download_url(tool_name)
	if url.is_empty():
		install_failed.emit(tool_name, "Download URL not available for current platform: %s" % OS.get_name())
		return

	_active_tool = tool_name
	
	# Determine temporary file path
	var ext: String = ".zip" if url.ends_with(".zip") else ".tar.gz"
	if url.ends_with(".tar.xz"):
		ext = ".tar.xz"
	var temp_file: String = TEMP_DIR.path_join(tool_name + ext)
	
	# Create and configure HTTPRequest
	_active_http_request = HTTPRequest.new()
	_active_http_request.use_threads = true
	_active_http_request.download_file = ProjectSettings.globalize_path(temp_file)
	_active_http_request.request_completed.connect(_on_download_completed.bind(temp_file))
	add_child(_active_http_request)
	
	print("FoveaDependencyInstaller: Starting download of '%s' from: %s" % [tool_name, url])
	var err: Error = _active_http_request.request(url)
	if err != OK:
		_free_request()
		_active_tool = ""
		install_failed.emit(tool_name, "Failed to start HTTP request (error code %d)." % err)

func _process(_delta: float) -> void:
	if _active_http_request and _active_tool != "":
		var downloaded: int = _active_http_request.get_downloaded_bytes()
		var total: int = _active_http_request.get_body_size()
		if total > 0:
			var pct: float = float(downloaded) / float(total) * 100.0
			var speed_str: String = "%s / %s" % [_format_bytes(downloaded), _format_bytes(total)]
			progress_updated.emit(_active_tool, "Downloading", pct, "Downloading... %s (%.1f%%)" % [speed_str, pct])

func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, temp_file_path: String) -> void:
	var tool_name: String = _active_tool
	# Free only the HTTPRequest here; _active_tool stays set so the "already
	# installing" guard remains effective through the extract/pip phase (#4).
	_free_request()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_delete_file(temp_file_path)
		_active_tool = ""
		install_failed.emit(tool_name, "Download failed (HTTP result: %d, response code: %d)." % [result, response_code])
		return

	progress_updated.emit(tool_name, "Extracting", 100.0, "Extracting archive...")

	# Run extraction in a background thread to prevent editor freeze.
	# Stored in a member so it can be joined (#3).
	_extract_thread = Thread.new()
	_extract_thread.start(Callable(self, "_async_extract").bind(temp_file_path, tool_name))

func _async_extract(temp_file_path: String, tool_name: String) -> void:
	var temp_extract_dir: String = TEMP_DIR.path_join(tool_name + "_extracted")
	DirAccess.make_dir_recursive_absolute(temp_extract_dir)

	var global_archive: String = ProjectSettings.globalize_path(temp_file_path)
	var global_dest: String = ProjectSettings.globalize_path(temp_extract_dir)

	var output: Array = []
	print("FoveaDependencyInstaller: Extracting '%s' using tar..." % tool_name)
	var code: int = OS.execute("tar", ["-xf", global_archive, "-C", global_dest], output, true, false)
	
	_delete_file(temp_file_path)

	if code != 0:
		_delete_dir_recursive(temp_extract_dir)
		install_failed.emit.call_deferred(tool_name, "Extraction failed (tar exited with code %d)." % code)
		_reset.call_deferred()
		return

	# Flatten directory structure if archive contained a single nested parent directory
	var final_dest_dir: String = TOOLS_DIR.path_join(tool_name)
	_delete_dir_recursive(final_dest_dir) # Ensure clean slate
	DirAccess.make_dir_recursive_absolute(final_dest_dir)

	var dir: DirAccess = DirAccess.open(temp_extract_dir)
	if dir:
		dir.list_dir_begin()
		var items: Array[String] = []
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				items.append(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

		# If there is exactly one folder inside, use its contents instead
		var source_dir: String = temp_extract_dir
		if items.size() == 1 and dir.change_dir(items[0]) == OK:
			source_dir = temp_extract_dir.path_join(items[0])

		_move_dir_contents(source_dir, final_dest_dir)
		_delete_dir_recursive(temp_extract_dir)

	# Post-installation phase
	if tool_name == "python":
		_async_python_post_install(final_dest_dir)
	else:
		install_completed.emit.call_deferred(tool_name)
		_reset.call_deferred()

func _async_python_post_install(python_dir: String) -> void:
	progress_updated.emit.call_deferred("python", "Post-Install", 0.0, "Initializing Python environment (pip)...")
	
	var python_exe: String = python_dir.path_join("python.exe" if OS.get_name() == "Windows" else "bin/python")
	python_exe = ProjectSettings.globalize_path(python_exe)

	if not FileAccess.file_exists(python_exe):
		install_failed.emit.call_deferred("python", "Python executable not found at: %s" % python_exe)
		_reset.call_deferred()
		return

	# Detect NVIDIA GPU
	var has_nvidia: bool = false
	var adapter_name: String = RenderingServer.get_video_adapter_name().to_lower()
	if "nvidia" in adapter_name or "geforce" in adapter_name or "quadro" in adapter_name or "rtx" in adapter_name:
		has_nvidia = true

	# 1. Upgrade pip
	progress_updated.emit.call_deferred("python", "Post-Install", 10.0, "Upgrading pip...")
	var code: int = OS.execute(python_exe, ["-m", "pip", "install", "--upgrade", "pip"], [], true)
	if code != 0:
		push_warning("FoveaDependencyInstaller: pip upgrade returned non-zero code %d" % code)

	# 2. Install PyTorch & torchvision
	var torch_args: Array[String] = ["-m", "pip", "install", "torch==2.4.0", "torchvision==0.19.0"]
	if has_nvidia:
		progress_updated.emit.call_deferred("python", "Post-Install", 25.0, "Installing PyTorch with CUDA 12.4 support (takes a few minutes)...")
		torch_args.append_array(["--index-url", "https://download.pytorch.org/whl/cu124"])
	else:
		progress_updated.emit.call_deferred("python", "Post-Install", 25.0, "Installing PyTorch CPU version (takes a few minutes)...")
		torch_args.append_array(["--index-url", "https://download.pytorch.org/whl/cpu"])

	code = OS.execute(python_exe, torch_args, [], true)
	if code != 0:
		install_failed.emit.call_deferred("python", "Failed to install PyTorch (pip exited with code %d)." % code)
		_reset.call_deferred()
		return

	# 3. Install remaining pipeline dependencies
	progress_updated.emit.call_deferred("python", "Post-Install", 75.0, "Installing DiffSynth and auxiliary packages...")
	var auxiliary_args: Array[String] = [
		"-m", "pip", "install", 
		"diffsynth", "sentencepiece", "transformers", 
		"fastapi", "uvicorn", "numpy", "trimesh"
	]
	code = OS.execute(python_exe, auxiliary_args, [], true)
	if code != 0:
		install_failed.emit.call_deferred("python", "Failed to install auxiliary packages (pip exited with code %d)." % code)
		_reset.call_deferred()
		return

	install_completed.emit.call_deferred("python")
	_reset.call_deferred()

## Frees the HTTPRequest only (does not clear the install-in-progress flag).
func _free_request() -> void:
	if _active_http_request:
		_active_http_request.queue_free()
		_active_http_request = null

## Terminal cleanup: clears the install flag and joins the worker thread.
## Always called via call_deferred() from the worker so it runs on the main
## thread after the worker has returned (wait_to_finish then returns at once).
func _reset() -> void:
	_active_tool = ""
	if _extract_thread != null and _extract_thread.is_started():
		_extract_thread.wait_to_finish()
	_extract_thread = null

func _exit_tree() -> void:
	# Don't leave a worker thread dangling if the editor/plugin shuts down.
	if _extract_thread != null and _extract_thread.is_started():
		_extract_thread.wait_to_finish()
		_extract_thread = null

func _format_bytes(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	elif bytes < 1024 * 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	else:
		return "%.1f MB" % (float(bytes) / (1024.0 * 1024.0))

func _delete_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _move_dir_contents(src_dir: String, dest_dir: String) -> void:
	var dir: DirAccess = DirAccess.open(src_dir)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var src_path: String = src_dir.path_join(file_name)
				var dest_path: String = dest_dir.path_join(file_name)
				if dir.current_is_dir():
					DirAccess.make_dir_recursive_absolute(dest_path)
					_move_dir_contents(src_path, dest_path)
				else:
					dir.copy(src_path, dest_path)
			file_name = dir.get_next()
		dir.list_dir_end()

func _delete_dir_recursive(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var path: String = dir_path.path_join(file_name)
				if dir.current_is_dir():
					_delete_dir_recursive(path)
				else:
					dir.remove(path)
			file_name = dir.get_next()
		dir.list_dir_end()
		dir.remove(dir_path)
