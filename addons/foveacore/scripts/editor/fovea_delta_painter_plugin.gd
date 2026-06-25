@tool
extends EditorPlugin

## FoveaEngine : Plugin d'Édition et Outil de Peinture Delta (Task 248)
## Fournit un pinceau interactif en 3D pour peindre couleur et déformation sur les splats.

var selected_node: FoveaSplattable = null
var toolbar: HBoxContainer = null

var brush_radius_slider: HSlider = null
var brush_mode_selector: OptionButton = null
var brush_color_picker: ColorPickerButton = null
var brush_deform_offset: Vector3 = Vector3(0, 0.1, 0)

var is_painting := false

func _enter_tree() -> void:
	# Création de la barre d'outils de peinture
	toolbar = HBoxContainer.new()
	toolbar.hide()
	
	var label := Label.new()
	label.text = " Delta Splat Painter: "
	toolbar.add_child(label)
	
	# Radius Slider
	var r_label := Label.new()
	r_label.text = " Radius: "
	toolbar.add_child(r_label)
	
	brush_radius_slider = HSlider.new()
	brush_radius_slider.min_value = 0.05
	brush_radius_slider.max_value = 2.0
	brush_radius_slider.step = 0.05
	brush_radius_slider.value = 0.5
	brush_radius_slider.custom_minimum_size = Vector2(100, 0)
	toolbar.add_child(brush_radius_slider)
	
	# Mode Selector
	brush_mode_selector = OptionButton.new()
	brush_mode_selector.add_item("Color Paint", 0)
	brush_mode_selector.add_item("Sculpt/Deform", 1)
	brush_mode_selector.add_item("Erase", 2)
	toolbar.add_child(brush_mode_selector)
	
	# Color Picker
	brush_color_picker = ColorPickerButton.new()
	brush_color_picker.color = Color.RED
	toolbar.add_child(brush_color_picker)
	
	# Save Button
	var save_btn := Button.new()
	save_btn.text = "Save Delta"
	save_btn.pressed.connect(_on_save_pressed)
	toolbar.add_child(save_btn)
	
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar)

func _exit_tree() -> void:
	if toolbar:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, toolbar)
		toolbar.queue_free()

func _handles(object: Object) -> bool:
	return object is FoveaSplattable

func _make_visible(visible: bool) -> void:
	if toolbar:
		toolbar.visible = visible

func _edit(object: Object) -> void:
	selected_node = object as FoveaSplattable

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not selected_node or not selected_node.visible:
		return AFTER_GUI_INPUT_PASS
		
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				is_painting = true
				_paint_at_mouse(viewport_camera, mouse_event.position)
				return AFTER_GUI_INPUT_STOP
			else:
				is_painting = false
				
	elif event is InputEventMouseMotion and is_painting:
		var motion_event := event as InputEventMouseMotion
		_paint_at_mouse(viewport_camera, motion_event.position)
		return AFTER_GUI_INPUT_STOP
		
	return AFTER_GUI_INPUT_PASS

func _paint_at_mouse(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not selected_node or selected_node.loaded_splats.is_empty():
		return
		
	# Lancer un rayon depuis la caméra de l'éditeur
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	
	# Trouver l'intersection la plus proche sur la boîte englobante ou le nuage de splats
	var closest_dist := 99999.0
	var intersection_point := Vector3.ZERO
	var found := false
	
	# Proximité simple par ray-sphere intersection sur le premier splat ou AABB centre
	var local_origin := selected_node.global_transform.affine_inverse() * from
	var local_dir := selected_node.global_transform.basis.inverse() * dir
	
	# Recherche brute simplifiée du splat le plus proche pour peindre
	var step := max(1, selected_node.loaded_splats.size() / 1000) # Échantillonner pour rester fluide
	for i in range(0, selected_node.loaded_splats.size(), step):
		var splat: GaussianSplat = selected_node.loaded_splats[i]
		var to_splat: Vector3 = splat.position - local_origin
		var projection: float = to_splat.dot(local_dir)
		var perp_dist: float = to_splat.length_squared() - (projection * projection)
		
		if perp_dist < 0.25 and projection > 0:
			if projection < closest_dist:
				closest_dist = projection
				intersection_point = splat.position
				found = true
				
	if found:
		var mode := "color"
		match brush_mode_selector.selected:
			0: mode = "color"
			1: mode = "deform"
			2: mode = "erase"
			
		FoveaSplatPaintTool.paint_splats(
			selected_node,
			intersection_point,
			brush_radius_slider.value,
			mode,
			brush_color_picker.color,
			brush_deform_offset
		)

func _on_save_pressed() -> void:
	if not selected_node:
		return
		
	var path := selected_node.delta_file_path
	if path.is_empty():
		path = "res://test_splat_paint.fvdelta"
		
	selected_node.save_delta_file(path)
	print("FoveaEngine: Delta peints sauvegardés avec succès dans: ", path)
