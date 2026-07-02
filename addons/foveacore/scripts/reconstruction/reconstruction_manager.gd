extends Node
class_name FoveaReconstructionManager

## ReconstructionManager — Coordinates reconstruction sessions
## Interaces with externally compiled tools for SfM and 3DGS-Training

const DepMgr := preload("res://addons/foveacore/scripts/reconstruction/fovea_dependency_manager.gd")

## Emitted when a new reconstruction session begins.
## [param name] represents the unique name/identifier of the started [ReconstructionSession].
signal session_started(name: String)

## Emitted when the progress of the currently active session is updated.
## [param progress] is a floating-point value ranging from [code]0.0[/code] (started) to [code]100.0[/code] (completed).
## This covers Phase 1 (0% to 33%), Phase 2 (33% to 66%), and Phase 3 (66% to 100%).
signal session_progress_updated(progress: float)

## Emitted when the active reconstruction session completes successfully.
## [param result] provides the final [ReconstructionSession] containing all generated asset paths, metrics, and metadata.
signal session_completed(result: ReconstructionSession)

## Emitted when the active reconstruction session fails due to an error.
## [param reason] contains a human-readable description of what caused the failure (e.g., missing dependencies, blur filter threshold issues, OOM, etc.).
signal reconstruction_failed(reason: String)

## Emitted when a new line of text output is received from the stdout/stderr stream of an external CLI tool
## (such as FFmpeg, COLMAP, or Python 3DGS training scripts).
## [param line] is the raw text string parsed from the process output.
signal log_line_received(line: String)

## Emitted when the reconstruction pipeline transitions between active and idle states.
## [param is_active] is [code]true[/code] if there are running tasks, and [code]false[/code] when the manager becomes idle.
signal pipeline_state_changed(is_active: bool)

var is_active: bool = false:
	set(val):
		if is_active != val:
			is_active = val
			pipeline_state_changed.emit(is_active)

var _active_tasks: int = 0
var _current_phase: int = 1

func _start_task() -> void:
	_active_tasks += 1
	if _active_tasks == 1:
		is_active = true

func _end_task() -> void:
	_active_tasks = max(0, _active_tasks - 1)
	if _active_tasks == 0:
		is_active = false


@export var processor: StudioProcessor = null
@export var exporter: DatasetExporter = null
# Déclaré sans @export pour éviter référence circulaire, créé dynamiquement dans _ready()
var backend: ReconstructionBackend = null

## Chemins des outils externes
var ffmpeg_path: String = "ffmpeg":
	set(val):
		ffmpeg_path = val
		_propagate_ffmpeg_path()
		_save_user_settings()

var colmap_path: String = "colmap":
	set(val):
		colmap_path = val
		_propagate_colmap_path()
		_save_user_settings()

var python_path: String = "python":
	set(val):
		python_path = val
		_propagate_python_path()
		_save_user_settings()

var gaussian_train_script: String = "train.py":
	set(val):
		gaussian_train_script = val
		_propagate_gaussian_train_script()
		_save_user_settings()

var star_bridge_script: String = "star_bridge.py":
	set(val):
		star_bridge_script = val
		_propagate_star_bridge_script()
		_save_user_settings()

var worldmirror_bridge_script: String = "worldmirror_bridge.py":
	set(val):
		worldmirror_bridge_script = val
		_propagate_worldmirror_bridge_script()
		_save_user_settings()

var triposplat_bridge_script: String = "triposplat_bridge.py":
	set(val):
		triposplat_bridge_script = val
		_propagate_triposplat_bridge_script()
		_save_user_settings()

var artifixer_bridge_script: String = "artifixer_bridge.py":
	set(val):
		artifixer_bridge_script = val
		_propagate_artifixer_bridge_script()
		_save_user_settings()


func _propagate_ffmpeg_path() -> void:
	if processor: processor.ffmpeg_path = ffmpeg_path
	ProjectSettings.set_setting("fovea/tools/ffmpeg_path", ffmpeg_path)

func _propagate_colmap_path() -> void:
	if backend: backend.colmap_path = colmap_path
	ProjectSettings.set_setting("fovea/tools/colmap_path", colmap_path)

func _propagate_python_path() -> void:
	if backend: backend.python_path = python_path
	ProjectSettings.set_setting("fovea/tools/python_path", python_path)

func _propagate_gaussian_train_script() -> void:
	if backend: backend.gaussiantrain_script = gaussian_train_script
	ProjectSettings.set_setting("fovea/tools/gaussian_train_script", gaussian_train_script)

func _propagate_star_bridge_script() -> void:
	if backend: backend.star_bridge_script = star_bridge_script
	ProjectSettings.set_setting("fovea/tools/star_bridge_script", star_bridge_script)

func _propagate_worldmirror_bridge_script() -> void:
	if backend: backend.worldmirror_bridge_script = worldmirror_bridge_script
	ProjectSettings.set_setting("fovea/tools/worldmirror_bridge_script", worldmirror_bridge_script)

func _propagate_triposplat_bridge_script() -> void:
	if backend: backend.triposplat_bridge_script = triposplat_bridge_script
	ProjectSettings.set_setting("fovea/tools/triposplat_bridge_script", triposplat_bridge_script)

func _propagate_artifixer_bridge_script() -> void:
	if backend: backend.artifixer_bridge_script = artifixer_bridge_script
	ProjectSettings.set_setting("fovea/tools/artifixer_bridge_script", artifixer_bridge_script)


# Fichier de configuration utilisateur (hors projet)
var _user_config_path: String = ""


@export var metrics: ReconstructionMetrics = null
@export var default_output_dir: String = "res://reconstructions/"
@export var dry_run: bool = false:
	set(val):
		dry_run = val
		if backend: backend.dry_run = dry_run

