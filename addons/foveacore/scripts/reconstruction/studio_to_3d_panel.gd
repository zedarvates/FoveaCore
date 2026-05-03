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

@onready var reload_ply_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/ReloadPLY")
@onready var export_ply_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/ExportPLY")
@onready var toggle_renderer_btn: Button = get_node_or_null("VSplit/TopScroll/VBoxTop/Pipeline/ToggleRenderer")

var current_renderer: _SplatRendererScript = null  # Référence au renderer 3D actuel

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
	_safe_connect(manager.session_progress_updated, _on_progress_updated)
	_safe_connect(manager.session_completed, _on_session_completed)
	_safe_connect(manager.reconstruction_failed, _on_reconstruction_failed)
	
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
	_safe_connect_btn(export_ply_btn, _on_export_ply_pressed)
	_safe_connect_btn(toggle_renderer_btn, _on_toggle_renderer_pressed)
	
	_safe_connect_btn(browse_ffmpeg_btn, _on_browse_ffmpeg_pressed)
	_safe_connect_btn(browse_colmap_btn, _on_browse_colmap_pressed)
	_safe_connect_btn(check_tools_btn, _on_check_tools_pressed)
	_safe_connect_btn(clean_floaters_btn, _on_clean_floaters_pressed)
	
	if threshold_slider:
		threshold_slider.value_changed.connect(_on_threshold_changed)
	if mask_option:
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
	_log("StudioTo3D UI Initialized (Safe Mode).")
	
	# 4. Vérifier les outils au démarrage
	var results = manager.check_tools()
	if results["ffmpeg"]:
		_log("FFmpeg found: " + manager.ffmpeg_path)
	else:
		_log("WARNING: FFmpeg not found. Please check paths in Settings.")

func _safe_connect(sig: Signal, callable: Callable):
	if not sig.is_connected(callable):
		sig.connect(callable)

func _safe_connect_btn(btn: Button, callable: Callable):
	if btn and not btn.pressed.is_connected(callable):
		btn.pressed.connect(callable)

# --- Handlers ---

func _on_reset_pressed() -> void:
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
	_log("Session Reset.")

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
	dialog.filters = PackedStringArray(["*.tres ; Reconstruction Session"])
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
	var img = manager.processor.get_preview_frame(video_path_edit.text)
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
	dialog.filters = PackedStringArray(["*.mp4, *.mov, *.avi ; Video Files"])
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

	# Nettoyer l'ancien renderer si présent
	if current_renderer:
		current_renderer.queue_free()

	# Charger et afficher
	var gaussians = _PLYLoaderScript.load_gaussians_from_ply(global_ply)
	if gaussians == null or gaussians.is_empty():
		_log("❌ Failed to load gaussians from PLY")
		return

	var renderer = _SplatRendererScript.new()
	renderer.name = "SplatPreview_" + current_session.session_name
	get_tree().root.add_child(renderer)
	renderer.load_splats(gaussians)

	renderer.render_updated.connect(_on_render_updated)
	renderer.sorting_completed.connect(_on_sorting_completed)
	renderer.memory_usage_reported.connect(_on_memory_reported)

	current_renderer = renderer

	var stats = renderer.get_statistics()
	if not stats.is_empty():
		var center = stats.get("center", Vector3.ZERO)
		_update_stats_label("Reloaded: %d splats" % gaussians.size())

	_log("✅ Reloaded %d splats." % gaussians.size())

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

	# Sync WM2 settings
	if current_session:
		if wm2_mode_check: wm2_mode_check.button_pressed = current_session.use_worldmirror
		if wm2_target_slider: wm2_target_slider.value = float(current_session.target_size)
		_on_wm2_mode_changed(current_session.use_worldmirror)

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
	var results = manager.check_tools()
	if ffmpeg_path_edit: ffmpeg_path_edit.text = manager.ffmpeg_path
	if colmap_path_edit: colmap_path_edit.text = manager.colmap_path
	
	if results["ffmpeg"] and results["colmap"]:
		_log("✅ All tools found and verified.")
	else:
		if not results["ffmpeg"]: _log("❌ FFmpeg NOT FOUND.")
		if not results["colmap"]: _log("❌ COLMAP NOT FOUND.")

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

func _update_wm2_status() -> void:
	if not wm2_status:
		return
	var checker = StudioDependencyChecker.new()
	if checker.is_worldmirror2_ready():
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

func _on_progress_updated(progress: float) -> void:
	if progress_bar: progress_bar.value = progress
	if status_label: status_label.text = "Status: " + current_session.status
	_log("Progress: %.1f%% - %s" % [progress, current_session.status])

func _on_session_completed(_session: ReconstructionSession) -> void:
	_log("✅ Reconstruction terminée avec succès !")
	if status_label: status_label.text = "Status: Finished"
	if progress_bar: progress_bar.value = 100.0
	
	# Chargement automatique du résultat
	_log("Ouverture automatique de la prévisualisation 3D...")
	_on_preview_pressed()

func _on_reconstruction_failed(reason: String) -> void:
	_log("❌ ERREUR: " + reason)
	if status_label: status_label.text = "Status: Failed"

func _log(message: String) -> void:
	if log_text:
		log_text.text += "[%s] %s\n" % [Time.get_time_string_from_system(), message]
		# Forcer le scroll vers le bas en déplaçant le curseur
		log_text.set_caret_line(log_text.get_line_count())
		log_text.scroll_vertical = log_text.get_line_count() * 20.0 # Approximation

func _on_session_progress_updated(progress: float) -> void:
	if progress_bar:
		progress_bar.value = progress
	if progress >= 33.0 and progress < 40.0:
		_log("Phase 1 (Extraction & Masquage) terminée successfully.")
	elif progress >= 55.0 and progress < 70.0:
		_log("Phase 2 (Géométrie/SfM) terminée.")
	elif progress >= 100.0:
		_log("Pipeline complet terminé avec succès !")

func _on_clean_floaters_pressed() -> void:
	if current_session == null:
		_log("Error: No session available. Run extraction first.")
		return
	
	var workspace_path = ProjectSettings.globalize_path(current_session.output_directory)
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

func _on_export_ply_pressed() -> void:
	if current_renderer == null:
		_log("Error: No renderer active. Load a PLY first.")
		return

	var dialog = FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.ply ; Gaussian Splat PLY"])
	dialog.title = "Export Splats to PLY"
	dialog.file_selected.connect(func(path):
		var err = current_renderer.export_to_ply(path)
		if err == OK:
			_log("✅ Exported splats to: %s" % path)
		else:
			_log("❌ Export failed: %s" % path)
	)
	add_child(dialog)
	dialog.popup_centered(Vector2i(800, 600))

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
				if export_ply_btn and export_ply_btn.visible and is_instance_valid(export_ply_btn):
					_on_export_ply_pressed()
			KEY_T:
				if toggle_renderer_btn and toggle_renderer_btn.visible and is_instance_valid(toggle_renderer_btn):
					_on_toggle_renderer_pressed()

func _update_stats_label(text: String) -> void:
	if stats_label:
		stats_label.text = "Stats: " + text
