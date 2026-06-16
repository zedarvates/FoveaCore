extends Node
class_name ReconstructionBackend

## ReconstructionBackend — Handles external tool execution (COLMAP, 3DGS, Python)
## Executes commands in the background and reports progress/errors

signal command_started(command: String)
signal command_progress(current_line: String, percent: float)
signal command_finished(status: int, output: String)
signal error_occurred(message: String)
signal oom_detected(command: String, details: String)

## Path to external dependencies (can be configured in project settings)
@export var colmap_path: String = "colmap"
@export var python_path: String = "python"
@export var gaussiantrain_script: String = "train.py"
@export var star_bridge_script: String = "star_bridge.py"
## Chemin vers les poids DA3 (.pth). Vide = repli heuristique (basse qualité, avertissement explicite).
@export var star_da3_checkpoint: String = ""
@export var worldmirror_bridge_script: String = "worldmirror_bridge.py"
@export var triposplat_bridge_script: String = "triposplat_bridge.py"
@export var artifixer_bridge_script: String = "artifixer_bridge.py"

## Timeout maximum en secondes pour chaque commande externe (0 = pas de timeout)
@export var command_timeout_seconds: float = 1800.0  # 30 min par defaut

var _stdout_thread: Thread = null
var _stderr_thread: Thread = null
var _current_pid: int = -1
## Mode test (Dry Run) : affiche les commandes sans les lancer pour de vrai
@export var dry_run: bool = false

## Run the full reconstruction pipeline using external calls
func execute_reconstruction(session: ReconstructionSession) -> void:
	# Choix entre WorldMirror 2.0, TripoSplat, STAR (legacy) et COLMAP complet
	if not session.is_processed:
		if session.use_triposplat:
			_run_triposplat_path(session)
		elif session.use_worldmirror:
			_run_worldmirror_path(session)
		elif session.use_fast_sync:
			_run_star_monocular_path(session)
		else:
			_run_colmap_features(session)
	else:
		# Si is_processed est à true, c'est qu'on veut lancer le training
		_run_gaussian_training(session)

func _run_colmap_features(session: ReconstructionSession) -> void:
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
		
	# Utilisation du reconstructeur automatique de COLMAP (plus robuste)
	var args = [
		"automatic_reconstructor",
		"--workspace_path", abs_path,
		"--image_path", abs_path + "/input",
		"--data_type", "individual" if session.exhaustive_matching else "video",
		"--quality", "medium",
		"--use_gpu", "1"
	]
	
	# Pass masks to COLMAP if masks directory exists
	var mask_path = abs_path + "/masks"
	if DirAccess.dir_exists_absolute(mask_path):
		args.append("--mask_path")
		args.append(mask_path)
	
	_execute_command(colmap_path, args, "COLMAP: Full SfM Reconstruction", session)

func _run_gaussian_training(session: ReconstructionSession) -> void:
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
	var args = [
		gaussiantrain_script,
		"-s", abs_path,
		"-m", abs_path + "/output",
		"--iterations", "7000"
	]
	_execute_command(python_path, args, "3DGS: Training Splats", session)

func _run_worldmirror_path(session: ReconstructionSession) -> void:
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
	var script_path = ProjectSettings.globalize_path("res://addons/foveacore/scripts/reconstruction").path_join(worldmirror_bridge_script)
	var args = [
		script_path,
		"--input", abs_path + "/input",
		"--output", abs_path,
		"--device", "cuda",
		"--target_size", str(session.target_size),
		"--fps", str(session.extraction_fps)
	]
	_execute_command(python_path, args, "WorldMirror 2.0: Feed-forward Reconstruction", session)

