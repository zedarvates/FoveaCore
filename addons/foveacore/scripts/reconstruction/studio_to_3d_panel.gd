@tool
extends Control

## StudioTo3DPanel — Editor UI for the reconstruction pipeline

var manager: ReconstructionManager = null
var current_session: ReconstructionSession = null

@onready var video_path_edit: LineEdit = $VBox/VideoSource/PathEdit
@onready var session_name_edit: LineEdit = $VBox/SessionName/NameEdit
@onready var mask_option: OptionButton = $VBox/Settings/MaskingRow/MaskOption
@onready var threshold_slider: HSlider = $VBox/Settings/ThresholdRow/ThresholdSlider
@onready var status_label: Label = $VBox/Status/StatusLabel
@onready var progress_bar: ProgressBar = $VBox/Progress/ProgressBar
@onready var log_text: TextEdit = $VBox/Logs/LogEdit
@onready var preview_button: Button = $VBox/Pipeline/Preview
@onready var roi_button: Button = $VBox/Settings/ROIRow/ROIButton
@onready var reset_button: Button = $VBox/HeaderBox/Reset

func _ready() -> void:
    manager = ReconstructionManager.new()
    add_child(manager)
    manager.session_progress_updated.connect(_on_progress_updated)
    manager.session_completed.connect(_on_session_completed)
    roi_button.pressed.connect(_on_roi_pressed)

func _on_reset_pressed() -> void:
    current_session = null
    video_path_edit.text = ""
    session_name_edit.text = ""
    progress_bar.value = 0
    status_label.text = "Status: Idle"
    log_text.text = ""
    _log("Session Reset. Ready for new input.")

func _on_roi_pressed() -> void:
    _log("ROI: Lasso drawing mode activated (Placeholder).")
    _log("Tip: For now, default focus ROI is applied around center.")
    _ensure_session()
    # Simulate a center ROI crop
    current_session.roi_rect = Rect2i(100, 100, 800, 800) 

func _on_browse_pressed() -> void:
    var dialog = FileDialog.new()
    dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    dialog.access = FileDialog.ACCESS_FILESYSTEM
    dialog.filters = ["*.mp4, *.mov, *.avi ; Video Files"]
    dialog.file_selected.connect(_on_video_selected)
    add_child(dialog)
    dialog.popup_centered(Vector2i(800, 600))

func _on_video_selected(path: String) -> void:
    video_path_edit.text = path
    if session_name_edit.text.is_empty():
        session_name_edit.text = path.get_file().get_basename()

func _on_extract_pressed() -> void:
    if video_path_edit.text.is_empty():
        _log("Error: No video selected.")
        return
    
    _ensure_session()
    current_session.background_threshold = threshold_slider.value
    var mode = mask_option.get_item_text(mask_option.selected)
    _log("Phase 1: Starting extraction with mode: " + mode)
    manager.run_extraction(current_session, mode)

func _on_sfm_pressed() -> void:
    _ensure_session()
    _log("Phase 2: Starting COLMAP SfM...")
    manager.run_sfm(current_session)

func _on_train_pressed() -> void:
    _ensure_session()
    _log("Phase 3: Starting 3DGS Training...")
    manager.run_training(current_session)

func _on_preview_pressed() -> void:
    if current_session == null or not current_session.is_processed:
        _log("Error: No processed session to preview.")
        return
    
    _log("Spawning 3D Preview in scene...")
    var visualizer = PointCloudVisualizer.new()
    visualizer.name = "Preview_" + current_session.session_name
    get_tree().root.get_child(0).add_child(visualizer)
    
    # In a real tool, it would load the PLY from the results folder
    visualizer._setup_multimesh(5000) # Quick preview
    visualizer._populate_points(null, {"vertex_count": 5000, "has_color": true})

func _ensure_session() -> void:
    if current_session == null:
        current_session = manager.create_new_session(video_path_edit.text, session_name_edit.text)

func _on_run_pressed() -> void:
    if video_path_edit.text.is_empty():
        _log("Error: No video selected.")
        return
    
    current_session = manager.create_new_session(video_path_edit.text, session_name_edit.text)
    _log("Starting session: " + current_session.session_name)
    manager.run_reconstruction(current_session)

func _on_progress_updated(progress: float) -> void:
    progress_bar.value = progress
    status_label.text = "Status: " + current_session.status
    _log("Progress: %.1f%% - %s" % [progress, current_session.status])

func _on_session_completed(session: ReconstructionSession) -> void:
    _log("Reconstruction Complete!")
    _log("Low-poly mesh: " + session.low_poly_mesh_path)
    _log("Gaussian Splats: " + session.splat_data_path)
    status_label.text = "Status: Finished"

func _log(message: String) -> void:
    log_text.text += "[%s] %s\n" % [Time.get_time_string_from_system(), message]
    log_text.scroll_vertical = INF