var active_sessions: Dictionary[String, ReconstructionSession] = {}

func _ready() -> void:
	# Initialiser le chemin de config utilisateur
	_user_config_path = OS.get_user_data_dir() + "/fovea_engine_user_settings.cfg"

	# Charger les settings persistants depuis fichier user
	_load_user_settings()

	# Charger les chemins depuis les paramètres du projet s'ils existent (fallback)
	if ProjectSettings.has_setting("fovea/tools/ffmpeg_path"):
		ffmpeg_path = ProjectSettings.get_setting("fovea/tools/ffmpeg_path")
	if ProjectSettings.has_setting("fovea/tools/colmap_path"):
		colmap_path = ProjectSettings.get_setting("fovea/tools/colmap_path")
	if ProjectSettings.has_setting("fovea/tools/python_path"):
		python_path = ProjectSettings.get_setting("fovea/tools/python_path")
	if ProjectSettings.has_setting("fovea/tools/gaussian_train_script"):
		gaussian_train_script = ProjectSettings.get_setting("fovea/tools/gaussian_train_script")
	if ProjectSettings.has_setting("fovea/tools/star_bridge_script"):
		star_bridge_script = ProjectSettings.get_setting("fovea/tools/star_bridge_script")
	if ProjectSettings.has_setting("fovea/tools/worldmirror_bridge_script"):
		worldmirror_bridge_script = ProjectSettings.get_setting("fovea/tools/worldmirror_bridge_script")
	if ProjectSettings.has_setting("fovea/tools/triposplat_bridge_script"):
		triposplat_bridge_script = ProjectSettings.get_setting("fovea/tools/triposplat_bridge_script")
	if ProjectSettings.has_setting("fovea/tools/artifixer_bridge_script"):
		artifixer_bridge_script = ProjectSettings.get_setting("fovea/tools/artifixer_bridge_script")

	# Prioritize FoveaDependencyManager resolution (local user://fovea_tools/ builds)
	ffmpeg_path = DepMgr.resolve("ffmpeg")
	colmap_path = DepMgr.resolve("colmap")
	python_path = DepMgr.resolve("python")

	if processor == null:
		processor = StudioProcessor.new()
		add_child(processor)
	processor.ffmpeg_path = ffmpeg_path
	processor.error_occurred.connect(func(err: String) -> void: reconstruction_failed.emit(err))

	if exporter == null:
		exporter = DatasetExporter.new()
		add_child(exporter)

	if backend == null:
		backend = ReconstructionBackend.new()
		add_child(backend)
		backend.colmap_path = colmap_path
		backend.python_path = python_path
		backend.gaussiantrain_script = gaussian_train_script
		backend.star_bridge_script = star_bridge_script
		backend.worldmirror_bridge_script = worldmirror_bridge_script
		backend.triposplat_bridge_script = triposplat_bridge_script
		backend.artifixer_bridge_script = artifixer_bridge_script
		backend.dry_run = dry_run
		backend.command_started.connect(_on_backend_started)
		backend.command_progress.connect(_on_backend_progress)
		backend.command_finished.connect(_on_backend_finished)
		backend.error_occurred.connect(func(err: String) -> void: reconstruction_failed.emit(err))
		backend.oom_detected.connect(func(cmd: String, details: String) -> void: reconstruction_failed.emit(details))

	call_deferred("check_tools")

func check_tools() -> Dictionary:
	# Re-resolve paths from FoveaDependencyManager to catch fresh installs
	ffmpeg_path = DepMgr.resolve("ffmpeg")
	colmap_path = DepMgr.resolve("colmap")
	python_path = DepMgr.resolve("python")
	
	if processor:
		processor.ffmpeg_path = ffmpeg_path
	if backend:
		backend.colmap_path = colmap_path
		backend.python_path = python_path

	var results: Dictionary = {
		"ffmpeg": {"found": false, "version": "", "error": ""},
		"colmap": {"found": false, "version": "", "error": ""},
		"python": {"found": false, "version": "", "error": ""}
	}

	# Vérification FFmpeg
	if not _is_tool_available(ffmpeg_path, ["-version"]):
		_auto_detect_ffmpeg()
	var ff_info: Dictionary = _validate_tool_version(ffmpeg_path, "-version")
	results["ffmpeg"] = ff_info
	if not ff_info.found:
		_auto_detect_ffmpeg()
		ff_info = _validate_tool_version(ffmpeg_path, "-version")
		results["ffmpeg"] = ff_info

	# Vérification COLMAP
	if not _is_tool_available(colmap_path, ["--help"]):
		_auto_detect_colmap()
	var cm_info: Dictionary = _validate_tool_version(colmap_path, "--help")
	results["colmap"] = cm_info
	if not cm_info.found:
		_auto_detect_colmap()
		cm_info = _validate_tool_version(colmap_path, "--help")
		results["colmap"] = cm_info

	# Vérification Python
	if not _is_tool_available(python_path, ["--version"]):
		_auto_detect_python()
	var py_info: Dictionary = _validate_tool_version(python_path, "--version")
	results["python"] = py_info
	if not py_info.found:
		_auto_detect_python()
		py_info = _validate_tool_version(python_path, "--version")
		results["python"] = py_info

	# Logging
	if results["ffmpeg"].found:
		print("FoveaManager: FFmpeg OK - ", results["ffmpeg"].version.split("\n")[0])
	else:
		push_warning("FoveaManager: FFmpeg NOT FOUND")

	if results["colmap"].found:
		print("FoveaManager: COLMAP OK")
	else:
		push_warning("FoveaManager: COLMAP NOT FOUND")

	if results["python"].found:
		print("FoveaManager: Python OK - ", results["python"].version.split("\n")[0])
	else:
		push_warning("FoveaManager: Python NOT FOUND")

	return results

