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

## Run the full reconstruction pipeline using external calls
func execute_reconstruction(session: ReconstructionSession) -> void:
    if session.status != "Pre-processed" and not session.is_processed:
        # Step 1: Feature Extraction (COLMAP)
        _run_colmap_features(session)
    else:
        # Step 2: Gaussian Training (3DGS)
        _run_gaussian_training(session)

func _run_colmap_features(session: ReconstructionSession) -> void:
    var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
    var cmd: String = "%s feature_extractor --database_path %s/database.db --image_path %s/input" % [
        colmap_path, abs_path, abs_path
    ]
    
    _execute_command(cmd, "COLMAP: Feature Extraction")

func _run_gaussian_training(session: ReconstructionSession) -> void:
    var abs_path: String = ProjectSettings.globalize_path(session.output_directory)
    var cmd: String = "%s %s -s %s -m %s/output --iterations 7000" % [
        python_path, gaussiantrain_script, abs_path, abs_path
    ]
    
    _execute_command(cmd, "3DGS: Training Splats")

func _execute_command(command: String, task_name: String) -> void:
    command_started.emit(task_name)
    print("ReconstructionBackend: Executing -> ", command)
    
    # In a real GDExtension, this would use OS.execute or a background process
    # To avoid blocking Godot, we simulate the long-running execution for this UI prototype
    _simulate_command_execution(command, task_name)

func _simulate_command_execution(command: String, task_name: String) -> void:
    # This represents the asynchronous nature of the tool
    # In production, this would be replaced with actual OS.create_process or OS.execute
    await get_tree().create_timer(3.0).timeout
    command_finished.emit(0, "Command finished successfully: " + task_name)