func _run_triposplat_path(session: ReconstructionSession) -> void:
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
	var script_path = ProjectSettings.globalize_path("res://addons/foveacore/scripts/reconstruction").path_join(triposplat_bridge_script)
	
	var input_image = session.video_path
	if not FileAccess.file_exists(input_image):
		# Fallback to the first image found in input_dir
		var input_dir = abs_path.path_join("input")
		if DirAccess.dir_exists_absolute(input_dir):
			var dir = DirAccess.open(input_dir)
			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if not dir.current_is_dir() and (file_name.to_lower().matchn("*.png") or file_name.to_lower().matchn("*.jpg") or file_name.to_lower().matchn("*.jpeg") or file_name.to_lower().matchn("*.webp")):
					input_image = input_dir.path_join(file_name)
					break
				file_name = dir.get_next()
	
	var args = [
		script_path,
		"--input", ProjectSettings.globalize_path(input_image),
		"--output", abs_path,
		"--device", "cuda",
		"--density", "262144"
	]
	_execute_command(python_path, args, "TripoSplat: Single-Image Reconstruction", session)

func _run_star_monocular_path(session: ReconstructionSession) -> void:
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
	var script_path = ProjectSettings.globalize_path("res://addons/foveacore/scripts/reconstruction").path_join(star_bridge_script)
	var args = [
		script_path,
		"--input", abs_path + "/input",
		"--output", abs_path + "/star_workspace",
		"--device", "cuda"
	]
	# Poids DA3 requis pour une vraie inférence ; sinon repli heuristique explicite (audit B8)
	if not star_da3_checkpoint.is_empty():
		args.append_array(["--checkpoint", star_da3_checkpoint])
	else:
		args.append("--allow-heuristic")
		push_warning("ReconstructionBackend: star_da3_checkpoint non défini — profondeur heuristique basse qualité.")
	_execute_command(python_path, args, "STAR: Fast Monocular Depth (DA3)", session)

## Runs ArtiFixer refinement on the current reconstruction
func execute_artifixer(session: ReconstructionSession) -> void:
	_run_artifixer_path(session)

func _run_artifixer_path(session: ReconstructionSession) -> void:
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
	var script_path = ProjectSettings.globalize_path("res://addons/foveacore/scripts/reconstruction").path_join(artifixer_bridge_script)
	var args = [
		script_path,
		"--input", abs_path,
		"--output", abs_path
	]
	if not session.artifixer_checkpoint.is_empty():
		args.append_array(["--checkpoint", session.artifixer_checkpoint])
	if session.dry_run:
		args.append("--dry-run")
	_execute_command(python_path, args, "ArtiFixer: Splat Refinement & Novel-view Synthesis", session)


func _execute_command(executable: String, args: Array, task_name: String, session: ReconstructionSession = null) -> void:
	command_started.emit(task_name)
	var cmd_str: String = executable + " " + " ".join(args)
	print("ReconstructionBackend: Executing -> ", cmd_str)

	if session and session.dry_run:
		var msg: String = "[DRY RUN] Would execute command: " + cmd_str
		print(msg)
		command_progress.emit(msg, 50.0)
		await get_tree().create_timer(1.0).timeout
		command_finished.emit(0, msg + "\n[DRY RUN] Completed successfully.")
		return

	# execute_with_pipe capture stdout+stderr séparés
	var pipe: Dictionary = OS.execute_with_pipe(executable, args)

	var stdio = pipe.get("stdio", null)
	var stderr = pipe.get("stderr", null)
	var pid = pipe.get("pid", -1)

	if stdio == null or pid == -1:
		var err_msg = "Échec du lancement : " + task_name + " (Vérifiez le chemin : " + executable + ")"
		error_occurred.emit(err_msg)
		command_finished.emit(1, "Failed to start")
		return

	_current_pid = pid

	# Structure partagée et thread-safe pour suivre l'état de la commande
	var shared_data = {
		"full_output": "",
		"last_output_time": Time.get_ticks_msec(),
		"oom_detected": false,
		"lock": Mutex.new()
	}

	# Spawn deux threads indépendants pour éviter les inter-blocages de tampons de flux (deadlocks)
	_stdout_thread = Thread.new()
	_stdout_thread.start(Callable(self, "_stdout_read_loop").bind(stdio, task_name, shared_data, pid))
	
	_stderr_thread = Thread.new()
	_stderr_thread.start(Callable(self, "_stderr_read_loop").bind(stderr, task_name, shared_data, pid))

	# Lancement de la boucle d'attente/polling asynchrone non bloquante sur le thread principal
	_poll_process(pid, task_name, shared_data)

