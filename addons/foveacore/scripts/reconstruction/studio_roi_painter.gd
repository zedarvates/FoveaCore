extends AcceptDialog
class_name StudioRoiPainter

## StudioRoiPainter — ROI painting dialog for StudioTo3D
## Extracted from studio_to_3d_panel.gd to reduce monolith size.
## Usage:
##   var painter = StudioRoiPainter.create(preview_image)
##   painter.roi_confirmed.connect(func(rect: Rect2i): session.roi_rect = rect)
##   add_child(painter); painter.popup_centered()

signal roi_confirmed(rect: Rect2i)

var _mask_img: Image
var _mask_tex: ImageTexture
var _source_img: Image
var _size_slider: HSlider
var _mode_btn: OptionButton
var _is_drawing := false


static func create(source_image: Image) -> StudioRoiPainter:
	var painter = StudioRoiPainter.new()
	painter._source_img = source_image
	painter._build_ui()
	return painter


func _build_ui() -> void:
	title = "Paint Region of Interest (ROI)"
	size = Vector2i(1200, 850)
	get_label().hide()

	confirm_text = "Apply ROI"

	var main_vbox = VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	add_child(main_vbox)

	# --- Toolbar ---
	var toolbar = HBoxContainer.new()
	main_vbox.add_child(toolbar)

	_mode_btn = OptionButton.new()
	_mode_btn.add_item("🖌️ Paint (Add)", 0)
	_mode_btn.add_item("🧽 Eraser (Remove)", 1)
	toolbar.add_child(_mode_btn)

	toolbar.add_child(VSeparator.new())

	var size_label = Label.new()
	size_label.text = "Brush Size: "
	toolbar.add_child(size_label)

	_size_slider = HSlider.new()
	_size_slider.min_value = 5
	_size_slider.max_value = 100
	_size_slider.value = 30
	_size_slider.custom_minimum_size = Vector2(150, 0)
	toolbar.add_child(_size_slider)

	var reset_btn = Button.new()
	reset_btn.text = "🗑️ Clear All"
	toolbar.add_child(reset_btn)

	# --- Drawing Area ---
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)

	var container = Control.new()
	container.custom_minimum_size = Vector2(_source_img.get_width(), _source_img.get_height())
	scroll.add_child(container)

	var tex = ImageTexture.create_from_image(_source_img)
	var rect_display = TextureRect.new()
	rect_display.texture = tex
	rect_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect_display.mouse_filter = Control.MOUSE_FILTER_STOP
	container.add_child(rect_display)

	_mask_img = Image.create(_source_img.get_width(), _source_img.get_height(), false, Image.FORMAT_RGBA8)
	_mask_img.fill(Color(0, 0, 0, 0))
	_mask_tex = ImageTexture.create_from_image(_mask_img)

	var mask_display = TextureRect.new()
	mask_display.texture = _mask_tex
	mask_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mask_display.modulate = Color(0, 1, 0, 0.5)
	mask_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(mask_display)

	# --- Painting Logic ---
	rect_display.gui_input.connect(_on_draw_input)

	reset_btn.pressed.connect(func():
		_mask_img.fill(Color(0, 0, 0, 0))
		_mask_tex.update(_mask_img)
	)

	confirmed.connect(_on_apply)


func _on_draw_input(event: InputEvent) -> void:
	var erasing := _mode_btn.selected == 1
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_is_drawing = event.pressed
		if _is_drawing:
			_draw_brush(event.position, erasing)
	elif event is InputEventMouseMotion and _is_drawing:
		_draw_brush(event.position, erasing)


func _draw_brush(pos: Vector2, erase: bool) -> void:
	var center := Vector2i(pos)
	var r := int(_size_slider.value)
	var color := Color(0, 0, 0, 0) if erase else Color(1, 1, 1, 1)
	var w := _mask_img.get_width()
	var h := _mask_img.get_height()

	var y_start := maxi(center.y - r, 0)
	var y_end := mini(center.y + r, h - 1)
	var x_start := maxi(center.x - r, 0)
	var x_end := mini(center.x + r, w - 1)

	var r2 := r * r
	for y in range(y_start, y_end + 1):
		var dy := y - center.y
		var dy2 := dy * dy
		for x in range(x_start, x_end + 1):
			var dx := x - center.x
			if dx * dx + dy2 <= r2:
				_mask_img.set_pixel(x, y, color)
	_mask_tex.update(_mask_img)


func _on_apply() -> void:
	var used_rect := _mask_img.get_used_rect()
	if used_rect.size.x < 10:
		roi_confirmed.emit(Rect2i(0, 0, _source_img.get_width(), _source_img.get_height()))
	else:
		roi_confirmed.emit(used_rect)
	queue_free()