func _is_tool_available(path: String, args: Array[String]) -> bool:
	var out: Array[String] = []
	var err: int = OS.execute(path, args, out)
	return err == 0

func _validate_tool_version(path: String, version_arg: String, _min_version: String = "") -> Dictionary:
	"""Vérifie la version d'un outil. Retourne {found: bool, version: str, error: str}."""
	var out: Array[String] = []
	var err: int = OS.execute(path, [version_arg], out)
	if err != 0:
		return {"found": false, "version": "", "error": "Tool not found or failed"}

	if not out.is_empty():
		var version_line: String = out[0].strip_edges()
		# Parse version (simplifié)
		return {"found": true, "version": version_line, "error": ""}

	return {"found": true, "version": "unknown", "error": ""}

func _auto_detect_ffmpeg() -> void:
	var cmd: String = "where" if OS.has_feature("windows") else "which"
	var out: Array[String] = []
	var err: int = OS.execute(cmd, ["ffmpeg"], out)
	if err == 0 and not out.is_empty():
		ffmpeg_path = out[0].strip_edges().split("\n")[0]
		print("FoveaManager: FFmpeg détecté automatiquement via PATH : ", ffmpeg_path)
		return
		
	# Fallback sur chemins communs si non dans PATH
	var home_path: String = OS.get_environment("HOME") if OS.has_feature("unix") else OS.get_environment("USERPROFILE")
	var is_windows: bool = OS.has_feature("windows")
	var bin_name: String = "ffmpeg.exe" if is_windows else "ffmpeg"
	
	var possible_paths: Array[String] = [
		"C:/ffmpeg/bin/ffmpeg.exe",
		"/usr/bin/ffmpeg",
		"/usr/local/bin/ffmpeg",
	]
	
	if not home_path.is_empty():
		possible_paths.append(home_path + "/Documents/ffmpeg-8.0-win-x64/" + bin_name)
		possible_paths.append(home_path + "/Documents/ffmpeg/bin/" + bin_name)
		possible_paths.append(home_path + "/Documents/ffmpeg-master-latest-win64-gpl-shared/ffmpeg-master-latest-win64-gpl-shared/bin/" + bin_name)
		possible_paths.append(home_path + "/Documents/ffmpeg/bin/" + bin_name)
	
	for p: String in possible_paths:
		if _is_tool_available(p, ["-version"]):
			print("FoveaManager: FFmpeg détecté automatiquement à : ", p)
			ffmpeg_path = p 
			return

func _auto_detect_colmap() -> void:
	var cmd: String = "where" if OS.has_feature("windows") else "which"
	var out: Array[String] = []
	var err: int = OS.execute(cmd, ["colmap"], out)
	if err == 0 and not out.is_empty():
		colmap_path = out[0].strip_edges().split("\n")[0]
		print("FoveaManager: COLMAP détecté automatiquement via PATH : ", colmap_path)
		return

	var home_path: String = OS.get_environment("HOME") if OS.has_feature("unix") else OS.get_environment("USERPROFILE")
	var is_windows: bool = OS.has_feature("windows")
	var bin_name: String = "colmap.exe" if is_windows else "colmap"

	var possible_paths: Array[String] = [
		"colmap",
		"C:/colmap/colmap.exe",
		"/usr/bin/colmap",
		"/usr/local/bin/colmap"
	]

	if not home_path.is_empty():
		possible_paths.append(home_path + "/Documents/colmap-x64-windows-cuda/bin/" + bin_name)
		possible_paths.append(home_path + "/Documents/colmap-x64-windows-cuda/" + bin_name)
		possible_paths.append(home_path + "/Documents/colmap/bin/" + bin_name)
		possible_paths.append(home_path + "/Documents/colmap/" + bin_name)

	for p: String in possible_paths:
		if _is_tool_available(p, ["--help"]):
			print("FoveaManager: COLMAP détecté automatiquement à : ", p)
			colmap_path = p
			return

func _auto_detect_python() -> void:
	var cmd: String = "where" if OS.has_feature("windows") else "which"
	var out: Array[String] = []
	var err: int = OS.execute(cmd, ["python"], out)
	if err == 0 and not out.is_empty():
		python_path = out[0].strip_edges().split("\n")[0]
		print("FoveaManager: Python détecté automatiquement via PATH : ", python_path)
		return

	# Fallback sur chemins communs si non dans PATH
	var possible_paths: Array[String] = [
		"python",
		"/usr/bin/python3",
		"/usr/local/bin/python3"
	]

	for p: String in possible_paths:
		if _is_tool_available(p, ["--version"]):
			print("FoveaManager: Python détecté automatiquement à : ", p)
			python_path = p
			return

# --- Persistence des Settings Utilisateur ---

func _save_user_settings() -> void:
	"""Sauvegarde les chemins outils dans un fichier cfg utilisateur (hors projet)."""
	var config: ConfigFile = ConfigFile.new()
	config.set_value("tools", "ffmpeg_path", ffmpeg_path)
	config.set_value("tools", "colmap_path", colmap_path)
	config.set_value("tools", "python_path", python_path)
	config.set_value("tools", "gaussian_train_script", gaussian_train_script)
	config.set_value("tools", "star_bridge_script", star_bridge_script)
	config.set_value("tools", "worldmirror_bridge_script", worldmirror_bridge_script)
	config.set_value("tools", "triposplat_bridge_script", triposplat_bridge_script)
	config.set_value("tools", "artifixer_bridge_script", artifixer_bridge_script)

	var err: Error = config.save(_user_config_path)
	if err != OK:
		push_error("Failed to save user settings to " + _user_config_path)
	else:
		print("FoveaManager: User settings saved to ", _user_config_path)

