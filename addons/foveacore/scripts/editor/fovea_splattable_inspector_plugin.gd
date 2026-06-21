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

	box.add_child(HSeparator.new())

	var paint_title := Label.new()
	paint_title.text = "Splat Delta Paint Brush"
	paint_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	box.add_child(paint_title)

	var active_splattable := _resolve_splattable(object)

	var cb_paint := CheckButton.new()
	cb_paint.text = "Enable Paint Mode"
	cb_paint.button_pressed = active_splattable.get_meta("paint_mode", false) if active_splattable else false
	cb_paint.toggled.connect(func(pressed: bool) -> void:
		if active_splattable:
			active_splattable.set_meta("paint_mode", pressed)
	)
	box.add_child(cb_paint)

	var mode_opt := OptionButton.new()
	mode_opt.add_item("Paint Color", 0)
	mode_opt.add_item("Deform Offset", 1)
	mode_opt.add_item("Erase Deltas", 2)
	mode_opt.selected = active_splattable.get_meta("paint_brush_mode", 0) if active_splattable else 0
	mode_opt.item_selected.connect(func(idx: int) -> void:
		if active_splattable:
			active_splattable.set_meta("paint_brush_mode", idx)
	)
	box.add_child(mode_opt)

	# Radius slider
	var radius_box := HBoxContainer.new()
	var lbl_rad := Label.new()
	lbl_rad.text = "Radius: "
	radius_box.add_child(lbl_rad)
	
	var slider_rad := HSlider.new()
	slider_rad.min_value = 0.05
	slider_rad.max_value = 2.0
	slider_rad.step = 0.05
	slider_rad.value = active_splattable.get_meta("paint_brush_radius", 0.5) if active_splattable else 0.5
	slider_rad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_rad.value_changed.connect(func(val: float) -> void:
		if active_splattable:
			active_splattable.set_meta("paint_brush_radius", val)
	)
	radius_box.add_child(slider_rad)
	box.add_child(radius_box)

	# Color picker
	var color_picker := ColorPickerButton.new()
	color_picker.text = "Brush Color"
	color_picker.color = active_splattable.get_meta("paint_brush_color", Color.RED) if active_splattable else Color.RED
	color_picker.color_changed.connect(func(col: Color) -> void:
		if active_splattable:
			active_splattable.set_meta("paint_brush_color", col)
	)
	box.add_child(color_picker)

	# Save/Load buttons for Delta-Splat (Task 248)
	box.add_child(_make_button(
		"Save Painted Deltas",
		"Save painted color and deformation deltas to a .fvdelta file",
		func() -> void:
			if active_splattable:
				var path := active_splattable.delta_file_path
				if path.is_empty():
					path = "res://painted_deltas.fvdelta"
					active_splattable.delta_file_path = path
				active_splattable.save_delta_file(path)
				print("FoveaEngine: Deltas peints sauvegardés avec succès : ", path)
	))
	box.add_child(_make_button(
		"Load Painted Deltas",
		"Load color and deformation deltas from the configured .fvdelta file",
		func() -> void:
			if active_splattable and not active_splattable.delta_file_path.is_empty():
				active_splattable.load_delta_file(active_splattable.delta_file_path)
				print("FoveaEngine: Deltas chargés depuis : ", active_splattable.delta_file_path)
	))

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
