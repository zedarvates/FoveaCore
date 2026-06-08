@tool
extends Control

## StudioTo3DPanel — Interface éditeur pour le pipeline de reconstruction
## Version sécurisée avec preloads et connexions robustes

const _PCVisualizerScript = preload("res://addons/foveacore/scripts/reconstruction/point_cloud_visualizer.gd")
const _SplatRendererScript = preload("res://addons/foveacore/scripts/reconstruction/splat_renderer.gd")
const _PLYLoaderScript = preload("res://addons/foveacore/scripts/reconstruction/ply_loader.gd")
const _GaussianSplatScript = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

var manager: FoveaReconstructionManager = null
var current_session: ReconstructionSession = null
var _preview_manager: StudioPreviewManager = null

var _is_running: bool = false
var _animation_timer: float = 0.0
var _last_known_status: String = ""
var _last_known_phase_prefix: String = ""
var _spinner_idx: int = 0
const SPINNERS: Array[String] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

@onready var video_path_edit: LineEdit = get_node_or_null("VSplit/TopScroll/VBoxTop/VideoSource/PathEdit")
@onready var session_name_edit: LineEdit = get_node_or_null("VSplit/TopScroll/VBoxTop/SessionName/NameEdit")
@onready var mask_option: OptionButton = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/MaskingRow/MaskOption")
@onready var threshold_slider: HSlider = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/ThresholdRow/ThresholdSlider")
@onready var status_label: Label = get_node_or_null("VSplit/TopScroll/VBoxTop/Status/StatusLabel")
@onready var progress_bar: ProgressBar = get_node_or_null("VSplit/TopScroll/VBoxTop/Progress/ProgressBar")
@onready var log_text: TextEdit = get_node_or_null("VSplit/Logs/LogEdit")
@onready var stats_label: Label = get_node_or_null("VSplit/TopScroll/VBoxTop/Stats/StatsLabel")

# Preview controls
@onready var show_mask_toggle: CheckBox = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/MaskingRow/ShowMaskToggle")
@onready var roi_toggle: CheckBox = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/ROIRow/ShowROIToggle")

# Render options
@onready var aniso_toggle: CheckBox = get_node_or_null("VSplit/TopScroll/VBoxTop/RenderOptions/AnisotropicRow/AnisoToggle")
@onready var lod_toggle: CheckBox = get_node_or_null("VSplit/TopScroll/VBoxTop/RenderOptions/LODRow/LODToggle")
@onready var point_size_slider: HSlider = get_node_or_null("VSplit/TopScroll/VBoxTop/RenderOptions/PointSizeRow/PointSizeSlider")

# Boutons (optionnels via get_node_or_null pour éviter les crashs si la scène change)
@onready var browse_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/VideoSource/Browse")
@onready var extract_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/Extract")
@onready var sfm_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/Sfm")
@onready var train_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/Train")
@onready var preview_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/Preview")
@onready var run_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/Run")
@onready var auto_run_check: CheckBox = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/AutoRun")
@onready var roi_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/ROIRow/ROIButton")
@onready var save_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/HeaderBox/Save")
@onready var load_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/HeaderBox/Load")
@onready var reset_button: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/HeaderBox/Reset")

# Nouveaux champs pour les chemins
@onready var ffmpeg_path_edit: LineEdit = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/FFmpegRow/FFmpegPath")
@onready var browse_ffmpeg_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/FFmpegRow/BrowseFFmpeg")
@onready var colmap_path_edit: LineEdit = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/ColmapRow/ColmapPath")
@onready var browse_colmap_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/ColmapRow/BrowseColmap")
@onready var check_tools_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/CheckTools")

@onready var preview_rect: TextureRect = get_node_or_null("VSplit/TopScroll/VBoxTop/PreviewCenter/PreviewRect")

var floaters_detector: FloatersDetector = null
@onready var debug_mode_option: OptionButton = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/DebugRow/DebugMode")
@onready var clean_floaters_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/CleanRow/CleanFloaters")

# WorldMirror 2.0 controls
@onready var wm2_mode_check: CheckBox = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/WM2Row/WM2ModeCheck")
@onready var wm2_target_slider: HSlider = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/WM2Row/WM2TargetSlider")
@onready var wm2_target_label: Label = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/WM2Row/WM2TargetLabel")
@onready var wm2_status: Label = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/WM2Row/WM2Status")

# COLMAP controls
@onready var colmap_exhaustive_check: CheckBox = get_node_or_null("VSplit/TopScroll/VBoxTop/Settings/ColmapOptsRow/ExhaustiveCheck")

@onready var reload_ply_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/ReloadPLY")
@onready var export_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/ExportPLY")
@onready var toggle_renderer_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/ToggleRenderer")

var current_renderer: _SplatRendererScript = null  # Référence au renderer 3D actuel
var dry_run_check: CheckBox = null

