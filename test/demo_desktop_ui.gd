class_name DemoDesktopUI
extends CanvasLayer

var renderer_node: Node = null
var fps_label: Label
var tile_checkbox: CheckButton
var lod_slider: HSlider
var lod_label: Label

func _ready() -> void:
	# Find FoveaCoreSplatRenderer or FoveaInstancedSplatRenderer in scene
	renderer_node = get_parent().find_child("*SplatRenderer*", true, false)
	if not renderer_node:
		renderer_node = get_parent().find_child("*splat*", true, false)
		
	# Build simple UI programmatically to ensure it always works and looks great
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 150)
	panel.position = Vector2(20, 20)
	add_child(panel)
	
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "FoveaEngine Desktop Demo"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# FPS Label
	fps_label = Label.new()
	fps_label.text = "FPS: 0"
	vbox.add_child(fps_label)
	
	# Tile Rasterizer Toggle
	tile_checkbox = CheckButton.new()
	tile_checkbox.text = "Tile-Based Rasterizer"
	tile_checkbox.button_pressed = false
	if renderer_node and "enable_tile_rasterizer" in renderer_node:
		tile_checkbox.button_pressed = renderer_node.enable_tile_rasterizer
	tile_checkbox.toggled.connect(_on_tile_toggled)
	vbox.add_child(tile_checkbox)
	
	# LOD Threshold Slider
	var lod_hbox := HBoxContainer.new()
	vbox.add_child(lod_hbox)
	
	var slider_label := Label.new()
	slider_label.text = "LOD Cull: "
	lod_hbox.add_child(slider_label)
	
	lod_label = Label.new()
	lod_label.text = "0.0"
	lod_hbox.add_child(lod_label)
	
	lod_slider = HSlider.new()
	lod_slider.min_value = -1.0
	lod_slider.max_value = 1.0
	lod_slider.step = 0.05
	lod_slider.value = 0.0
	if renderer_node and "cull_threshold" in renderer_node:
		lod_slider.value = renderer_node.cull_threshold
		lod_label.text = "%.2f" % renderer_node.cull_threshold
	lod_slider.value_changed.connect(_on_lod_changed)
	lod_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(lod_slider)
	
	# Instruction Label
	var inst := Label.new()
	inst.text = "\n[Right Click + Drag] to Look\n[W/A/S/D] to Fly\n[Q/E] Up/Down"
	inst.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(inst)

func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d (%.2f ms)" % [Engine.get_frames_per_second(), 1000.0 / max(1.0, Engine.get_frames_per_second())]

func _on_tile_toggled(button_pressed: bool) -> void:
	if renderer_node and "enable_tile_rasterizer" in renderer_node:
		renderer_node.enable_tile_rasterizer = button_pressed
		if renderer_node.has_method("update_material_shader"):
			renderer_node.update_material_shader()

func _on_lod_changed(value: float) -> void:
	lod_label.text = "%.2f" % value
	if renderer_node and "cull_threshold" in renderer_node:
		renderer_node.cull_threshold = value
