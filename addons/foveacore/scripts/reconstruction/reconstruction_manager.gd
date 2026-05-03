extends Node
class_name FoveaReconstructionManager

## ReconstructionManager — Coordinates reconstruction sessions
## Interaces with externally compiled tools for SfM and 3DGS-Training

signal session_started(name: String)
signal session_progress_updated(progress: float)
signal session_completed(result: ReconstructionSession)
signal reconstruction_failed(reason: String)

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

# Fichier de configuration utilisateur (hors projet)
var _user_config_path: String = OS.get_user_data_dir() + "/fovea_engine_user_settings.cfg"


@export var metrics: ReconstructionMetrics = null
@export var default_output_dir: String = "res://reconstructions/"

var active_sessions: Dictionary = {}

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

	if processor == null:
		processor = StudioProcessor.new()
		add_child(processor)
	processor.ffmpeg_path = ffmpeg_path
	processor.error_occurred.connect(func(err): reconstruction_failed.emit(err))

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
		backend.command_started.connect(_on_backend_started)
		backend.command_progress.connect(_on_backend_progress)
		backend.command_finished.connect(_on_backend_finished)
		backend.error_occurred.connect(func(err): reconstruction_failed.emit(err))
		backend.oom_detected.connect(func(cmd, details): reconstruction_failed.emit(details))

func check_tools() -> Dictionary:
	var results = {
		"ffmpeg": {"found": false, "version": "", "error": ""},
		"colmap": {"found": false, "version": "", "error": ""}
	}

	# Vérification FFmpeg
	if not _is_tool_available(ffmpeg_path, ["-version"]):
		_auto_detect_ffmpeg()
	var ff_info = _validate_tool_version(ffmpeg_path, "-version")
	results["ffmpeg"] = ff_info
	if not ff_info.found:
		_auto_detect_ffmpeg()
		ff_info = _validate_tool_version(ffmpeg_path, "-version")
		results["ffmpeg"] = ff_info

	# Vérification COLMAP
	if not _is_tool_available(colmap_path, ["--help"]):
		_auto_detect_colmap()
	var cm_info = _validate_tool_version(colmap_path, "--help")
	results["colmap"] = cm_info
	if not cm_info.found:
		_auto_detect_colmap()
		cm_info = _validate_tool_version(colmap_path, "--help")
		results["colmap"] = cm_info

	# Logging
	if results["ffmpeg"].found:
		print("FoveaManager: FFmpeg OK - ", results["ffmpeg"].version.split("\n")[0])
	else:
		push_warning("FoveaManager: FFmpeg NOT FOUND")

	if results["colmap"].found:
		print("FoveaManager: COLMAP OK")
	else:
		push_warning("FoveaManager: COLMAP NOT FOUND")

	return results

func _is_tool_available(path: String, args: Array) -> bool:
	var out = []
	var err = OS.execute(path, args, out)
	return err == 0

func _validate_tool_version(path: String, version_arg: String, min_version: String = "") -> Dictionary:
	"""Vérifie la version d'un outil. Retourne {found: bool, version: str, error: str}."""
	var out = []
	var err = OS.execute(path, [version_arg], out)
	if err != 0:
		return {"found": false, "version": "", "error": "Tool not found or failed"}

	if not out.is_empty():
		var version_line = out[0].strip_edges()
		# Parse version (simplifié)
		return {"found": true, "version": version_line, "error": ""}

	return {"found": true, "version": "unknown", "error": ""}