func _stdout_read_loop(stdio: FileAccess, task_name: String, shared_data: Dictionary, pid: int) -> void:
	if not stdio:
		return
	while not stdio.eof_reached():
		var line = stdio.get_line()
		if line.is_empty() and not OS.is_process_running(pid):
			break
		if not line.is_empty():
			shared_data.lock.lock()
			shared_data.last_output_time = Time.get_ticks_msec()
			shared_data.full_output += line + "\n"
			shared_data.lock.unlock()
			
			print("[%s] %s" % [task_name, line])
			var progress_pct = _parse_progress_percent(line, task_name)
			command_progress.emit.call_deferred(line, progress_pct)
			
			# Détection Out Of Memory (OOM)
			var lower_line = line.to_lower()
			for pattern in ["cuda out of memory", "out of memory", "oom", "memory allocation failed", "cannot allocate memory", "failed to allocate", "allocation failed"]:
				if lower_line.contains(pattern):
					shared_data.lock.lock()
					if not shared_data.oom_detected:
						shared_data.oom_detected = true
						var oom_msg = "OOM détecté dans %s : %s" % [task_name, line.strip_edges()]
						oom_detected.emit.call_deferred(task_name, oom_msg)
						error_occurred.emit.call_deferred(oom_msg)
					shared_data.lock.unlock()
					break

func _stderr_read_loop(stderr: FileAccess, task_name: String, shared_data: Dictionary, pid: int) -> void:
	if not stderr:
		return
	while not stderr.eof_reached():
		var line = stderr.get_line()
		if line.is_empty() and not OS.is_process_running(pid):
			break
		if not line.is_empty():
			shared_data.lock.lock()
			shared_data.last_output_time = Time.get_ticks_msec()
			shared_data.full_output += "[ERR] " + line + "\n"
			shared_data.lock.unlock()
			
			print("[%s] [ERR] %s" % [task_name, line])
			var progress_pct = _parse_progress_percent(line, task_name)
			command_progress.emit.call_deferred(line, progress_pct)
			
			# Détection Out Of Memory (OOM)
			var lower_line = line.to_lower()
			for pattern in ["cuda out of memory", "out of memory", "oom", "memory allocation failed", "cannot allocate memory", "failed to allocate", "allocation failed"]:
				if lower_line.contains(pattern):
					shared_data.lock.lock()
					if not shared_data.oom_detected:
						shared_data.oom_detected = true
						var oom_msg = "OOM détecté dans %s : %s" % [task_name, line.strip_edges()]
						oom_detected.emit.call_deferred(task_name, oom_msg)
						error_occurred.emit.call_deferred(oom_msg)
					shared_data.lock.unlock()
					break

