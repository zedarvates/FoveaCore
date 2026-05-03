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

## Timeout maximum en secondes pour chaque commande externe (0 = pas de timeout)
@export var command_timeout_seconds: float = 1800.0  # 30 min par defaut

## Run the full reconstruction pipeline using external calls
func execute_reconstruction(session: ReconstructionSession) -> void:
	# Choix entre chemin complet (COLMAP) et chemin rapide (STAR)
	if not session.is_processed:
		if session.use_fast_sync: # Nouveau flag pour STAR
			_run_star_monocular_path(session)
		else:
			_run_colmap_features(session)
	else:
		# Si is_processed est à true, c'est qu'on veut lancer le training
		_run_gaussian_training(session)

func _run_colmap_features(session: ReconstructionSession) -> void:
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
	
	# Création du dossier sparse s'il n'existe pas
	var sparse_dir = abs_path + "/sparse"
	if not DirAccess.dir_exists_absolute(sparse_dir):
		DirAccess.make_dir_recursive_absolute(sparse_dir)
		
	# Utilisation du reconstructeur automatique de COLMAP (plus robuste)
	var args = [
		"automatic_reconstructor",
		"--workspace_path", abs_path,
		"--image_path", abs_path + "/input",
		"--data_type", "video",
		"--quality", "medium",
		"--use_gpu", "1"
	]
	
	_execute_command(colmap_path, args, "COLMAP: Full SfM Reconstruction")

func _run_gaussian_training(session: ReconstructionSession) -> void:
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
	var args = [
		gaussiantrain_script,
		"-s", abs_path,
		"-m", abs_path + "/output",
		"--iterations", "7000"
	]
	_execute_command(python_path, args, "3DGS: Training Splats")

func _run_star_monocular_path(session: ReconstructionSession) -> void:
	var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
	var args = [
		star_bridge_script,
		"--input", abs_path + "/input",
		"--output", abs_path + "/star_workspace",
		"--device", "cuda"
	]
	_execute_command(python_path, args, "STAR: Fast Monocular Depth (DA3)")

func _execute_command(executable: String, args: Array, task_name: String) -> void:
	command_started.emit(task_name)
	var cmd_str = executable + " " + " ".join(args)
	print("ReconstructionBackend: Executing -> ", cmd_str)

	# execute_with_pipe capture stdout+stderr séparés
	var pipe = OS.execute_with_pipe(executable, args)

	var stdio = pipe.get("stdio", null)
	var stderr = pipe.get("stderr", null)
	var pid = pipe.get("pid", -1)

	if stdio == null or pid == -1:
		var err_msg = "Échec du lancement : " + task_name + " (Vérifiez le chemin : " + executable + ")"
		error_occurred.emit(err_msg)
		command_finished.emit(1, "Failed to start")
		return

	# Lecture asynchrone des deux flux
	_read_pipes_async(stdio, stderr, pid, task_name)

func _read_pipes_async(stdio: FileAccess, stderr: FileAccess, pid: int, task_name: String) -> void:
	var full_output = ""
	var line_count = 0
	var oom_detected_flag = false
	var start_time := Time.get_ticks_msec()
	var last_output_time := Time.get_ticks_msec()
	var oom_patterns = [
		"CUDA out of memory",
		"out of memory",
		"OOM",
		"memory allocation failed",
		"cannot allocate memory",
		"Failed to allocate",
		"Allocation failed"
	]

	while OS.is_process_running(pid):
		# Timeout check
		if command_timeout_seconds > 0:
			var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
			if elapsed > command_timeout_seconds:
				push_error("Backend: Timeout (%ds) exceeded for '%s', killing process." % [int(command_timeout_seconds), task_name])
				OS.kill(pid)
				full_output += "[TIMEOUT] Process killed after %.0fs\n" % elapsed
				command_finished.emit(-1, full_output)
				return

		var got_output = false

		# Lire stdout
		if stdio and stdio.get_error() == OK:
			while not stdio.eof_reached():
				var line = stdio.get_line()
				if not line.is_empty():
					got_output = true
					line_count += 1
					last_output_time = Time.get_ticks_msec()
					full_output += line + "\n"
					print("[%s] %s" % [task_name, line])
					var progress_pct = _parse_progress_percent(line, task_name)
					command_progress.emit(line, progress_pct)

					# Détection OOM
					var lower_line = line.to_lower()
					for pattern in oom_patterns:
						if lower_line.contains(pattern.to_lower()):
							var oom_msg = "OOM détecté dans %s : %s" % [task_name, line.strip_edges()]
							if not oom_detected_flag:
								oom_detected.emit(task_name, oom_msg)
								error_occurred.emit(oom_msg)
								oom_detected_flag = true
							break

		# Lire stderr
		if stderr and stderr.get_error() == OK:
			while not stderr.eof_reached():
				var line = stderr.get_line()
				if not line.is_empty():
					got_output = true
					line_count += 1
					last_output_time = Time.get_ticks_msec()
					full_output += "[ERR] " + line + "\n"
					print("[%s] [ERR] %s" % [task_name, line])
					var progress_pct = _parse_progress_percent(line, task_name)
					command_progress.emit(line, progress_pct)

					var lower_line = line.to_lower()
					for pattern in oom_patterns:
						if lower_line.contains(pattern.to_lower()):
							var oom_msg = "OOM détecté dans %s : %s" % [task_name, line.strip_edges()]
							if not oom_detected_flag:
								oom_detected.emit(task_name, oom_msg)
								error_occurred.emit(oom_msg)
								oom_detected_flag = true
							break

		if not got_output:
			# Safety: if no output for 5 min, the process is likely hung even if still "running"
			if (Time.get_ticks_msec() - last_output_time) > 300000:
				push_error("Backend: No output from '%s' for 5 min, process likely hung." % task_name)
				OS.kill(pid)
				full_output += "[HUNG] Process killed (no output for 5 min)\n"
				command_finished.emit(-1, full_output)
				return
			await get_tree().create_timer(0.1).timeout

	# Récupérer le code de sortie
	var exit_code = OS.get_process_exit_code(pid)
	if exit_code != 0 and not oom_detected_flag:
		var err_msg = "Commande '%s' échouée avec code %d" % [task_name, exit_code]
		error_occurred.emit(err_msg)

	command_finished.emit(exit_code, full_output)


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

	return -1.0
