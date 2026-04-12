@tool
extends Control

## StudioTo3DPanel — Interface éditeur pour le pipeline de reconstruction
## Version sécurisée avec preloads et connexions robustes

const _PCVisualizerScript = preload("res://addons/foveacore/scripts/reconstruction/point_cloud_visualizer.gd")

var manager: FoveaReconstructionManager = null
var current_session: ReconstructionSession = null

@onready var video_path_edit: LineEdit = $VBox/VideoSource/PathEdit
@onready var session_name_edit: LineEdit = $VBox/SessionName/NameEdit
@onready var mask_option: OptionButton = $VBox/Settings/MaskingRow/MaskOption
@onready var threshold_slider: HSlider = $VBox/Settings/ThresholdRow/ThresholdSlider
@onready var status_label: Label = $VBox/Status/StatusLabel
@onready var progress_bar: ProgressBar = $VBox/Progress/ProgressBar
@onready var log_text: TextEdit = $VBox/Logs/LogEdit

# Boutons (optionnels via get_node_or_null pour éviter les crashs si la scène change)
@onready var browse_button: Button = get_node_or_null("VBox/VideoSource/Browse")
@onready var extract_button: Button = get_node_or_null("VBox/Pipeline/Extract")
@onready var sfm_button: Button = get_node_or_null("VBox/Pipeline/SfM")
@onready var train_button: Button = get_node_or_null("VBox/Pipeline/Train")
@onready var preview_button: Button = get_node_or_null("VBox/Pipeline/Preview")
@onready var run_button: Button = get_node_or_null("VBox/Pipeline/Run")
@onready var auto_run_check: CheckBox = get_node_or_null("VBox/Pipeline/AutoRun")
@onready var roi_button: Button = get_node_or_null("VBox/Settings/ROIRow/ROIButton")
@onready var reset_button: Button = get_node_or_null("VBox/HeaderBox/Reset")

# Nouveaux champs pour les chemins
@onready var ffmpeg_path_edit: LineEdit = get_node_or_null("VBox/Settings/FFmpegRow/FFmpegPath")
@onready var browse_ffmpeg_btn: Button = get_node_or_null("VBox/Settings/FFmpegRow/BrowseFFmpeg")
@onready var colmap_path_edit: LineEdit = get_node_or_null("VBox/Settings/ColmapRow/ColmapPath")
@onready var browse_colmap_btn: Button = get_node_or_null("VBox/Settings/ColmapRow/BrowseColmap")
@onready var check_tools_btn: Button = get_node_or_null("VBox/Settings/CheckTools")

func _ready() -> void:
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
	
	_safe_connect_btn(browse_ffmpeg_btn, _on_browse_ffmpeg_pressed)
	_safe_connect_btn(browse_colmap_btn, _on_browse_colmap_pressed)
	_safe_connect_btn(check_tools_btn, _on_check_tools_pressed)
	
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
	_log("Session Reset.")

func _on_roi_pressed() -> void:
	if video_path_edit.text.is_empty():
		_log("Error: Select a video first to see preview.")
		return
		
	_log("Opening ROI Selector...")
	var img = manager.processor.get_preview_frame(video_path_edit.text)
	if img == null:
		_log("Error: Could not extract preview frame (check FFmpeg).")
		return
		
	_show_roi_dialog(img)

