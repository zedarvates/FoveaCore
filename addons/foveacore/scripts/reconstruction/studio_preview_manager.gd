extends Node
class_name StudioPreviewManager

## StudioPreviewManager — Handles preview image display and shader parameters
## Extracted from studio_to_3d_panel.gd to reduce monolith size.
## Manages the mask_preview.gdshader material and preview TextureRect sizing.

var preview_rect: TextureRect
var session: ReconstructionSession

# UI controls for preview parameters
var threshold_slider: HSlider
var mask_option: OptionButton
var show_mask_toggle: CheckBox
var roi_toggle: CheckBox

var _is_drawing_roi: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO


func setup(preview: TextureRect, sess: ReconstructionSession) -> void:
	preview_rect = preview
	session = sess
	if preview_rect:
		var mat = ShaderMaterial.new()
		mat.shader = load("res://addons/foveacore/shaders/mask_preview.gdshader")
		preview_rect.material = mat
		_update_params()
		
		# Connect the GUI input for mouse drawing
		if not preview_rect.gui_input.is_connected(_on_preview_gui_input):
			preview_rect.gui_input.connect(_on_preview_gui_input)
		# Enable mouse filter to receive inputs
		preview_rect.mouse_filter = Control.MOUSE_FILTER_STOP


func set_preview_image(img: Image) -> void:
	if not preview_rect:
		return
	var tex = ImageTexture.create_from_image(img)
	preview_rect.texture = tex
	var max_width := 400.0
	var aspect := float(img.get_height()) / float(img.get_width())
	preview_rect.custom_minimum_size = Vector2(max_width, max_width * aspect)


func _update_params() -> void:
	if not preview_rect or not (preview_rect.material is ShaderMaterial):
		return
	var mat := preview_rect.material as ShaderMaterial
	mat.set_shader_parameter("threshold", threshold_slider.value if threshold_slider else 0.95)
	mat.set_shader_parameter("mask_mode", mask_option.selected if mask_option else 0)
	mat.set_shader_parameter("show_mask_overlay", show_mask_toggle.button_pressed if show_mask_toggle else true)

	var roi_pos := Vector2.ZERO
	var roi_size := Vector2.ZERO
	if session and session.roi_rect != Rect2i():
		roi_pos = Vector2(session.roi_rect.position.x, session.roi_rect.position.y)
		roi_size = Vector2(session.roi_rect.size.x, session.roi_rect.size.y)
	mat.set_shader_parameter("roi_pos", roi_pos)
	mat.set_shader_parameter("roi_size", roi_size)
	mat.set_shader_parameter("show_roi", roi_toggle.button_pressed if roi_toggle else false)


func on_threshold_changed(_value: float) -> void:
	_update_params()


func on_mask_mode_changed(_index: int) -> void:
	_update_params()


func on_show_mask_toggled(_checked: bool) -> void:
	_update_params()


func on_show_roi_toggled(_checked: bool) -> void:
	_update_params()

func _on_preview_gui_input(event: InputEvent) -> void:
	if not session or not preview_rect or not preview_rect.texture:
		return
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_drawing_roi = true
			_drag_start_pos = event.position
		else:
			_is_drawing_roi = false
			# Finalize the ROI
			var drag_end_pos: Vector2 = event.position
			var rect := _calculate_roi_rect(_drag_start_pos, drag_end_pos)
			
			if rect.size.x < 5 or rect.size.y < 5:
				# Reset ROI if click is too small (behaves as reset click)
				session.roi_rect = Rect2i()
			else:
				session.roi_rect = rect
				
			if roi_toggle:
				roi_toggle.button_pressed = true
			_update_params()
			
	elif event is InputEventMouseMotion and _is_drawing_roi:
		# Update preview dynamically while dragging
		var rect := _calculate_roi_rect(_drag_start_pos, event.position)
		if rect.size.x >= 5 and rect.size.y >= 5:
			session.roi_rect = rect
			if roi_toggle:
				roi_toggle.button_pressed = true
			_update_params()

func _calculate_roi_rect(start: Vector2, end: Vector2) -> Rect2i:
	var texture_size := preview_rect.texture.get_size()
	var rect_size := preview_rect.size
	
	# Clamp positions to control rect
	var start_clamped := Vector2(
		clamp(start.x, 0.0, rect_size.x),
		clamp(start.y, 0.0, rect_size.y)
	)
	var end_clamped := Vector2(
		clamp(end.x, 0.0, rect_size.x),
		clamp(end.y, 0.0, rect_size.y)
	)
	
	# Convert local coordinates to texture coordinates
	var start_tex := Vector2(
		start_clamped.x / rect_size.x * texture_size.x,
		start_clamped.y / rect_size.y * texture_size.y
	)
	var end_tex := Vector2(
		end_clamped.x / rect_size.x * texture_size.x,
		end_clamped.y / rect_size.y * texture_size.y
	)
	
	var min_pos := Vector2i(
		int(min(start_tex.x, end_tex.x)),
		int(min(start_tex.y, end_tex.y))
	)
	var max_pos := Vector2i(
		int(max(start_tex.x, end_tex.x)),
		int(max(start_tex.y, end_tex.y))
	)
	
	var size := max_pos - min_pos
	return Rect2i(min_pos, size)
