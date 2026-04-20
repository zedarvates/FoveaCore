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
		var got_output = false

		# Lire stdout
		if stdio and stdio.get_error() == OK:
			while not stdio.eof_reached():
				var line = stdio.get_line()
				if not line.is_empty():
					got_output = true
					line_count += 1
					full_output += line + "\n"
					print("[%s] %s" % [task_name, line])
					command_progress.emit(line, -1.0)  # Pourcent inconnu

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
					full_output += "[ERR] " + line + "\n"
					print("[%s] [ERR] %s" % [task_name, line])
					command_progress.emit(line, -1.0)

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
			await get_tree().create_timer(0.1).timeout

	# Récupérer le code de sortie
	var exit_code = OS.get_process_exit_code(pid)
	if exit_code != 0 and not oom_detected_flag:
		var err_msg = "Commande '%s' échouée avec code %d" % [task_name, exit_code]
		error_occurred.emit(err_msg)

	command_finished.emit(exit_code, full_output)
