extends Node
class_name ReconstructionBackend

## ReconstructionBackend — Handles external tool execution (COLMAP, 3DGS, Python)
## Executes commands in the background and reports progress/errors

signal command_started(command: String)
signal command_finished(status: int, output: String)
signal error_occurred(message: String)

## Path to external dependencies (can be configured in project settings)
@export var colmap_path: String = "colmap" # Default assumes it's in PATH
@export var python_path: String = "python"
@export var gaussiantrain_script: String = "train.py"
@export var star_bridge_script: String = "star_bridge.py" # InSpatio-World path

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
    
    # Exécution réelle via OS.create_process
    var pid = OS.create_process(executable, args)
    
    if pid == -1:
        var err_msg = "Échec du lancement : " + task_name + " (Vérifiez le chemin : " + executable + ")"
        error_occurred.emit(err_msg)
        command_finished.emit(1, "Failed to start")
        return

    # On surveille le process de manière asynchrone
    _watch_process(pid, task_name)

func _watch_process(pid: int, task_name: String) -> void:
    # On utilise un timer pour vérifier périodiquement si le process tourne toujours
    while OS.is_process_running(pid):
        await get_tree().create_timer(1.0).timeout
    
	# Note: En 4.x, on ne peut pas facilement récupérer l'exit code d'un process détaché.
    # Pour un outil pro, on utiliserait une GDExtension pour un meilleur contrôle des pipes.
    command_finished.emit(0, "Command finished: " + task_name)