func _show_roi_dialog(img: Image) -> void:
	var popup = AcceptDialog.new()
	popup.title = "Paint Region of Interest (ROI)"
	popup.size = Vector2i(1200, 850)
	popup.get_label().hide()
	
	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	popup.add_child(main_vbox)
	
	# --- Toolbar ---
	var toolbar = HBoxContainer.new()
	main_vbox.add_child(toolbar)
	
	var mode_btn = OptionButton.new()
	mode_btn.add_item("🖌️ Paint (Add)", 0)
	mode_btn.add_item("🧽 Eraser (Remove)", 1)
	toolbar.add_child(mode_btn)
	
	toolbar.add_child(VSeparator.new())
	var size_label = Label.new()
	size_label.text = "Brush Size: "
	toolbar.add_child(size_label)
	var size_slider = HSlider.new()
	size_slider.min_value = 5
	size_slider.max_value = 100
	size_slider.value = 30
	size_slider.custom_minimum_size = Vector2(150, 0)
	toolbar.add_child(size_slider)
	
	var reset_btn = Button.new()
	reset_btn.text = "🗑️ Clear All"
	toolbar.add_child(reset_btn)
	
	# --- Drawing Area ---
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	var container = Control.new()
	container.custom_minimum_size = Vector2(img.get_width(), img.get_height())
	scroll.add_child(container)
	
	# Background Image
	var tex = ImageTexture.create_from_image(img)
	var rect_display = TextureRect.new()
	rect_display.texture = tex
	rect_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect_display.mouse_filter = Control.MOUSE_FILTER_STOP
	container.add_child(rect_display)
	
	# Mask Overlay (The "Paint" Layer)
	var mask_img = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	mask_img.fill(Color(0, 0, 0, 0)) # Start empty
	var mask_tex = ImageTexture.create_from_image(mask_img)
	
	var mask_display = TextureRect.new()
	mask_display.texture = mask_tex
	mask_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mask_display.modulate = Color(0, 1, 0, 0.5) # Semi-transparent green
	mask_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(mask_display)
	
	# --- Painting Logic ---
	var is_drawing = false
	var last_pos = Vector2.ZERO
	
	var draw_brush = func(pos: Vector2, erase: bool):
		var center = Vector2i(pos)
		var r = int(size_slider.value)
		var color = Color(0, 0, 0, 0) if erase else Color(1, 1, 1, 1)
		
		# Software brush on Image
		for y in range(-r, r):
			for x in range(-r, r):
				if x*x + y*y <= r*r:
					var px = center.x + x
					var py = center.y + y
					if px >= 0 and px < mask_img.get_width() and py >= 0 and py < mask_img.get_height():
						mask_img.set_pixel(px, py, color)
		mask_tex.update(mask_img)
	
	rect_display.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			is_drawing = event.pressed
			if is_drawing:
				draw_brush.call(event.position, mode_btn.selected == 1)
		elif event is InputEventMouseMotion and is_drawing:
			draw_brush.call(event.position, mode_btn.selected == 1)
	)
	
	reset_btn.pressed.connect(func():
		mask_img.fill(Color(0,0,0,0))
		mask_tex.update(mask_img)
	)
	
	popup.confirmed.connect(func():
		_ensure_session()
		# Find the bounding box of the painted area
		var used_rect = mask_img.get_used_rect()
		if used_rect.size.x < 10:
			current_session.roi_rect = Rect2i(0, 0, img.get_width(), img.get_height())
			_log("ROI Reset: No area painted.")
		else:
			current_session.roi_rect = used_rect
			_log("ROI Painted Area set: " + str(used_rect))
		popup.queue_free()
	)
	
	add_child(popup)
	popup.popup_centered()

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
	# Chargement automatique de l'aperçu pour la ROI
	var img = await manager.processor.get_preview_frame(path)
	if img:
		_log("Aperçu généré avec succès.")

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

func _on_preview_pressed() -> void:
	if current_session == null or not current_session.is_processed:
		_log("Error: No processed session.")
		return
	_log("Spawning 3D Preview...")
	var visualizer = _PCVisualizerScript.new()
	visualizer.name = "Preview_" + current_session.session_name
	get_tree().root.add_child(visualizer)
	visualizer._setup_multimesh(5000)
	visualizer._populate_points(null, {"vertex_count": 5000, "has_color": true})

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

func _on_run_pressed() -> void:
	if video_path_edit and video_path_edit.text.is_empty():
		_log("Error: No video selected.")
		return
	_ensure_session()
	
	_log("Starting All: " + current_session.session_name)
	_log("⚠️ PERFORMANCE NOTE: Reconstruction is very GPU intensive.")
	_log("- Phase 2 (SfM) can take 2-15 mins. UI may appear frozen.")
	_log("- Phase 3 (3DGS) can take 15-30 mins.")
	
	manager.run_reconstruction(current_session)

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
		log_text.scroll_vertical = INF