func _poll_process(pid: int, task_name: String, shared_data: Dictionary) -> void:
	var start_time := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		# Yield au thread principal pour garder l'UI réactive
		await get_tree().create_timer(0.2).timeout
		
		# Limite de temps (timeout)
		if command_timeout_seconds > 0:
			var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
			if elapsed > command_timeout_seconds:
				push_error("Backend: Timeout (%ds) dépassé pour '%s', arrêt du processus." % [int(command_timeout_seconds), task_name])
				OS.kill(pid)
				shared_data.lock.lock()
				shared_data.full_output += "[TIMEOUT] Process killed after %.0fs\n" % elapsed
				shared_data.lock.unlock()
				break
				
		# Détection de gel du processus (plus de sorties console)
		shared_data.lock.lock()
		var idle_time = Time.get_ticks_msec() - shared_data.last_output_time
		shared_data.lock.unlock()
		
		if idle_time > 300000: # 5 min sans sortie
			push_error("Backend: Aucun retour de '%s' depuis 5 min, processus probablement gelé." % task_name)
			OS.kill(pid)
			shared_data.lock.lock()
			shared_data.full_output += "[HUNG] Process killed (no output for 5 min)\n"
			shared_data.lock.unlock()
			break
			
	# Attente propre de l'arrêt des threads de lecture
	if _stdout_thread and _stdout_thread.is_started():
		_stdout_thread.wait_to_finish()
	if _stderr_thread and _stderr_thread.is_started():
		_stderr_thread.wait_to_finish()
		
	_current_pid = -1
	var exit_code = OS.get_process_exit_code(pid)
	
	shared_data.lock.lock()
	var out = shared_data.full_output
	var oom = shared_data.oom_detected
	shared_data.lock.unlock()
	
	if exit_code != 0 and not oom:
		var err_msg = "Commande '%s' échouée avec code %d" % [task_name, exit_code]
		error_occurred.emit(err_msg)
		
	command_finished.emit(exit_code, out)

func _exit_tree() -> void:
	if _current_pid != -1 and OS.is_process_running(_current_pid):
		OS.kill(_current_pid)
	if _stdout_thread and _stdout_thread.is_started():
		_stdout_thread.wait_to_finish()
	if _stderr_thread and _stderr_thread.is_started():
		_stderr_thread.wait_to_finish()


func _parse_progress_percent(line: String, task_name: String) -> float:
	var stripped = line.strip_edges()
	var lower = stripped.to_lower()

	# COLMAP: "Reconstruction 1: 50%" or " 50%"
	var re_pct = RegEx.new()
	re_pct.compile("(\\d+)\\s*%")
	var pct_match = re_pct.search(stripped)
	if pct_match:
		return float(pct_match.get_string(1))

	# COLMAP: "Iteration [100/500]"
	var re_iter = RegEx.new()
	re_iter.compile("Iteration\\s*\\[\\s*(\\d+)\\s*/\\s*(\\d+)\\s*\\]")
	var iter_match = re_iter.search(lower)
	if iter_match:
		var current = float(iter_match.get_string(1))
		var total = float(iter_match.get_string(2))
		if total > 0:
			return (current / total) * 100.0

	# 3DGS training: "Training progress: 150/7000"
	var re_train = RegEx.new()
	re_train.compile("(?i)training.*?(\\d+)\\s*/\\s*(\\d+)")
	var train_match = re_train.search(lower)
	if train_match:
		var current = float(train_match.get_string(1))
		var total = float(train_match.get_string(2))
		if total > 0:
			return (current / total) * 100.0

	# COLMAP: "Extracting features for image [100/200]"
	var re_img = RegEx.new()
	re_img.compile("\\[\\s*(\\d+)\\s*/\\s*(\\d+)\\s*\\]")
	var img_match = re_img.search(stripped)
	if img_match:
		var current = float(img_match.get_string(1))
		var total = float(img_match.get_string(2))
		if total > 0:
			return (current / total) * 100.0

	# COLMAP phase keywords
	if lower.contains("extracting features"):
		return 0.0
	if lower.contains("matching"):
		return 15.0
	if lower.contains("reconstruction") and lower.contains("start"):
		return 25.0
	if lower.contains("bundle adjustment"):
		return 40.0
	if lower.contains("undistorting"):
		return 70.0
	if lower.contains("dense"):
		return 80.0

	# 3DGS phase keywords
	if lower.contains("loading training"):
		return 0.0
	if lower.contains("training progress"):
		return 50.0  # placeholder if no number found
	if lower.contains("saving"):
		return 95.0

	# WorldMirror 2.0 phase keywords
	if lower.contains("model loaded"):
		return 30.0
	if lower.contains("running inference"):
		return 40.0
	if lower.contains("worldmirror 2.0 bridge: done"):
		return 95.0
	if lower.contains("completion marker"):
		return 100.0

	return -1.0
