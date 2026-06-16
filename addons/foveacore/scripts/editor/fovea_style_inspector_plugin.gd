@tool
extends EditorInspectorPlugin

const FoveaStyle = preload("res://addons/foveacore/scripts/fovea_style.gd")
const FoveaMaterial = preload("res://addons/foveacore/scripts/fovea_material.gd")
const FoveaStylePreviewControl = preload("res://addons/foveacore/scripts/editor/fovea_style_preview_control.gd")

func _can_handle(object: Object) -> bool:
	return object is FoveaStyle or object is FoveaMaterial

func _parse_begin(object: Object) -> void:
	var preview = FoveaStylePreviewControl.new(object)
	add_custom_control(preview)