func _ready() -> void:
	floaters_detector = FloatersDetector.new()
	add_child(floaters_detector)
	
	_safe_connect(floaters_detector.cleaning_started, _on_cleaning_started)
	_safe_connect(floaters_detector.cleaning_progress_updated, _on_cleaning_progress)
	_safe_connect(floaters_detector.cleaning_completed, _on_cleaning_completed)
	_safe_connect(floaters_detector.cleaning_failed, _on_cleaning_failed)
	# 1. Récupérer le manager (Autoload en jeu, Instance locale en éditeur)
	manager = get_node_or_null("/root/ReconstructionManager")
	
	if manager == null:
		# Si on est dans l'éditeur, on crée une instance locale pour que l'outil marche
		if Engine.is_editor_hint():
			manager = FoveaReconstructionManager.new()
			add_child(manager)
			_log("Editor Mode: Local Manager initialized.")
		else:
			push_error("StudioTo3DPanel: ReconstructionManager autoload introuvable !")
			return
		
	# 2. Connecter les signaux du Manager
	_safe_connect(manager.session_started, _on_session_started)
	_safe_connect(manager.session_progress_updated, _on_progress_updated)
	_safe_connect(manager.session_completed, _on_session_completed)
	_safe_connect(manager.reconstruction_failed, _on_reconstruction_failed)
	_safe_connect(manager.log_line_received, _on_log_line_received)
	
	# 3. Connecter l'UI manuellement
	_safe_connect_btn(browse_button, _on_browse_pressed)
	_safe_connect_btn(extract_button, _on_extract_pressed)
	_safe_connect_btn(sfm_button, _on_sfm_pressed)
	_safe_connect_btn(train_button, _on_train_pressed)
	_safe_connect_btn(preview_button, _on_preview_pressed)
	_safe_connect_btn(run_button, _on_run_pressed)
	_safe_connect_btn(roi_button, _on_roi_pressed)
	_safe_connect_btn(reset_button, _on_reset_pressed)
	_safe_connect_btn(reload_ply_btn, _on_reload_ply_pressed)
	_safe_connect_btn(export_btn, _on_export_pressed)
	_safe_connect_btn(toggle_renderer_btn, _on_toggle_renderer_pressed)
	
	_safe_connect_btn(browse_ffmpeg_btn, _on_browse_ffmpeg_pressed)
	_safe_connect_btn(browse_colmap_btn, _on_browse_colmap_pressed)
	_safe_connect_btn(check_tools_btn, _on_check_tools_pressed)
	_safe_connect_btn(clean_floaters_btn, _on_clean_floaters_pressed)
	
	if threshold_slider:
		threshold_slider.value_changed.connect(_on_threshold_changed)
	if mask_option:
		if mask_option.item_count == 4:
			mask_option.add_item("None")
		mask_option.item_selected.connect(_on_mask_mode_changed)
	if show_mask_toggle:
		show_mask_toggle.toggled.connect(_on_show_mask_toggled)
	if roi_toggle:
		roi_toggle.toggled.connect(_on_show_roi_toggled)
	if aniso_toggle:
		aniso_toggle.toggled.connect(_on_aniso_toggled)
	if lod_toggle:
		lod_toggle.toggled.connect(_on_lod_toggled)
	if point_size_slider:
		point_size_slider.value_changed.connect(_on_point_size_changed)

	# Dynamic UI injection
	var header_box = get_node_or_null("VSplit/TopScroll/VBoxTop/HeaderBox")
	if header_box:
		var open_folder_btn = Button.new()
		open_folder_btn.name = "OpenFolder"
		open_folder_btn.text = "Open Folder"
		open_folder_btn.pressed.connect(_on_open_folder_pressed)
		header_box.add_child(open_folder_btn)
		
	var pipeline_container = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline")
	if pipeline_container:
		dry_run_check = CheckBox.new()
		dry_run_check.name = "DryRunCheck"
		dry_run_check.text = "Dry Run (Simulate)"
		dry_run_check.button_pressed = false
		dry_run_check.toggled.connect(_on_dry_run_toggled)
		pipeline_container.add_child(dry_run_check)

	_setup_preview_manager()

	# Tooltips pour contrôles avancés
	if aniso_toggle:
		aniso_toggle.tooltip_text = "Use separate X/Y scale for each splat (anisotropic ellipses). More realistic but slightly slower."
	if lod_toggle:
		lod_toggle.tooltip_text = "Level of Detail: enlarge distant splats to reduce perceived density."
	if point_size_slider:
		point_size_slider.tooltip_text = "Base size of splat quads. Increase for larger, softer splats."
	if show_mask_toggle:
		show_mask_toggle.tooltip_text = "Overlay red tint on background areas detected by the mask."
	if roi_toggle:
		roi_toggle.tooltip_text = "Show yellow border around the Region of Interest."
	
	# Defer WM2 status check to avoid blocking _ready() on synchronous OS.execute()
	call_deferred("_update_wm2_status")
	
	_log("StudioTo3D UI Initialized (Safe Mode).")
	
	# 4. Vérifier les outils au démarrage
	call_deferred("_check_tools_and_popup", true)

func _safe_connect(sig: Signal, callable: Callable):
	if not sig.is_connected(callable):
		sig.connect(callable)

func _safe_connect_btn(btn: Button, callable: Callable):
	if btn and not btn.pressed.is_connected(callable):
		btn.pressed.connect(callable)

# --- Handlers ---