func _auto_detect_ffmpeg() -> void:
	var cmd = "where" if OS.has_feature("windows") else "which"
	var out = []
	var err = OS.execute(cmd, ["ffmpeg"], out)
	if err == 0 and not out.is_empty():
		ffmpeg_path = out[0].strip_edges().split("\n")[0]
		print("FoveaManager: FFmpeg détecté automatiquement via PATH : ", ffmpeg_path)
		return
		
	# Fallback sur chemins communs si non dans PATH
	var home_path = OS.get_environment("HOME") if OS.has_feature("unix") else OS.get_environment("USERPROFILE")
	var is_windows = OS.has_feature("windows")
	var bin_name = "ffmpeg.exe" if is_windows else "ffmpeg"
	
	var possible_paths = [
		"C:/ffmpeg/bin/ffmpeg.exe",
		"/usr/bin/ffmpeg",
		"/usr/local/bin/ffmpeg",
	]
	
	if not home_path.is_empty():
		possible_paths.append(home_path + "/Documents/ffmpeg-8.0-win-x64/" + bin_name)
		possible_paths.append(home_path + "/Documents/ffmpeg/bin/" + bin_name)
		possible_paths.append(home_path + "/Documents/ffmpeg-master-latest-win64-gpl-shared/ffmpeg-master-latest-win64-gpl-shared/bin/" + bin_name)
		possible_paths.append(home_path + "/Documents/ffmpeg/bin/" + bin_name)
	
	for p in possible_paths:
		if _is_tool_available(p, ["-version"]):
			print("FoveaManager: FFmpeg détecté automatiquement à : ", p)
			ffmpeg_path = p 
			return

