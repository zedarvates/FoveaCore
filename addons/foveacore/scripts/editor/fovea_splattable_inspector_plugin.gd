@tool
extends EditorInspectorPlugin
## Adds real action buttons to the [FoveaSplattable] / [FoveaSplat3D] inspector.
##
## Replaces the old "checkbox that resets itself" pattern
## ([code]trigger_generation[/code], [code]trigger_conversion_to_fovea[/code],
## [code]trigger_segmentation[/code]) with proper editor buttons.


func _can_handle(object: Object) -> bool:
	return object is FoveaSplattable or object is FoveaSplat3D


func _parse_begin(object: Object) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var title: Label = Label.new()
	title.text = "Fovea Actions"
	title.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	box.add_child(title)

	box.add_child(_make_button(
		"Generate Splats from Mesh",
		"Procedurally generate splats from the attached MeshInstance3D",
		func() -> void: _on_generate_pressed(object)))
	box.add_child(_make_button(
		"Convert to .fovea",
		"Compress the loaded splats into a native .fovea asset next to the source file",
		func() -> void: _on_convert_pressed(object)))
	box.add_child(_make_button(
		"Run AI Segmentation",
		"Run 3D semantic segmentation using the prompt configured in 'AI Segmentation & Tagging'",
		func() -> void: _on_segment_pressed(object)))

	add_custom_control(box)


func _make_button(text: String, tooltip: String, on_pressed: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.pressed.connect(on_pressed)
	return btn


## Resolves the actual FoveaSplattable to act on. For FoveaSplat3D this is its
## internal delegate (may be null if the node is not yet inside a scene tree).
func _resolve_splattable(object: Object) -> FoveaSplattable:
	if object is FoveaSplattable:
		return object as FoveaSplattable
	if object is FoveaSplat3D:
		return (object as FoveaSplat3D).get_advanced()
	return null


func _on_generate_pressed(object: Object) -> void:
	var target: FoveaSplattable = _resolve_splattable(object)
	if target == null:
		push_warning("FoveaInspector: Node is not ready yet, cannot generate splats.")
		return
	target.generate_splats_now()


func _on_convert_pressed(object: Object) -> void:
	var target: FoveaSplattable = _resolve_splattable(object)
	if target == null:
		push_warning("FoveaInspector: Node is not ready yet, cannot convert.")
		return
	if target.splat_file_path.is_empty():
		push_warning("FoveaInspector: No splat file loaded to convert.")
		return
	var dest: String = target.splat_file_path.get_basename() + ".fovea"
	target.export_to_fovea(dest)


func _on_segment_pressed(object: Object) -> void:
	var target: FoveaSplattable = _resolve_splattable(object)
	if target == null:
		push_warning("FoveaInspector: Node is not ready yet, cannot run segmentation.")
		return
	if target.run_segmentation_prompt.is_empty():
		push_warning("FoveaInspector: Please specify a segmentation prompt first ('AI Segmentation & Tagging' group).")
		return
	target.run_segmentation(target.run_segmentation_prompt)