func _on_reset_pressed() -> void:
	if current_session == null:
		_perform_ui_reset()
		return

	# Créer une boîte de dialogue interactive pour confirmer l'action
	var confirm := ConfirmationDialog.new()
	confirm.title = "Reset Session & Files"
	confirm.dialog_text = "How would you like to reset the session '%s'?\n\n- CONFIRM: Erase all files on disk and reset the UI.\n- RESET UI ONLY: Reset UI inputs only, leaving files intact.\n- CANCEL: Do nothing." % current_session.session_name
	
	confirm.ok_button_text = "Delete Files & Reset"
	
	# Ajouter un bouton personnalisé pour réinitialiser uniquement l'UI
	var ui_only_btn = confirm.add_button("Reset UI Only", false, "reset_ui_only")
	
	confirm.confirmed.connect(func():
		_log("Wiping all workspace files on disk for session: " + current_session.session_name)
		manager.delete_session(current_session, true)
		_perform_ui_reset()
		confirm.queue_free()
	)
	
	confirm.custom_action.connect(func(action):
		if action == "reset_ui_only":
			_log("Resetting UI only. Files kept on disk.")
			manager.delete_session(current_session, false)
			_perform_ui_reset()
			confirm.queue_free()
	)
	
	confirm.canceled.connect(func():
		confirm.queue_free()
	)
	
	add_child(confirm)
	confirm.popup_centered(Vector2i(500, 220))

func _perform_ui_reset() -> void:
	current_session = null
	if video_path_edit: video_path_edit.text = ""
	if session_name_edit: session_name_edit.text = ""
	if progress_bar: progress_bar.value = 0
	if status_label: status_label.text = "Status: Idle"
	if log_text: log_text.text = ""
	if preview_rect: preview_rect.texture = null
	if show_mask_toggle: show_mask_toggle.button_pressed = true
	if roi_toggle: roi_toggle.button_pressed = false
	if _preview_manager: _preview_manager.on_threshold_changed(0)
	
	# Cleanup temporary preview frame
	var temp_preview_path = OS.get_user_data_dir() + "/fovea_preview.jpg"
	if FileAccess.file_exists(temp_preview_path):
		DirAccess.remove_absolute(temp_preview_path)
	
	# Nettoyer également le renderer 3D s'il y en a un actif
	if current_renderer:
		current_renderer.queue_free()
		current_renderer = null
		
	_log("Session Reset Complete.")


func _on_save_pressed() -> void:
	_ensure_session()
	if current_session:
		# Update session from UI before saving
		current_session.background_threshold = threshold_slider.value if threshold_slider else 0.95
		current_session.session_name = session_name_edit.text if session_name_edit else "new_session"
		
		var err = manager.save_session(current_session)
		if err == OK:
			_log("Session saved successfully.")
		else:
			_log("Error saving session: " + str(err))