func _auto_detect_colmap() -> void:
	var home_path = OS.get_environment("HOME") if OS.has_feature("unix") else OS.get_environment("USERPROFILE")
	var is_windows = OS.has_feature("windows")
	var bin_name = "colmap.exe" if is_windows else "colmap"

	var possible_paths = [
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

	for p in possible_paths:
		if _is_tool_available(p, ["--help"]):
			print("FoveaManager: COLMAP détecté automatiquement à : ", p)
			colmap_path = p
			return

# --- Persistence des Settings Utilisateur ---

func _save_user_settings() -> void:
	"""Sauvegarde les chemins outils dans un fichier cfg utilisateur (hors projet)."""
	var config = ConfigFile.new()
	config.set_value("tools", "ffmpeg_path", ffmpeg_path)
	config.set_value("tools", "colmap_path", colmap_path)
	config.set_value("tools", "python_path", python_path)
	config.set_value("tools", "gaussian_train_script", gaussian_train_script)
	config.set_value("tools", "star_bridge_script", star_bridge_script)
	config.set_value("tools", "worldmirror_bridge_script", worldmirror_bridge_script)

	var err = config.save(_user_config_path)
	if err != OK:
		push_error("Failed to save user settings to " + _user_config_path)
	else:
		print("FoveaManager: User settings saved to ", _user_config_path)

func _load_user_settings() -> void:
	"""Charge les chemins outils depuis le fichier cfg utilisateur si existant."""
	if not FileAccess.file_exists(_user_config_path):
		print("FoveaManager: No user settings file found, using defaults.")
		return

	var config = ConfigFile.new()
	var err = config.load(_user_config_path)
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
	var path = session.output_directory.path_join(session.session_name + ".tres")
	var dir = ProjectSettings.globalize_path(session.output_directory)
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err = ResourceSaver.save(session, path)
	print("Manager: Session saved to ", path, " (Error: ", err, ")")
	return err

func load_session(path: String) -> ReconstructionSession:
	if not FileAccess.file_exists(path):
		return null
	var res = ResourceLoader.load(path)
	if res is ReconstructionSession:
		active_sessions[res.session_name] = res
		print("Manager: Session loaded: ", res.session_name)
		return res
	return null

## Step 1: Extraction & Masking
func run_extraction(session: ReconstructionSession, mask_mode: String = "Studio White") -> void:
	session_started.emit(session.session_name)
	session.status = "Extracting Frames"
	
	# Prepare workspace
	exporter.prepare_workspace(session)
	metrics = ReconstructionMetrics.new()
	
	# Connecter le masquage automatique pendant l'extraction
	var masking_func = func(idx, img): 
		var mask = processor.mask_background(img, mask_mode, session.background_threshold, session.roi_rect)
		exporter.export_frame(session, idx, img, mask)
		var coverage = _calculate_mask_coverage(mask)
		metrics.add_frame_metrics(idx, 1.0, coverage)
		# Update progress bar incrementally (0 to 33%)
		if session.frame_count > 0:
			session_progress_updated.emit((float(idx) / float(session.frame_count)) * 33.0)
	
	processor.frame_extracted.connect(masking_func)
	
	# Lancer l'extraction réelle
	await processor.extract_frames(session)
	
	# Nettoyage
	processor.frame_extracted.disconnect(masking_func)
	exporter.create_metadata_json(session)
	
	session.status = "Pre-processed"
	print(metrics.get_quality_report())
	session_progress_updated.emit(33.0)

func _calculate_mask_coverage(mask: Image) -> float:
	# Estimate surface covered by non-transparent pixels
	var transparent_pixels = 0
	var size = mask.get_size()
	# Sample every 10th pixel for performance
	for y in range(0, size.y, 10):
		for x in range(0, size.x, 10):
			if mask.get_pixel(x, y).a < 0.1:
				transparent_pixels += 1
	
	var total_sampled = (size.x/10) * (size.y/10)
	if total_sampled <= 0:
		return 0.0
	return 1.0 - (float(transparent_pixels) / float(total_sampled))

## Lancer le pipeline complet en séquence (Phase 1 + 2 + 3)
func run_reconstruction(session: ReconstructionSession) -> void:
	if session == null:
		push_error("ReconstructionManager: session est null")
		return

	session_started.emit(session.session_name)
	print("ReconstructionManager: Démarrage du pipeline complet pour '", session.session_name, "'")

	# Phase 1 : Extraction & Masquage
	var mask_mode := "Smart Studio"
	print("Manager: Starting Phase 1 (Extraction)...")
	await run_extraction(session, mask_mode)

	if session.status == "Erreur":
		reconstruction_failed.emit("Échec Phase 1 : Extraction")
		return

	# WorldMirror 2.0 path: single step replaces SfM + 3DGS training
	if session.use_worldmirror:
		session_progress_updated.emit(40.0)
		print("Manager: Using WorldMirror 2.0 Feed-forward Path")
		await run_worldmirror(session)
		if session.status == "Erreur":
			reconstruction_failed.emit("Échec WorldMirror 2.0")
			return
		session_progress_updated.emit(100.0)
		session_completed.emit(session)
		print("ReconstructionManager: WorldMirror 2.0 pipeline terminé !")
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
		return

	# Phase 3 : Training 3DGS
	session_progress_updated.emit(70.0)
	await run_training(session)

	if session.status == "Erreur":
		reconstruction_failed.emit("Échec Phase 3 : 3DGS Training")
		return

	session_progress_updated.emit(100.0)
	session_completed.emit(session)
	print("ReconstructionManager: Pipeline terminé avec succès !")

## Step 2: SfM (COLMAP)
func run_sfm(session: ReconstructionSession) -> void:
	session.status = "SfM Running"
	session.is_processed = false # S'assurer qu'on ne lance pas le training
	print("ReconstructionManager: Phase 2 - COLMAP SfM...")
	backend.execute_reconstruction(session)
	# Attendre la fin du backend
	var finished_status = await backend.command_finished
	if finished_status != 0:
		session.status = "Erreur"
		reconstruction_failed.emit("Échec Phase 2 : COLMAP SfM")
		return
	session_progress_updated.emit(55.0)
	session.status = "SfM Finished"

## Step 2 (Alternative): STAR Path (Monocular Depth DA3)
func run_star_sync(session: ReconstructionSession) -> void:
	session.status = "STAR Syncing (DA3)"
	session.is_processed = false
	print("ReconstructionManager: Phase 2 - STAR Monocular Path...")
	backend.execute_reconstruction(session)
	# Attendre la fin du bridge Python
	await backend.command_finished
	
	# Vérification du workspace STAR
	var star_path = ProjectSettings.globalize_path(session.output_directory) + "/star_workspace/star_metadata.json"
	if FileAccess.file_exists(star_path):
		session_progress_updated.emit(60.0)
		session.status = "STAR Workspace Ready"
	else:
		session.status = "Erreur"
		reconstruction_failed.emit("Le STAR Workspace n'a pas été généré.")

## Step 2 (WorldMirror 2.0): Feed-forward Reconstruction
func run_worldmirror(session: ReconstructionSession) -> void:
	session.status = "WorldMirror 2.0 Inference"
	session.is_processed = false
	print("ReconstructionManager: Phase 2 - WorldMirror 2.0 Feed-forward...")
	backend.execute_reconstruction(session)

	await backend.command_finished

	# Vérifier le marqueur de complétion
	var marker_path = ProjectSettings.globalize_path(session.output_directory) + "/.worldmirror_done"
	if not FileAccess.file_exists(marker_path):
		session.status = "Erreur"
		reconstruction_failed.emit("WorldMirror 2.0: aucun marqueur de complétion trouvé.")
		return

	var marker = FileAccess.open(marker_path, FileAccess.READ)
	if marker:
		var content = marker.get_as_text()
		print("ReconstructionManager: WorldMirror 2.0 results -> ", content)
		marker.close()

	# Charger le PLY directement (WorldMirror produit gaussians.ply à la racine du workspace)
	var ply_path = session.output_directory.path_join("gaussians.ply")
	var global_ply = ProjectSettings.globalize_path(ply_path)
	if FileAccess.file_exists(global_ply):
		print("ReconstructionManager: Loading WorldMirror PLY from ", global_ply)
		var gaussians = PLYLoader.load_gaussians_from_ply(global_ply)
		if gaussians and not gaussians.is_empty():
			session.splat_data_path = ply_path
			session.status = "Terminé (%d splats)" % gaussians.size()
		else:
			session.status = "Erreur Chargement PLY"
			push_error("ReconstructionManager: PLY loaded but empty")
	else:
		session.status = "Erreur"
		push_error("ReconstructionManager: gaussians.ply not found at " + global_ply)

## Step 3: Training (3DGS)
func run_training(session: ReconstructionSession) -> void:
	session.status = "Training Splats (Long)..."
	session_progress_updated.emit(70.0)
	print("ReconstructionManager: Phase 3 - 3DGS Training (This can take 5-20 mins)...")
	session.is_processed = true
	backend.execute_reconstruction(session)
	
	# Attendre la fin du processus réel
	var finished_status = await backend.command_finished
	if finished_status != 0:
		session.status = "Erreur"
		reconstruction_failed.emit("Échec Phase 3 : 3DGS Training")
		return
	session_progress_updated.emit(85.0)
	if session.status != "Erreur":
		session.status = "Finalizing..."
		exporter.finalize_session(session)
		
		# Load the resulting PLY if it exists
		var ply_path = session.output_directory.path_join("output/point_cloud/iteration_7000/point_cloud.ply")
		var global_ply = ProjectSettings.globalize_path(ply_path)
		if FileAccess.file_exists(global_ply):
			print("ReconstructionManager: Loading result PLY from ", global_ply)
			var gaussians = PLYLoader.load_gaussians_from_ply(global_ply)
			if gaussians and not gaussians.is_empty():
				session.splat_data_path = ply_path
				session.status = "Terminé (%d splats)" % gaussians.size()
			else:
				session.status = "Erreur Chargement PLY"
				push_error("ReconstructionManager: PLY loaded but empty or PLYLoader unavailable")
		else:
			session.status = "Terminé (PLY non trouvé)"

func _on_backend_started(task: String) -> void:
	print("Manager: Backend started -> ", task)
	# Logger dans la session active
	for sess in active_sessions.values():
		if sess.status != "Terminé":
			sess.status = task

func _on_backend_progress(line: String, percent: float) -> void:
	# Afficher la ligne dans le log (si UI attachée)
	# Mise à jour de la progression si pourcentage estimé
	if percent >= 0:
		session_progress_updated.emit(percent)
	# Toujours émettre un signal de progression de ligne pour les logs
	# (La UI peut choisir de l'afficher ou non)

func _on_backend_finished(status: int, output: String) -> void:
	print("Manager: Backend finished -> ", output)
	if status != 0:
		push_warning("ReconstructionManager: commande terminée avec code d'erreur %d" % status)