func _load_user_settings() -> void:
	"""Charge les chemins outils depuis le fichier cfg utilisateur si existant."""
	if not FileAccess.file_exists(_user_config_path):
		print("FoveaManager: No user settings file found, using defaults.")
		return

	var config: ConfigFile = ConfigFile.new()
	var err: Error = config.load(_user_config_path)
	if err != OK:
		push_error("Failed to load user settings from " + _user_config_path)
		return

	if config.has_section_key("tools", "ffmpeg_path"):
		ffmpeg_path = config.get_value("tools", "ffmpeg_path")
	if config.has_section_key("tools", "colmap_path"):
		colmap_path = config.get_value("tools", "colmap_path")
	if config.has_section_key("tools", "python_path"):
		python_path = config.get_value("tools", "python_path")
	if config.has_section_key("tools", "gaussian_train_script"):
		gaussian_train_script = config.get_value("tools", "gaussian_train_script")
	if config.has_section_key("tools", "star_bridge_script"):
		star_bridge_script = config.get_value("tools", "star_bridge_script")
	if config.has_section_key("tools", "worldmirror_bridge_script"):
		worldmirror_bridge_script = config.get_value("tools", "worldmirror_bridge_script")
	if config.has_section_key("tools", "triposplat_bridge_script"):
		triposplat_bridge_script = config.get_value("tools", "triposplat_bridge_script")
	if config.has_section_key("tools", "artifixer_bridge_script"):
		artifixer_bridge_script = config.get_value("tools", "artifixer_bridge_script")

	print("FoveaManager: User settings loaded from ", _user_config_path)

## Start a reconstruction session
func create_new_session(video_path: String, name: String = "") -> ReconstructionSession:
	var sess_name: String = name if not name.is_empty() else "sess_" + str(Time.get_unix_time_from_system())
	var session: ReconstructionSession = ReconstructionSession.new(sess_name)
	session.video_path = video_path
	session.output_directory = default_output_dir + sess_name
	
	active_sessions[sess_name] = session
	return session

## Save/Load Session
func save_session(session: ReconstructionSession) -> Error:
	var dir: String = ProjectSettings.globalize_path(session.output_directory)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
		
	var path: String = session.output_directory.path_join("session.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Manager: Failed to save session JSON to " + path)
		return ERR_CANT_OPEN
		
	var json_str: String = JSON.stringify(session.to_dict(), "\t")
	file.store_string(json_str)
	file.close()
	print("Manager: Session saved to ", path)
	return OK

func load_session(path: String) -> ReconstructionSession:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var json_str: String = file.get_as_text()
	file.close()
	
	var json: JSON = JSON.new()
	var err: Error = json.parse(json_str)
	if err != OK:
		push_error("Manager: Failed to parse session JSON from " + path)
		return null
		
	var dict: Variant = json.get_data()
	if not (dict is Dictionary):
		return null
		
	var session: ReconstructionSession = ReconstructionSession.new(dict.get("session_name", "session"))
	session.from_dict(dict)
	active_sessions[session.session_name] = session
	print("Manager: Session loaded: ", session.session_name)
	return session

## Delete active session and optional files on disk
func delete_session(session: ReconstructionSession, delete_disk_files: bool = false) -> void:
	if session == null:
		return
	
	if active_sessions.has(session.session_name):
		active_sessions.erase(session.session_name)
		print("Manager: Erased active session: ", session.session_name)
		
	if delete_disk_files:
		var global_dir: String = ProjectSettings.globalize_path(session.output_directory)
		if DirAccess.dir_exists_absolute(global_dir):
			print("Manager: Deleting session directory recursively: ", global_dir)
			_delete_dir_recursive(global_dir)
		else:
			print("Manager: Session directory does not exist: ", global_dir)