func _on_load_pressed() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = PackedStringArray(["*.json ; Reconstruction Session"])
	dialog.file_selected.connect(func(path):
		var session = manager.load_session(path)
		if session:
			current_session = session
			_update_ui_from_session()
			_log("Session loaded: " + session.session_name)
		else:
			_log("Error loading session from: " + path)
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

func _update_ui_from_session() -> void:
	if current_session == null: return
	if video_path_edit: video_path_edit.text = current_session.video_path
	if session_name_edit: session_name_edit.text = current_session.session_name
	if threshold_slider: threshold_slider.value = current_session.background_threshold
	if status_label: status_label.text = "Status: " + current_session.status
	if colmap_exhaustive_check: colmap_exhaustive_check.button_pressed = current_session.exhaustive_matching
	if dry_run_check: dry_run_check.button_pressed = current_session.dry_run
	if _preview_manager: _preview_manager.on_threshold_changed(0)

	# Load preview if available
	if not current_session.video_path.is_empty():
		if manager and manager.processor:
			var img = await manager.processor.get_preview_frame(current_session.video_path)
			if img:
				_preview_manager.set_preview_image(img)

func _on_roi_pressed() -> void:
	if video_path_edit.text.is_empty():
		_log("Error: Select a video first to see preview.")
		return
		
	_log("Opening ROI Selector...")
	_ensure_session()
	if manager == null or manager.processor == null:
		_log("Error: Processor not ready.")
		return
	var img = await manager.processor.get_preview_frame(video_path_edit.text)
	if img == null:
		_log("Error: Could not extract preview frame (check FFmpeg).")
		return

	var painter = StudioRoiPainter.create(img)
	painter.roi_confirmed.connect(func(rect: Rect2i):
		if current_session:
			current_session.roi_rect = rect
			_log("ROI set: " + str(rect))
	)
	add_child(painter)
	painter.popup_centered()

func _on_browse_pressed() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.mp4, *.mov, *.avi, *.mkv, *.webm, *.gif ; Video Files"])
	dialog.file_selected.connect(_on_video_selected)
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

func _on_video_selected(path: String) -> void:
	if video_path_edit: video_path_edit.text = path
	if session_name_edit and session_name_edit.text.is_empty():
		session_name_edit.text = path.get_file().get_basename()
	
	_log("Vidéo sélectionnée. Génération automatique de l'aperçu...")
	_ensure_session()
	if manager == null or manager.processor == null:
		_log("Error: Processor not ready. Please check tool configuration.")
		return
	var img = await manager.processor.get_preview_frame(path)
	if img:
		_log("Aperçu généré avec succès.")
		_preview_manager.set_preview_image(img)

func _setup_preview_manager() -> void:
	_preview_manager = StudioPreviewManager.new()
	add_child(_preview_manager)
	_preview_manager.preview_rect = preview_rect
	_preview_manager.threshold_slider = threshold_slider
	_preview_manager.mask_option = mask_option
	_preview_manager.show_mask_toggle = show_mask_toggle
	_preview_manager.roi_toggle = roi_toggle
	if current_session:
		_preview_manager.session = current_session
	_preview_manager.setup(preview_rect, current_session)

func _on_threshold_changed(_value: float) -> void:
	if _preview_manager: _preview_manager.on_threshold_changed(_value)

func _on_mask_mode_changed(_index: int) -> void:
	if _preview_manager: _preview_manager.on_mask_mode_changed(_index)
	if current_session and mask_option:
		current_session.mask_mode = mask_option.get_item_text(_index)

func _on_show_mask_toggled(checked: bool) -> void:
	if _preview_manager: _preview_manager.on_show_mask_toggled(checked)

func _on_show_roi_toggled(checked: bool) -> void:
	if _preview_manager: _preview_manager.on_show_roi_toggled(checked)

func _on_aniso_toggled(checked: bool) -> void:
	if current_renderer:
		current_renderer.enable_anisotropic = checked

func _on_lod_toggled(checked: bool) -> void:
	if current_renderer:
		current_renderer.lod_enabled = checked

func _on_point_size_changed(value: float) -> void:
	if current_renderer:
		current_renderer.point_size = value

func _on_extract_pressed() -> void:
	if video_path_edit.text.is_empty():
		_log("Error: No video selected.")
		return
	_ensure_session()
	current_session.background_threshold = threshold_slider.value if threshold_slider else 0.9
	var mode = mask_option.get_item_text(mask_option.selected) if mask_option else "Smart Studio"
	_log("Phase 1: Extraction (" + mode + ")")
	manager.run_extraction(current_session, mode)

func _on_sfm_pressed() -> void:
	_ensure_session()
	_log("Phase 2: COLMAP SfM...")
	manager.run_sfm(current_session)

func _on_train_pressed() -> void:
	_ensure_session()
	_log("Phase 3: 3DGS Training...")
	manager.run_training(current_session)

func _on_reload_ply_pressed() -> void:
	if current_session == null:
		_log("Error: No session selected.")
		return
	# Ne nécessite pas que is_processed soit true, on tente de charger le PLY s'il existe
	var global_ply = ""
	var out_base = ProjectSettings.globalize_path(current_session.output_directory)

	# 1. Check WorldMirror 2.0 output: gaussians.ply at workspace root
	var wm2_ply = current_session.output_directory.path_join("gaussians.ply")
	if FileAccess.file_exists(ProjectSettings.globalize_path(wm2_ply)):
		global_ply = ProjectSettings.globalize_path(wm2_ply)
		_log("Found WorldMirror 2.0 PLY: gaussians.ply")

	# 2. Check COLMAP+3DGS output
	if global_ply.is_empty():
		var ply_path = current_session.output_directory.path_join("output/point_cloud/iteration_7000/point_cloud.ply")
		global_ply = ProjectSettings.globalize_path(ply_path)

	if not FileAccess.file_exists(global_ply):
		_log("PLY not found at standard paths. Searching output/...")
		# Chercher n'importe quel .ply dans output
		var out_dir = DirAccess.open(out_base + "/output")
		if not out_dir:
			out_dir = DirAccess.open(out_base)
		if out_dir:
			out_dir.list_dir_begin()
			var file = out_dir.get_next()
			while file != "":
				if file.ends_with(".ply"):
					global_ply = out_base + "/output/" + file
					if not FileAccess.file_exists(global_ply):
						global_ply = out_base + "/" + file
					_log("Found PLY: " + file)
					break
				file = out_dir.get_next()

	if not FileAccess.file_exists(global_ply):
		_log("❌ No PLY file found.")
		return

	_log("Loading and displaying splats...")
	
	# Load to update stats
	var gaussians = _PLYLoaderScript.load_gaussians_from_ply(global_ply)
	if gaussians and not gaussians.is_empty():
		_update_stats_label("Reloaded: %d splats" % gaussians.size())
	
	if Engine.is_editor_hint():
		var scene_root = EditorInterface.get_edited_scene_root()
		if scene_root:
			var splattable_script = load("res://addons/foveacore/scripts/fovea_splattable.gd")
			var node_name = "Splat_" + current_session.session_name
			
			var existing_node = scene_root.find_child(node_name, true, false)
			if not existing_node:
				var node = Node3D.new()
				node.name = node_name
				node.set_script(splattable_script)
				node.splat_file_path = global_ply
				scene_root.add_child(node)
				node.owner = scene_root
				_log("✅ Nœud FoveaSplattable ajouté à la scène active : " + node_name)
			else:
				existing_node.splat_file_path = global_ply
				if existing_node.has_method("_load_splats_from_ply"):
					existing_node.call("_load_splats_from_ply")
				_log("✅ Nœud FoveaSplattable existant mis à jour : " + node_name)
		else:
			_log("⚠️ Aucun nœud racine de scène active trouvé dans l'éditeur. Ouvrez une scène 3D pour ajouter/recharger le nœud.")
	else:
		var root = get_tree().root
		var node_name = "Splat_" + current_session.session_name
		var existing_node = root.find_child(node_name, true, false)
		if not existing_node:
			var node = Node3D.new()
			node.name = node_name
			node.set_script(load("res://addons/foveacore/scripts/fovea_splattable.gd"))
			node.splat_file_path = global_ply
			root.add_child(node)
			_log("✅ FoveaSplattable ajouté à get_tree().root : " + node_name)
		else:
			existing_node.splat_file_path = global_ply
			if existing_node.has_method("_load_splats_from_ply"):
				existing_node.call("_load_splats_from_ply")
			_log("✅ FoveaSplattable existant mis à jour dans get_tree().root : " + node_name)

func _ensure_session() -> void:
	# Si le manager a disparu ou n'a pas été initialisé, on tente une récupération de secours
	if manager == null:
		manager = get_node_or_null("/root/ReconstructionManager")
		if manager == null and Engine.is_editor_hint():
			manager = FoveaReconstructionManager.new()
			add_child(manager)
			_log("Manager recréé à la volée.")
	
	if current_session == null and manager != null:
		var v_path = video_path_edit.text if video_path_edit else ""
		var s_name = session_name_edit.text if session_name_edit else "NewSession"
		current_session = manager.create_new_session(v_path, s_name)
	
	if manager == null:
		_log("CRITICAL ERROR: Manager is still null. Is the plugin active?")
		return
		
	# Synchroniser les chemins si les champs existent
	if ffmpeg_path_edit: 
		ffmpeg_path_edit.text = manager.ffmpeg_path
		if not ffmpeg_path_edit.text_changed.is_connected(_on_ffmpeg_path_changed):
			ffmpeg_path_edit.text_changed.connect(_on_ffmpeg_path_changed)
			
	if colmap_path_edit:
		colmap_path_edit.text = manager.colmap_path
		if not colmap_path_edit.text_changed.is_connected(_on_colmap_path_changed):
			colmap_path_edit.text_changed.connect(_on_colmap_path_changed)

	# Sync WM2 settings (no blocking check during init)
	if current_session:
		if wm2_mode_check: wm2_mode_check.button_pressed = current_session.use_worldmirror
		if wm2_target_slider: wm2_target_slider.value = float(current_session.target_size)
		if colmap_exhaustive_check: colmap_exhaustive_check.button_pressed = current_session.exhaustive_matching
		if dry_run_check: dry_run_check.button_pressed = current_session.dry_run
		if mask_option and "mask_mode" in current_session:
			for idx in range(mask_option.item_count):
				if mask_option.get_item_text(idx) == current_session.mask_mode:
					mask_option.selected = idx
					break

	_log("StudioTo3D Session Verified.")

func _on_browse_ffmpeg_pressed() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["ffmpeg, ffmpeg.exe ; FFmpeg Executable"])
	dialog.file_selected.connect(func(path): 
		ffmpeg_path_edit.text = path
		manager.ffmpeg_path = path
		_log("FFmpeg path set to: " + path)
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

func _on_browse_colmap_pressed() -> void:
	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["colmap, colmap.exe ; COLMAP Executable"])
	dialog.file_selected.connect(func(path): 
		colmap_path_edit.text = path
		manager.colmap_path = path
		_log("COLMAP path set to: " + path)
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

func _on_check_tools_pressed() -> void:
	_log("Checking tools and auto-detecting...")
	_check_tools_and_popup(false)

func _on_ffmpeg_path_changed(new_text: String) -> void:
	manager.ffmpeg_path = new_text

func _on_colmap_path_changed(new_text: String) -> void:
	manager.colmap_path = new_text

func _on_wm2_mode_changed(checked: bool) -> void:
	_ensure_session()
	if current_session:
		current_session.use_worldmirror = checked
		if checked:
			_log("🔄 Mode: WorldMirror 2.0 (reconstruction rapide ~10s)")
			# Désactiver les boutons COLMAP inutiles en mode WM2
			if sfm_button: sfm_button.disabled = true
			if train_button: train_button.disabled = true
		else:
			_log("🔄 Mode: COLMAP + 3DGS (complet, 30-90 min)")
			if sfm_button: sfm_button.disabled = false
			if train_button: train_button.disabled = false
	_update_wm2_status()

func _on_wm2_target_changed(value: float) -> void:
	_ensure_session()
	if current_session:
		current_session.target_size = int(value)
		if wm2_target_label:
			wm2_target_label.text = "Target: %dpx" % int(value)

func _on_exhaustive_check_toggled(checked: bool) -> void:
	_ensure_session()
	if current_session:
		current_session.exhaustive_matching = checked
		_log("🔄 COLMAP Matcher: %s" % ("Exhaustive" if checked else "Sequential (Video)"))

func _update_wm2_status() -> void:
	if not wm2_status:
		return
	if StudioDependencyChecker.is_worldmirror2_ready():
		wm2_status.text = "✅ WorldMirror 2.0 ready"
		wm2_status.modulate = Color.GREEN
	else:
		wm2_status.text = "⚠ WorldMirror 2.0 not installed"
		wm2_status.modulate = Color.ORANGE
		if wm2_mode_check and wm2_mode_check.button_pressed:
			wm2_mode_check.button_pressed = false
			_log("WorldMirror 2.0 not available. Fallback to COLMAP.")

func _on_run_pressed() -> void:
	if video_path_edit and video_path_edit.text.is_empty():
		_log("Error: No video selected.")
		return
	_ensure_session()
	if manager == null:
		_log("Error: ReconstructionManager not available. Cannot run reconstruction.")
		return
	
	_log("Starting All: " + current_session.session_name)

	if current_session.use_worldmirror:
		_log("🚀 WorldMirror 2.0: Single-pass reconstruction (~2-10s)")
		_log("  Phase 1: Extract frames + mask (ffmpeg)")
		_log("  Phase 2: Feed-forward 3DGS inference (WorldMirror 2.0)")
	else:
		_log("⚠️ PERFORMANCE NOTE: Reconstruction is very GPU intensive.")
		_log("- Phase 2 (SfM) can take 2-15 mins.")
		_log("- Phase 3 (3DGS) can take 15-30 mins.")
	
	await manager.run_reconstruction(current_session)

func _on_preview_pressed() -> void:
	if current_session == null:
		_log("Error: No session available. Create or load a session first.")
		return
	var path = current_session.video_path if current_session.video_path else (video_path_edit.text if video_path_edit else "")
	if path.is_empty():
		_log("Error: No video path set.")
		return
	if manager == null or manager.processor == null:
		_log("Error: Processor not ready.")
		return
	_log("Generating preview frame...")
	var img = await manager.processor.get_preview_frame(path)
	if img:
		_preview_manager.set_preview_image(img)
		_log("Preview updated.")
	else:
		_log("Failed to generate preview.")

func _on_session_started(_name: String) -> void:
	_is_running = true
	_spinner_idx = 0
	_animation_timer = 0.0

func _process(delta: float) -> void:
	if not _is_running:
		return
	
	_animation_timer += delta
	if _animation_timer >= 0.15:
		_animation_timer = 0.0
		_update_animated_status()

func _update_animated_status() -> void:
	if not status_label or _last_known_status.is_empty():
		return
	_spinner_idx = (_spinner_idx + 1) % SPINNERS.size()
	var spinner := SPINNERS[_spinner_idx]
	status_label.text = "%s%s %s" % [_last_known_phase_prefix, spinner, _last_known_status]

func _on_progress_updated(progress: float) -> void:
	if progress_bar: 
		progress_bar.value = progress
		
	var phase_prefix := ""
	if progress < 33.0:
		phase_prefix = "[Phase 1/3] "
	elif progress >= 33.0 and progress < 66.0:
		phase_prefix = "[Phase 2/3] "
	elif progress >= 66.0 and progress < 100.0:
		phase_prefix = "[Phase 3/3] "
	else:
		phase_prefix = "[Terminé] "

	var status_str := current_session.status if current_session else "Running..."
	_last_known_status = status_str
	_last_known_phase_prefix = phase_prefix
	_is_running = progress < 100.0

	if not _is_running:
		if status_label: 
			status_label.text = phase_prefix + status_str
	else:
		_update_animated_status()
		
	_log("Progress: %.1f%% - %s" % [progress, status_str])
	
	# Afficher des messages informatifs lors de la transition des phases
	if progress >= 33.0 and progress < 35.0:
		_log("Phase 1 (Extraction & Masquage) terminée avec succès.")
	elif progress >= 66.0 and progress < 70.0:
		_log("Phase 2 (Géométrie/SfM) terminée avec succès.")
	elif progress >= 100.0:
		_log("Pipeline complet terminé avec succès !")

func _on_session_completed(_session: ReconstructionSession) -> void:
	_is_running = false
	_log("✅ Reconstruction terminée avec succès !")
	if status_label: status_label.text = "[Terminé] Finished"
	if progress_bar: progress_bar.value = 100.0
	
	# Ouvrir le dossier sur le système de fichiers (Task 34)
	var global_dir := ProjectSettings.globalize_path(_session.output_directory)
	_log("Ouverture du dossier de sortie : " + global_dir)
	OS.shell_open(global_dir)
	
	# Insertion automatique dans la scène active de l'éditeur
	if Engine.is_editor_hint():
		var scene_root = EditorInterface.get_edited_scene_root()
		if scene_root:
			var splat_path := _session.splat_data_path
			if splat_path.is_empty():
				splat_path = _session.output_directory.path_join("output/" + _session.session_name + ".ply")
				
			var splattable_script = load("res://addons/foveacore/scripts/fovea_splattable.gd")
			var node_name = "Splat_" + _session.session_name
			
			# Vérifier si un nœud porte déjà ce nom pour éviter les doublons
			var existing_node = scene_root.find_child(node_name, true, false)
			if not existing_node:
				var node = Node3D.new()
				node.name = node_name
				node.set_script(splattable_script)
				node.splat_file_path = splat_path
				scene_root.add_child(node)
				
				# Très important dans l'éditeur Godot : définir l'owner sur la racine de la scène
				# pour que le nœud apparaisse dans l'arborescence et soit sauvegardé dans la scène (.tscn)
				node.owner = scene_root
				_log("✅ Nœud FoveaSplattable ajouté automatiquement à la scène active : " + node_name)
			else:
				existing_node.splat_file_path = splat_path
				_log("✅ Chemin du nœud FoveaSplattable existant mis à jour : " + node_name)
		else:
			_log("⚠️ Aucun nœud racine de scène active trouvé dans l'éditeur. Ouvrez une scène 3D pour ajouter automatiquement le nœud.")
	
	# Chargement automatique du résultat
	_log("Ouverture automatique de la prévisualisation 3D...")
	_on_preview_pressed()

func _on_reconstruction_failed(reason: String) -> void:
	_is_running = false
	_log("❌ ERREUR: " + reason)
	if status_label: status_label.text = "Status: Failed"

func _log(message: String) -> void:
	if log_text:
		log_text.text += "[%s] %s\n" % [Time.get_time_string_from_system(), message]
		# Forcer le scroll vers le bas en déplaçant le curseur
		log_text.set_caret_line(log_text.get_line_count())
		log_text.scroll_vertical = log_text.get_line_count() * 20.0 # Approximation

func _on_clean_floaters_pressed() -> void:
	if current_session == null:
		_log("Error: No session available. Run extraction first.")
		return
	
	var workspace_path = ProjectSettings.globalize_path(current_session.output_directory)
	var splat_file_path = workspace_path + "/point_cloud/points.ply"
	if not FileAccess.file_exists(splat_file_path):
		splat_file_path = workspace_path + "/splats.ply"
		
	if not FileAccess.file_exists(splat_file_path) and not current_session.splat_data_path.is_empty():
		var session_splat_path = ProjectSettings.globalize_path(current_session.splat_data_path)
		if FileAccess.file_exists(session_splat_path):
			splat_file_path = session_splat_path
			
	if not FileAccess.file_exists(splat_file_path):
		_log("Error: No splat file (.ply) found in the workspace. Please complete Phase 3 (Training) or load a model first.")
		return
	
	_log("Analyzing workspace for floating artifacts: " + workspace_path)
	
	var result = floaters_detector.analyze_workspace(workspace_path)
	if result.is_empty():
		_log("Error: Could not analyze workspace.")
		return
	
	_log("Floaters Report:")
	_log(floaters_detector.get_floating_report())
	
	if result["floating_count"] > 0:
		_log("Starting automatic cleanup...")
		floaters_detector.remove_floating_splats(workspace_path)
	else:
		_log("No floaters detected. Model is clean!")

func _on_cleaning_started(total: int) -> void:
	_log("Cleaning started: %d floating splats will be removed" % total)

func _on_cleaning_progress(current: int, total: int) -> void:
	_log("Cleaning progress: %d/%d" % [current, total])

func _on_cleaning_completed(removed: int) -> void:
	_log("Cleaning completed: %d splats removed successfully!" % removed)

func _on_cleaning_failed(reason: String) -> void:
	_log("Cleaning failed: " + reason)

func _on_debug_mode_changed(index: int) -> void:
	_log("Debug mode set to: %d" % index)

func _on_toggle_renderer_pressed() -> void:
	if current_renderer:
		current_renderer.visible = not current_renderer.visible
		_log("Renderer visibility: %s" % ("shown" if current_renderer.visible else "hidden"))
	else:
		_log("No active renderer to toggle.")

func _on_export_pressed() -> void:
	if current_session == null:
		_log("Error: No session active. Load or run a session first.")
		return

	# Find the source PLY file in the workspace
	var global_ply := ""
	var out_base := ProjectSettings.globalize_path(current_session.output_directory)

	# Check WorldMirror 2.0 output: gaussians.ply at workspace root
	var wm2_ply = current_session.output_directory.path_join("gaussians.ply")
	if FileAccess.file_exists(ProjectSettings.globalize_path(wm2_ply)):
		global_ply = ProjectSettings.globalize_path(wm2_ply)
	else:
		var ply_path = current_session.output_directory.path_join("output/point_cloud/iteration_7000/point_cloud.ply")
		global_ply = ProjectSettings.globalize_path(ply_path)

	if not FileAccess.file_exists(global_ply):
		# Fallback: search for any .ply in workspace
		var out_dir = DirAccess.open(out_base + "/output")
		if not out_dir:
			out_dir = DirAccess.open(out_base)
		if out_dir:
			out_dir.list_dir_begin()
			var file = out_dir.get_next()
			while file != "":
				if file.ends_with(".ply"):
					global_ply = out_base + "/output/" + file
					if not FileAccess.file_exists(global_ply):
						global_ply = out_base + "/" + file
					break
				file = out_dir.get_next()

	if not FileAccess.file_exists(global_ply):
		_log("❌ Cannot export: No reconstructed PLY file found in the workspace yet. Run reconstruction first.")
		return

	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([
		"*.ply ; Standard PLY Gaussian Splats",
		"*.fovea ; Fovea Engine Binary Asset"
	])
	dialog.title = "Export Reconstruction As..."
	dialog.file_selected.connect(func(path: String):
		var ext = path.get_extension().to_lower()
		if ext.is_empty():
			path = path + ".ply"
		_perform_export(global_ply, path)
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

func _perform_export(source_ply: String, dest_path: String) -> void:
	var ext = dest_path.get_extension().to_lower()
	_log("Exporting to %s..." % ext.to_upper())
	
	# Load the gaussians from the source PLY file
	var gaussians = _PLYLoaderScript.load_gaussians_from_ply(source_ply)
	if gaussians == null or gaussians.is_empty():
		_log("❌ Export failed: Could not parse source PLY file.")
		return
		
	if ext == "ply":
		# Save as standard PLY using the SplatRenderer export logic
		var temp_renderer = _SplatRendererScript.new()
		temp_renderer.load_splats(gaussians)
		var err = temp_renderer.export_to_ply(dest_path)
		temp_renderer.queue_free()
		if err == OK:
			_log("✅ Export completed: Standard PLY saved to %s" % dest_path)
		else:
			_log("❌ Export failed: Error writing PLY file.")
	elif ext == "fovea":
		# Save as Fovea Engine Binary format using FoveaAssetWriter
		const FoveaAssetWriterScript = preload("res://addons/foveacore/scripts/fovea_asset_writer.gd")
		var style = current_session.style if "style" in current_session else null
		var success = FoveaAssetWriterScript.write_fovea_asset(dest_path, gaussians, null, style, {
			"session": current_session.session_name,
			"exported_by": "Fovea StudioTo3D",
			"timestamp": Time.get_unix_time_from_system()
		})
		if success:
			_log("✅ Export completed: .fovea asset saved to %s" % dest_path)
		else:
			_log("❌ Export failed: Error writing .fovea asset.")
	else:
		_log("❌ Export failed: Unsupported extension .%s" % ext)

# --- SplatRenderer Stats Handlers ---

func _on_render_updated(instance_count: int) -> void:
	_update_stats_label("Instances: %d" % instance_count)

func _on_sorting_completed(elapsed_ms: float) -> void:
	_update_stats_label("Sort: %d ms" % elapsed_ms)

func _on_memory_reported(bytes: int) -> void:
	var mb = bytes / (1024.0 * 1024.0)
	_update_stats_label("Memory: %.1f MB" % mb)

func _input(event: InputEvent) -> void:
	# Raccourcis globaux (même sans focus)
	if not is_inside_tree() or not visible:
		return
	# Ne pas interférer avec les contrôles de texte
	if event is InputEventKey and event.pressed:
		var focus_owner = get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return
		match event.keycode:
			KEY_R:
				if reload_ply_btn and reload_ply_btn.visible and is_instance_valid(reload_ply_btn):
					_on_reload_ply_pressed()
			KEY_E:
				if export_btn and export_btn.visible and is_instance_valid(export_btn):
					_on_export_pressed()
			KEY_T:
				if toggle_renderer_btn and toggle_renderer_btn.visible and is_instance_valid(toggle_renderer_btn):
					_on_toggle_renderer_pressed()

func _on_open_folder_pressed() -> void:
	_ensure_session()
	if current_session:
		var global_dir := ProjectSettings.globalize_path(current_session.output_directory)
		if not DirAccess.dir_exists_absolute(global_dir):
			DirAccess.make_dir_recursive_absolute(global_dir)
		_log("Opening workspace folder: " + global_dir)
		OS.shell_open(global_dir)

func _on_dry_run_toggled(checked: bool) -> void:
	_ensure_session()
	if current_session:
		current_session.dry_run = checked
		_log("Dry Run mode: %s" % ("Enabled" if checked else "Disabled"))

func _on_log_line_received(line: String) -> void:
	if log_text:
		log_text.text += line + "\n"
		# Force scroll down
		log_text.set_caret_line(log_text.get_line_count())
		log_text.scroll_vertical = log_text.get_line_count() * 20.0

func _check_tools_and_popup(at_startup: bool = false) -> void:
	var results = manager.check_tools()
	
	if ffmpeg_path_edit: ffmpeg_path_edit.text = manager.ffmpeg_path
	if colmap_path_edit: colmap_path_edit.text = manager.colmap_path
	
	var ffmpeg_info = results.get("ffmpeg", {})
	var colmap_info = results.get("colmap", {})
	
	var ffmpeg_ok: bool = ffmpeg_info.get("found", false) if ffmpeg_info is Dictionary else false
	var colmap_ok: bool = colmap_info.get("found", false) if colmap_info is Dictionary else false
	
	if ffmpeg_ok and colmap_ok:
		if not at_startup:
			_log("✅ All tools found and verified.")
		return
	
	# Show AcceptDialog popup
	var dialog = AcceptDialog.new()
	dialog.title = "Warning: Missing External Tools"
	dialog.custom_minimum_size = Vector2i(550, 200)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	
	var label = Label.new()
	label.text = "Some required external tools could not be found. Please check paths in Settings."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	if not ffmpeg_ok:
		var row = HBoxContainer.new()
		var tool_lbl = Label.new()
		tool_lbl.text = "• FFmpeg is missing"
		tool_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(tool_lbl)
		
		var download_btn = Button.new()
		download_btn.text = "Download FFmpeg"
		download_btn.pressed.connect(func(): OS.shell_open("https://ffmpeg.org/download.html"))
		row.add_child(download_btn)
		vbox.add_child(row)
		_log("❌ FFmpeg NOT FOUND. Download from: https://ffmpeg.org/download.html")
		
	if not colmap_ok:
		var row = HBoxContainer.new()
		var tool_lbl = Label.new()
		tool_lbl.text = "• COLMAP is missing"
		tool_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(tool_lbl)
		
		var download_btn = Button.new()
		download_btn.text = "Download COLMAP"
		download_btn.pressed.connect(func(): OS.shell_open("https://colmap.github.io/install.html"))
		row.add_child(download_btn)
		vbox.add_child(row)
		_log("❌ COLMAP NOT FOUND. Download from: https://colmap.github.io/install.html")
		
	dialog.add_child(vbox)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _update_stats_label(text: String) -> void:
	if stats_label:
		stats_label.text = "Stats: " + text
