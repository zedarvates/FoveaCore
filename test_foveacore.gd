extends Node
## TestFoveaCore — Scène de test pour valider le pipeline FoveaCore
## Affiche les statistiques de rendu en temps réel

@onready var _label: Label = null
@onready var _manager: FoveaCoreManager = null

var _frame_count: int = 0
var _fps: float = 0.0
var _frame_time: float = 0.0


func _ready() -> void:
	_setup_ui()
	_setup_environment()
	_manager = get_node_or_null("/root/FoveaCoreManager")
	print("=== FoveaCore Test Scene ===")
	print("Press T to toggle foveated rendering")
	print("Press 1-5 to change material style")


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "StatsCanvas"
	add_child(canvas)

	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.size = Vector2(400, 250)
	_label.add_theme_font_size_override("font_size", 14)
	canvas.add_child(_label)


func _setup_environment() -> void:
	var env_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node:
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.1, 0.1, 0.15)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env_node.environment = environment


func _process(delta: float) -> void:
	_frame_count += 1
	_frame_time += delta

	if _frame_time >= 1.0:
		_fps = float(_frame_count) / _frame_time
		_frame_count = 0
		_frame_time = 0.0
		_update_stats()


func _update_stats() -> void:
	if _label == null:
		return

	var stats_text := "=== FoveaCore Stats ===\n"
	stats_text += "FPS: %.1f\n" % _fps
	stats_text += "Frame time: %.2f ms\n" % (get_process_delta_time() * 1000.0)

	if _manager:
		stats_text += "\n--- Pipeline ---\n"
		stats_text += "Renderer initialized: %s\n" % _manager.renderer_initialized
		stats_text += "Foveated enabled: %s\n" % _manager.foveated_enabled
		stats_text += "Splat density: %.1f\n" % _manager.global_splat_density
		stats_text += "Style mode: %s\n" % _manager.style_mode

	stats_text += "\n--- Controls ---\n"
	stats_text += "T: Toggle foveated\n"
	stats_text += "1-5: Change style\n"
	stats_text += "R: Reset history\n"

	_label.text = stats_text


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_T:
				_toggle_foveated()
			KEY_1:
				_set_style("stone")
			KEY_2:
				_set_style("wood")
			KEY_3:
				_set_style("metal")
			KEY_4:
				_set_style("skin")
			KEY_5:
				_set_style("fabric")
			KEY_R:
				_reset_history()


func _toggle_foveated() -> void:
	if _manager:
		_manager.foveated_enabled = not _manager.foveated_enabled
		print("Foveated: ", _manager.foveated_enabled)


func _set_style(style_name: String) -> void:
	if _manager:
		print("Style changed to: ", style_name)
		var style = FoveaStyle.new()
		match style_name:
			"stone":
				style.detail = 1.5
				style.grain = 0.3
				style.light_coherence = 0.9
				style.color_saturation = 0.4
				style.micro_shadow = 0.6
			"wood":
				style.detail = 1.2
				style.grain = 0.4
				style.light_coherence = 0.7
				style.color_saturation = 0.5
				style.micro_shadow = 0.5
			"metal":
				style.detail = 2.0
				style.grain = 0.2
				style.light_coherence = 0.9
				style.color_saturation = 0.3
				style.micro_shadow = 0.4
			"skin":
				style.detail = 1.0
				style.grain = 0.5
				style.light_coherence = 0.6
				style.color_saturation = 0.8
				style.micro_shadow = 0.3
			"fabric":
				style.detail = 0.8
				style.grain = 0.6
				style.light_coherence = 0.5
				style.color_saturation = 0.7
				style.micro_shadow = 0.4
			_default:
				# Keep default values
				pass
		style.mode = "procedural"
		_manager.set_style(style)


func _reset_history() -> void:
	if _manager and _manager.has_method("_temporal_reprojector"):
		var reprojector := _manager.get("_temporal_reprojector") as Node
		if reprojector and reprojector.has_method("clear"):
			reprojector.call("clear")
			print("History cleared")