func _delete_dir_recursive(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path: String = path.path_join(file_name)
				if dir.current_is_dir():
					_delete_dir_recursive(full_path)
				else:
					DirAccess.remove_absolute(full_path)
			file_name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(path)


## Step 1: Extraction & Masking
func run_extraction(session: ReconstructionSession, mask_mode: String = "Studio White") -> void:
	_current_phase = 1
	_start_task()
	session_started.emit(session.session_name)
	session.status = "Extracting Frames"
	
	# Prepare workspace
	exporter.prepare_workspace(session)
	metrics = ReconstructionMetrics.new()
	
	# Connecter le masquage automatique pendant l'extraction (utilisation d'un tableau pour le passage par référence dans la closure)
	var exported_count: Array[int] = [0]
	var masking_func: Callable = func(idx: int, img: Image) -> void: 
		var blur: float = processor.calculate_blur_score(img) if not session.dry_run else 1.0
		var effective_mode: String = "None" if mask_mode == "Temporal Variance" else mask_mode
		var mask: Image = processor.mask_background(img, effective_mode, session.background_threshold, session.roi_rect)
		var coverage: float = _calculate_mask_coverage(mask)
		
		# Calculer luminosité et variance de couleur
		var color_metrics: Dictionary = processor.calculate_brightness_and_variance(img) if not session.dry_run else {"brightness": 0.5, "variance": 0.25}
		metrics.add_frame_metrics(idx, blur, coverage, color_metrics.brightness, color_metrics.variance)
		
		if blur < session.blur_threshold:
			print("ReconstructionManager: Frame %d skipped due to high blur (score: %.3f < threshold: %.3f)" % [idx, blur, session.blur_threshold])
		else:
			exporter.export_frame(session, idx, img, mask)
			exported_count[0] += 1
			
		# Update progress bar incrementally (0 to 33%)
		if session.frame_count > 0:
			session_progress_updated.emit((float(idx) / float(session.frame_count)) * 33.0)
	
	processor.frame_extracted.connect(masking_func)
	
	# Lancer l'extraction réelle
	await processor.extract_frames(session)
	
	# Nettoyage
	processor.frame_extracted.disconnect(masking_func)
	session.frame_count = exported_count[0]
	exporter.create_metadata_json(session)
	
	if mask_mode == "Temporal Variance":
		session.status = "Generating Temporal Masks"
		print("ReconstructionManager: Generating Temporal Variance masks via python...")
		var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
		var input_dir: String = abs_path + "/input"
		var masks_dir: String = abs_path + "/masks"
		var py_script: String = ProjectSettings.globalize_path("res://addons/foveacore/scripts/reconstruction/generate_variance_masks.py")
		var args: Array[String] = [py_script, "--input", input_dir, "--output", masks_dir]
		var out: Array[String] = []
		var exit_code: int = OS.execute(python_path, args, out)
		if exit_code != 0:
			push_error("ReconstructionManager: Temporal variance mask generation failed: " + str(out))
		else:
			print("ReconstructionManager: Temporal variance mask generation finished successfully.")
	
	session.status = "Pre-processed"
	print(metrics.get_quality_report())
	session_progress_updated.emit(33.0)
	_end_task()

func _calculate_mask_coverage(mask: Image) -> float:
	# Estimate surface covered by non-transparent pixels
	var transparent_pixels: int = 0
	var size: Vector2i = mask.get_size()
	# Sample every 10th pixel for performance
	for y: int in range(0, size.y, 10):
		for x: int in range(0, size.x, 10):
			if mask.get_pixel(x, y).a < 0.1:
				transparent_pixels += 1
	
	var total_sampled: int = (size.x/10) * (size.y/10)
	if total_sampled <= 0:
		return 0.0
	return 1.0 - (float(transparent_pixels) / float(total_sampled))


## Lancer le pipeline complet en séquence (Phase 1 + 2 + 3)
func run_reconstruction(session: ReconstructionSession) -> void:
	if session == null:
		push_error("ReconstructionManager: session est null")
		return

	_start_task()
	session_started.emit(session.session_name)
	print("ReconstructionManager: Démarrage du pipeline complet pour '", session.session_name, "'")
	
	# Clean up previous COLMAP cache files
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
	var db_file: String = abs_path.path_join("database.db")
	if FileAccess.file_exists(db_file):
		DirAccess.remove_absolute(db_file)
		print("ReconstructionManager: Cleaned up old database.db cache")
	var sparse_dir: String = abs_path.path_join("sparse")
	if DirAccess.dir_exists_absolute(sparse_dir):
		_delete_dir_recursive(sparse_dir)
		print("ReconstructionManager: Cleaned up old sparse reconstruction cache")

	save_session(session) # Auto-save initiale

	# Phase 1 : Extraction & Masquage
	var is_single_image: bool = false
	var ext: String = session.video_path.get_extension().to_lower()
	if ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp":
		is_single_image = true

	if is_single_image:
		print("Manager: Single image input detected. Skipping video extraction.")
		exporter.prepare_workspace(session)
		var dest_dir: String = ProjectSettings.globalize_path(session.output_directory).path_join("input")
		if not DirAccess.dir_exists_absolute(dest_dir):
			DirAccess.make_dir_recursive_absolute(dest_dir)
		var dest_path: String = dest_dir.path_join(session.video_path.get_file())
		DirAccess.copy_absolute(ProjectSettings.globalize_path(session.video_path), dest_path)
		session.frame_count = 1
		session.status = "Pre-processed"
		session_progress_updated.emit(33.0)
	else:
		var mask_mode: String = session.mask_mode if ("mask_mode" in session and not session.mask_mode.is_empty()) else "Smart Studio"
		print("Manager: Starting Phase 1 (Extraction) with mode: ", mask_mode)
		await run_extraction(session, mask_mode)

	if session.status == "Erreur" or session.frame_count == 0:
		if session.frame_count == 0:
			session.status = "Erreur"
			reconstruction_failed.emit("Échec : Aucune image valide n'a été extraite (toutes les images ont été ignorées à cause du flou). Veuillez baisser le seuil de flou (Blur Threshold) dans les paramètres.")
		else:
			reconstruction_failed.emit("Échec Phase 1 : Extraction")
		save_session(session)
		_end_task()
		return

	save_session(session) # Auto-save après Phase 1

	# TripoSplat path: single step replaces SfM + 3DGS training
	if "use_triposplat" in session and session.use_triposplat:
		session_progress_updated.emit(40.0)
		print("Manager: Using TripoSplat Feed-forward Path")
		await run_triposplat(session)
		if session.status == "Erreur":
			reconstruction_failed.emit("Échec TripoSplat")
			save_session(session)
			_end_task()
			return
		
		# Phase 4 : ArtiFixer Splat Refinement
		if "use_artifixer" in session and session.use_artifixer:
			session_progress_updated.emit(80.0)
			print("Manager: Starting Phase 4 (ArtiFixer Refinement after TripoSplat)...")
			await run_artifixer(session)
			if session.status == "Erreur":
				reconstruction_failed.emit("Échec Phase 4 : Raffinement ArtiFixer")
				save_session(session)
				_end_task()
				return
				
		session_progress_updated.emit(100.0)
		session_completed.emit(session)
		save_session(session) # Auto-save finale
		print("ReconstructionManager: TripoSplat pipeline terminé !")
		_end_task()
		return

	# WorldMirror 2.0 path: single step replaces SfM + 3DGS training
	if session.use_worldmirror:
		session_progress_updated.emit(40.0)
		print("Manager: Using WorldMirror 2.0 Feed-forward Path")
		await run_worldmirror(session)
		if session.status == "Erreur":
			reconstruction_failed.emit("Échec WorldMirror 2.0")
			save_session(session)
			_end_task()
			return
		
		# Phase 4 : ArtiFixer Splat Refinement
		if "use_artifixer" in session and session.use_artifixer:
			session_progress_updated.emit(80.0)
			print("Manager: Starting Phase 4 (ArtiFixer Refinement after WorldMirror)...")
			await run_artifixer(session)
			if session.status == "Erreur":
				reconstruction_failed.emit("Échec Phase 4 : Raffinement ArtiFixer")
				save_session(session)
				_end_task()
				return
				
		session_progress_updated.emit(100.0)
		session_completed.emit(session)
		save_session(session) # Auto-save finale
		print("ReconstructionManager: WorldMirror 2.0 pipeline terminé !")
		_end_task()
		return

	# Phase 2 : SfM (COLMAP) ou STAR (InSpatio) — legacy paths
	print("Manager: Phase 1 Done. Starting Phase 2...")
	session_progress_updated.emit(40.0)
	
	if session.use_fast_sync:
		print("Manager: Using Fast STAR-Lite Path (Monocular Depth)")
		await run_star_sync(session)
	else:
		print("Manager: Using Standard SfM Path (COLMAP)")
		await run_sfm(session)

	if session.status == "Erreur":
		reconstruction_failed.emit("Échec Phase 2 : Géométrie")
		save_session(session)
		_end_task()
		return

	save_session(session) # Auto-save après Phase 2

	# Phase 3 : Training 3DGS
	session_progress_updated.emit(70.0)
	await run_training(session)

	if session.status == "Erreur":
		reconstruction_failed.emit("Échec Phase 3 : 3DGS Training")
		save_session(session)
		_end_task()
		return

	# Phase 4 : ArtiFixer Splat Refinement
	if "use_artifixer" in session and session.use_artifixer:
		session_progress_updated.emit(88.0)
		print("Manager: Starting Phase 4 (ArtiFixer Refinement)...")
		await run_artifixer(session)
		if session.status == "Erreur":
			reconstruction_failed.emit("Échec Phase 4 : Raffinement ArtiFixer")
			save_session(session)
			_end_task()
			return

	session_progress_updated.emit(100.0)
	session_completed.emit(session)
	save_session(session) # Auto-save finale
	print("ReconstructionManager: Pipeline terminé avec succès !")
	_end_task()

## Step 2: SfM (COLMAP)
func run_sfm(session: ReconstructionSession) -> void:
	_start_task()
	if session.frame_count == 0:
		session.status = "Erreur"
		reconstruction_failed.emit("Échec Phase 2 : Aucune image à reconstruire. Veuillez d'abord extraire des images valides.")
		_end_task()
		return
	session.status = "SfM Running"
	session.is_processed = false # S'assurer qu'on ne lance pas le training
	print("ReconstructionManager: Phase 2 - COLMAP SfM...")
	backend.execute_reconstruction(session)
	# Attendre la fin du backend
	var finished_result: Variant = await backend.command_finished
	var finished_status: int = finished_result[0] if finished_result is Array else finished_result
	if finished_status != 0:
		session.status = "Erreur"
		reconstruction_failed.emit("Échec Phase 2 : COLMAP SfM")
		_end_task()
		return
	
	# Vérification des fichiers générés
	var output_ok: bool = exporter.verify_reconstruction_outputs(session)
	if not output_ok:
		session.status = "Erreur"
		reconstruction_failed.emit("Échec Phase 2 : La vérification des sorties COLMAP a échoué. Les fichiers de reconstruction sparse/0 sont manquants.")
		_end_task()
		return
	else:
		print("ReconstructionManager: Output verification succeeded. All required database and camera files generated.")
		
	session_progress_updated.emit(55.0)
	session.status = "SfM Finished"
	_end_task()

## Step 2 (Alternative): STAR Path (Monocular Depth DA3)
func run_star_sync(session: ReconstructionSession) -> void:
	_current_phase = 2
	_start_task()
	if session.frame_count == 0:
		session.status = "Erreur"
		reconstruction_failed.emit("Échec Phase 2 : Aucune image à traiter.")
		_end_task()
		return
	session.status = "STAR Syncing (DA3)"
	session.is_processed = false
	print("ReconstructionManager: Phase 2 - STAR Monocular Path...")
	backend.execute_reconstruction(session)
	# Attendre la fin du bridge Python
	await backend.command_finished
	
	# Vérification du workspace STAR
	var star_path: String = ProjectSettings.globalize_path(session.output_directory) + "/star_workspace/star_metadata.json"
	if FileAccess.file_exists(star_path):
		session_progress_updated.emit(60.0)
		session.status = "STAR Workspace Ready"
	else:
		session.status = "Erreur"
		reconstruction_failed.emit("Le STAR Workspace n'a pas été généré.")
	_end_task()

## Step 2 (TripoSplat): Feed-forward Single-Image Reconstruction
func run_triposplat(session: ReconstructionSession) -> void:
	_current_phase = 2
	_start_task()
	if session.frame_count == 0:
		session.status = "Erreur"
		reconstruction_failed.emit("Échec Phase 2 : Aucune image à traiter.")
		_end_task()
		return
	session.status = "TripoSplat Inference"
	session.is_processed = false
	print("ReconstructionManager: Phase 2 - TripoSplat Single-Image...")

	if session.dry_run:
		var global_dir: String = ProjectSettings.globalize_path(session.output_directory)
		var target_ply: String = global_dir.path_join("gaussians.ply")
		if not FileAccess.file_exists(target_ply):
			var f: FileAccess = FileAccess.open(target_ply, FileAccess.WRITE)
			if f:
				f.store_string("ply\nformat ascii 1.0\nelement vertex 0\nend_header\n")
				f.close()
		var marker_path: String = global_dir.path_join(".triposplat_done")
		var marker: FileAccess = FileAccess.open(marker_path, FileAccess.WRITE)
		if marker:
			marker.store_string('{"engine": "FoveaCore TripoSplat", "elapsed_s": 0.1}')
			marker.close()

	backend.execute_reconstruction(session)

	await backend.command_finished

	# Vérifier le marqueur de complétion
	var marker_path: String = ProjectSettings.globalize_path(session.output_directory) + "/.triposplat_done"
	if not FileAccess.file_exists(marker_path):
		session.status = "Erreur"
		reconstruction_failed.emit("TripoSplat: aucun marqueur de complétion trouvé.")
		_end_task()
		return

	var marker: FileAccess = FileAccess.open(marker_path, FileAccess.READ)
	if marker:
		var content: String = marker.get_as_text()
		print("ReconstructionManager: TripoSplat results -> ", content)
		marker.close()

	# Charger le PLY directement
	var ply_path: String = session.output_directory.path_join("gaussians.ply")
	var global_ply: String = ProjectSettings.globalize_path(ply_path)
	if FileAccess.file_exists(global_ply):
		_post_process_reconstruction_splats(session, global_ply)
		print("ReconstructionManager: Loading TripoSplat PLY from ", global_ply)
		var gaussians: Array[GaussianSplat] = PLYLoader.load_gaussians_from_ply(global_ply)
		if not gaussians.is_empty():
			session.splat_data_path = ply_path
			session.status = "Terminé (%d splats)" % gaussians.size()
		else:
			session.status = "Erreur Chargement PLY"
			push_error("ReconstructionManager: PLY loaded but empty")
	else:
		session.status = "Erreur"
		push_error("ReconstructionManager: gaussians.ply not found at " + global_ply)
	_end_task()


## Step 2 (WorldMirror 2.0): Feed-forward Reconstruction
func run_worldmirror(session: ReconstructionSession) -> void:
	_current_phase = 2
	_start_task()
	if session.frame_count == 0:
		session.status = "Erreur"
		reconstruction_failed.emit("Échec Phase 2 : Aucune image à traiter.")
		_end_task()
		return
	session.status = "WorldMirror 2.0 Inference"
	session.is_processed = false
	print("ReconstructionManager: Phase 2 - WorldMirror 2.0 Feed-forward...")

	if session.dry_run:
		var global_dir: String = ProjectSettings.globalize_path(session.output_directory)
		var target_ply: String = global_dir.path_join("gaussians.ply")
		if not FileAccess.file_exists(target_ply):
			var f: FileAccess = FileAccess.open(target_ply, FileAccess.WRITE)
			if f:
				f.store_string("ply\nformat ascii 1.0\nelement vertex 0\nend_header\n")
				f.close()
		var marker_path: String = global_dir.path_join(".worldmirror_done")
		var marker: FileAccess = FileAccess.open(marker_path, FileAccess.WRITE)
		if marker:
			marker.store_string('{"engine": "FoveaCore WorldMirror-2.0", "elapsed_s": 0.1}')
			marker.close()

	backend.execute_reconstruction(session)

	await backend.command_finished

	# Vérifier le marqueur de complétion
	var marker_path: String = ProjectSettings.globalize_path(session.output_directory) + "/.worldmirror_done"
	if not FileAccess.file_exists(marker_path):
		session.status = "Erreur"
		reconstruction_failed.emit("WorldMirror 2.0: aucun marqueur de complétion trouvé.")
		_end_task()
		return

	var marker: FileAccess = FileAccess.open(marker_path, FileAccess.READ)
	if marker:
		var content: String = marker.get_as_text()
		print("ReconstructionManager: WorldMirror 2.0 results -> ", content)
		marker.close()

	# Charger le PLY directement (WorldMirror produit gaussians.ply à la racine du workspace)
	var ply_path: String = session.output_directory.path_join("gaussians.ply")
	var global_ply: String = ProjectSettings.globalize_path(ply_path)
	if FileAccess.file_exists(global_ply):
		_post_process_reconstruction_splats(session, global_ply)
		print("ReconstructionManager: Loading WorldMirror PLY from ", global_ply)
		var gaussians: Array[GaussianSplat] = PLYLoader.load_gaussians_from_ply(global_ply)
		if not gaussians.is_empty():
			session.splat_data_path = ply_path
			session.status = "Terminé (%d splats)" % gaussians.size()
		else:
			session.status = "Erreur Chargement PLY"
			push_error("ReconstructionManager: PLY loaded but empty")
	else:
		session.status = "Erreur"
		push_error("ReconstructionManager: gaussians.ply not found at " + global_ply)
	_end_task()

## Step 3: Training (3DGS)
func run_training(session: ReconstructionSession) -> void:
	_current_phase = 3
	_start_task()
	session.status = "Training Splats (Long)..."
	session_progress_updated.emit(70.0)
	print("ReconstructionManager: Phase 3 - 3DGS Training (This can take 5-20 mins)...")
	session.is_processed = true
	backend.execute_reconstruction(session)
	
	# Attendre la fin du processus réel
	var finished_result: Variant = await backend.command_finished
	var finished_status: int = finished_result[0] if finished_result is Array else finished_result
	if finished_status != 0:
		session.status = "Erreur"
		reconstruction_failed.emit("Échec Phase 3 : 3DGS Training")
		_end_task()
		return
	session_progress_updated.emit(85.0)
	if session.status != "Erreur":
		session.status = "Finalizing..."
		exporter.finalize_session(session)
		
		# Load the resulting PLY if it exists
		var ply_path: String = session.output_directory.path_join("output/point_cloud/iteration_7000/point_cloud.ply")
		var global_ply: String = ProjectSettings.globalize_path(ply_path)
		if FileAccess.file_exists(global_ply):
			_post_process_reconstruction_splats(session, global_ply)
			print("ReconstructionManager: Loading result PLY from ", global_ply)
			var gaussians: Array[GaussianSplat] = PLYLoader.load_gaussians_from_ply(global_ply)
			if not gaussians.is_empty():
				session.splat_data_path = ply_path
				session.status = "Terminé (%d splats)" % gaussians.size()
			else:
				session.status = "Erreur Chargement PLY"
				push_error("ReconstructionManager: PLY loaded but empty or PLYLoader unavailable")
		else:
			session.status = "Terminé (PLY non trouvé)"
	_end_task()

## Step 4: ArtiFixer Splat Refinement
func run_artifixer(session: ReconstructionSession) -> void:
	_current_phase = 3
	_start_task()
	session.status = "ArtiFixer Refinement..."
	print("ReconstructionManager: Phase 4 - ArtiFixer Refinement...")

	if session.dry_run:
		var global_dir: String = ProjectSettings.globalize_path(session.output_directory)
		var target_ply: String = global_dir.path_join("artifixer_refined.ply")
		if not FileAccess.file_exists(target_ply):
			var f: FileAccess = FileAccess.open(target_ply, FileAccess.WRITE)
			if f:
				f.store_string("ply\nformat ascii 1.0\nelement vertex 0\nend_header\n")
				f.close()
		var marker_path: String = global_dir.path_join(".artifixer_done")
		var marker: FileAccess = FileAccess.open(marker_path, FileAccess.WRITE)
		if marker:
			marker.store_string('{"engine": "FoveaCore ArtiFixer-Refiner", "mode": "dry-run", "elapsed_s": 0.1}')
			marker.close()

	backend.execute_artifixer(session)

	await backend.command_finished
	
	# Vérifier le marqueur de complétion
	var marker_path: String = ProjectSettings.globalize_path(session.output_directory) + "/.artifixer_done"
	if not FileAccess.file_exists(marker_path):
		session.status = "Erreur"
		reconstruction_failed.emit("ArtiFixer: aucun marqueur de complétion trouvé.")
		_end_task()
		return

	var marker: FileAccess = FileAccess.open(marker_path, FileAccess.READ)
	if marker:
		var content: String = marker.get_as_text()
		print("ReconstructionManager: ArtiFixer results -> ", content)
		marker.close()

	# Charger le PLY raffiné
	var ply_path: String = session.output_directory.path_join("artifixer_refined.ply")
	var global_ply: String = ProjectSettings.globalize_path(ply_path)
	if FileAccess.file_exists(global_ply):
		_post_process_reconstruction_splats(session, global_ply)
		print("ReconstructionManager: Loading ArtiFixer PLY from ", global_ply)
		var gaussians: Array[GaussianSplat] = PLYLoader.load_gaussians_from_ply(global_ply)
		if not gaussians.is_empty():
			session.splat_data_path = ply_path
			session.status = "Terminé (%d splats raffinés)" % gaussians.size()
		else:
			session.status = "Erreur Chargement PLY"
			push_error("ReconstructionManager: PLY loaded but empty")
	else:
		session.status = "Erreur"
		push_error("ReconstructionManager: artifixer_refined.ply not found at " + global_ply)
	_end_task()


func _on_backend_started(task: String) -> void:
	print("Manager: Backend started -> ", task)
	log_line_received.emit(">>> Starting: " + task)
	# Logger dans la session active
	for sess: ReconstructionSession in active_sessions.values():
		if sess.status != "Terminé":
			sess.status = task

func _on_backend_progress(line: String, percent: float) -> void:
	log_line_received.emit(line)
	if percent >= 0:
		var mapped_percent: float = 0.0
		match _current_phase:
			1:
				mapped_percent = percent * 0.33
			2:
				mapped_percent = 33.0 + (percent * 0.33)
			3:
				mapped_percent = 66.0 + (percent * 0.34)
		session_progress_updated.emit(mapped_percent)

func _on_backend_finished(status: int, output: String) -> void:
	print("Manager: Backend finished -> ", output)
	log_line_received.emit(">>> Finished task with status %d" % status)
	if status != 0:
		push_warning("ReconstructionManager: commande terminée avec code d'erreur %d" % status)

func _post_process_reconstruction_splats(session: ReconstructionSession, global_ply: String) -> void:
	print("ReconstructionManager: Post-processing splats...")
	var gaussians: Array[GaussianSplat] = PLYLoader.load_gaussians_from_ply(global_ply)
	if gaussians.is_empty():
		push_error("ReconstructionManager: Failed to load PLY for post-processing.")
		return
		
	# 1. Color Auto-tagging
	if session.auto_tag_color:
		print("ReconstructionManager: Performing auto color tagging...")
		SplatProcessorHelper.auto_tag_splats_by_color(gaussians)
		
	# 2. Shape Assignment
	if not session.splat_shape.is_empty():
		print("ReconstructionManager: Assigning splat shapes: ", session.splat_shape)
		SplatProcessorHelper.assign_shapes(gaussians, session.splat_shape)
		
	# 3. Density Decimation
	if session.splat_count_density < 0.99:
		var old_size: int = gaussians.size()
		gaussians = SplatProcessorHelper.decimate_splats(gaussians, session.splat_count_density)
		print("ReconstructionManager: Decimated splats from %d to %d" % [old_size, gaussians.size()])
		
	# Save back to PLY
	var temp_renderer: SplatRenderer = SplatRenderer.new()
	temp_renderer.load_splats(gaussians)
	var err: Error = temp_renderer.export_to_ply(global_ply)
	temp_renderer.queue_free()
	if err == OK:
		print("ReconstructionManager: Post-processed splats written back to ", global_ply)
	else:
		push_error("ReconstructionManager: Failed to write back post-processed splats to PLY.")
