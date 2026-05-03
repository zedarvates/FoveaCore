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


func setup(preview: TextureRect, sess: ReconstructionSession) -> void:
	preview_rect = preview
	session = sess
	if preview_rect:
		var mat = ShaderMaterial.new()
		mat.shader = load("res://addons/foveacore/shaders/mask_preview.gdshader")
		preview_rect.material = mat
		_update_params()


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
