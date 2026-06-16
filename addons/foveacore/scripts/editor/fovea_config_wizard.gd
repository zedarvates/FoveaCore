@tool
extends AcceptDialog

# FoveaConfigWizard — Initial Setup Wizard for FoveaEngine external dependencies

var vbox: VBoxContainer
var info_label: Label
var ffmpeg_row: HBoxContainer
var colmap_row: HBoxContainer
var python_row: HBoxContainer

func _ready() -> void:
	title = "FoveaEngine Initial Setup Wizard 🔷"
	size = Vector2i(500, 320)
	
	vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(vbox)
	
	info_label = Label.new()
	info_label.text = "Welcome to FoveaEngine! To use the StudioTo3D reconstruction pipeline, we need to locate external tools on your system."
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(info_label)
	
	vbox.add_child(HSeparator.new())
	
	# Status Rows
	ffmpeg_row = _create_status_row("FFmpeg (Video extraction)")
	vbox.add_child(ffmpeg_row)
	
	colmap_row = _create_status_row("COLMAP (Structure from Motion)")
	vbox.add_child(colmap_row)
	
	python_row = _create_status_row("Python (SAM/WorldMirror AI)")
	vbox.add_child(python_row)
	
	vbox.add_child(HSeparator.new())
	
	var check_btn = Button.new()
	check_btn.text = "Check Tools & Refresh"
	check_btn.pressed.connect(_on_check_pressed)
	vbox.add_child(check_btn)
	
	var note = Label.new()
	note.text = "Note: You can configure custom executable paths at any time in the Settings section of the StudioTo3D bottom panel dock."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(note)
	
	# Initial check
	_check_and_update()

func _create_status_row(tool_name: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var lbl = Label.new()
	lbl.text = tool_name + ":"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	
	var status = Label.new()
	status.name = "StatusLabel"
	status.text = "Checking..."
	row.add_child(status)
	
	return row

func _on_check_pressed() -> void:
	_check_and_update()

func _check_and_update() -> void:
	var manager = get_node_or_null("/root/ReconstructionManager")
	if not manager:
		return
		
	var results = manager.call("check_tools")
	if results is Dictionary:
		_update_row_status(ffmpeg_row, results.get("ffmpeg", {}))
		_update_row_status(colmap_row, results.get("colmap", {}))
		_update_row_status(python_row, results.get("python", {}))

func _update_row_status(row: HBoxContainer, info: Dictionary) -> void:
	var status_lbl = row.get_node("StatusLabel") as Label
	if not status_lbl:
		return
		
	if info.get("found", false):
		status_lbl.text = "✅ Detected"
		status_lbl.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
	else:
		status_lbl.text = "❌ Missing / Not configured"
		status_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
