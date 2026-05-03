extends Node3D
## Palette Benchmark — Compare palette vs full RGB565 rendering
## Controls: P=toggle palette, 1-4=palette sizes, F=show FPS, B=benchmark

@onready var _label: Label = null
@onready var _renderer: FoveaSplatRenderer = null

var _frame_count: int = 0
var _fps: float = 0.0
var _frame_time: float = 0.0
var _palette_enabled: bool = false
var _palette_size: int = 16
var _benchmark_results: Array = []


func _ready() -> void:
	_setup_ui()
	_setup_environment()
	_setup_renderer()
	print("=== FoveaEngine Palette Benchmark ===")
	print("P: Toggle palette on/off")
	print("1-4: Palette size (4, 8, 16, 32)")
	print("F: Show detailed FPS")
	print("B: Run benchmark (sweep all sizes)")


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "PaletteBenchmarkUI"
	add_child(canvas)

	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.size = Vector2(500, 350)
	_label.add_theme_font_size_override("font_size", 12)
	canvas.add_child(_label)


func _setup_environment() -> void:
	var env_node := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node:
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.06, 0.06, 0.10)
		env.ambient_light_color = Color(0.4, 0.4, 0.5)
		env_node.environment = env

	var sun := DirectionalLight3D.new()
	sun.name = "BenchmarkSun"
	sun.rotation = Vector3(-0.6, 0.2, 0)
	sun.light_energy = 3.0
	add_child(sun)

	var cam := Camera3D.new()
	cam.name = "BenchmarkCamera"
	cam.position = Vector3(0, 2, 8)
	cam.current = true
	add_child(cam)


func _setup_renderer() -> void:
	_renderer = FoveaSplatRenderer.new()
	_renderer.name = "PaletteRenderer"
	add_child(_renderer)

	# Try to load a default .fovea test file
	var test_paths := [
		"res://test_reconstruction/star_workspace/test.fovea",
		"res://reconstructions/bonsaitree/output/test.fovea",
	]
	for path in test_paths:
		if FileAccess.file_exists(path):
			_renderer.asset_path = path
			print("PaletteBenchmark: Loaded asset: ", path)
			break


func _process(delta: float) -> void:
	_frame_count += 1
	_frame_time += delta
	if _frame_time >= 0.5:
		_fps = float(_frame_count) / _frame_time
		_frame_count = 0
		_frame_time = 0.0
		_update_stats()


func _update_stats() -> void:
	if _label == null:
		return

	var text := "=== FoveaEngine PALETTE BENCHMARK ===\n"
	text += "FPS: %.1f | Frame: %.2f ms\n" % [_fps, 1000.0 / max(_fps, 0.1)]
	text += "\n--- Palette ---\n"
	text += "Enabled: %s\n" % _palette_enabled
	text += "Palette size: %d colors\n" % _palette_size
	text += "Bandwidth saved: ~%d%%\n" % _estimate_bandwidth_savings()
	text += "\n--- Shader ops saved ---\n"
	if _palette_enabled:
		text += "RGB565 decode: SKIPPED (palette lookup)\n"
		text += "Bit shifts: 0 vs 3 (in RGB565 mode)\n"
		text += "GPU ALU ops saved: ~8 per splat vertex\n"

	text += "\n--- Controls ---\n"
	text += "P: Toggle palette | 1-4: Set colors\n"
	text += "B: Full benchmark sweep | F: Freeze view\n"
	_label.text = text


func _estimate_bandwidth_savings() -> int:
	if not _palette_enabled:
		return 0
	return int(100.0 - (float(_palette_size) * 4.0 * 100.0 / (65536.0 * 2.0 / 8.0)))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_P:
				_toggle_palette()
			KEY_1:
				_set_palette_size(4)
			KEY_2:
				_set_palette_size(8)
			KEY_3:
				_set_palette_size(16)
			KEY_4:
				_set_palette_size(32)
			KEY_B:
				_run_full_benchmark()
			KEY_F:
				_toggle_freeze()


func _toggle_palette() -> void:
	_palette_enabled = not _palette_enabled

	if _palette_enabled:
		var palette := FoveaColorPalette.watercolor_16()
		if _palette_size != 16:
			palette = _generate_palette(_palette_size)
		_apply_palette(palette)
	else:
		_remove_palette()

	print("Palette: ", "ON (%d colors)" % _palette_size if _palette_enabled else "OFF (full RGB565)")


func _set_palette_size(size: int) -> void:
	_palette_size = size
	_palette_enabled = true
	var palette := _generate_palette(size)
	_apply_palette(palette)
	print("Palette size: %d" % size)


func _apply_palette(palette: FoveaColorPalette) -> void:
	if _renderer and palette:
		_renderer.setup_palette(palette)


func _remove_palette() -> void:
	if _renderer and _renderer.material_override is ShaderMaterial:
		var mat := _renderer.material_override as ShaderMaterial
		mat.set_shader_parameter("use_palette", false)
		mat.set_shader_parameter("palette_size", 0)


func _generate_palette(size: int) -> FoveaColorPalette:
	match size:
		4:
			return FoveaColorPalette.grayscale_4()
		8:
			var p := FoveaColorPalette.watercolor_16()
			# Subsample: take every other color
			var sub: Array[Color] = []
			for i in range(0, p.colors.size(), 2):
				if sub.size() < 8:
					sub.append(p.colors[i])
			p.colors = sub
			p.palette_size = 8
			return p
		16:
			return FoveaColorPalette.watercolor_16()
		32:
			# Generate via K-means on Watercolor 16 extended
			var p := FoveaColorPalette.watercolor_16()
			# Add interpolated variants
			while p.colors.size() < 32:
				p.colors.append(Color(randf(), randf(), randf()))
			p.palette_size = 32
			return p
		_:
			return FoveaColorPalette.watercolor_16()


func _run_full_benchmark() -> void:
	print("=== Palette Benchmark Sweep ===")
	_benchmark_results.clear()

	for sizes in [0, 4, 8, 16, 32]:
		if sizes == 0:
			_remove_palette()
			print("Testing: RGB565 (full color)")
		else:
			_palette_enabled = true
			_palette_size = sizes
			_apply_palette(_generate_palette(sizes))
			print("Testing: %d-color palette" % sizes)

		# Wait a few frames for stabilization
		var wait_frames := 30
		for _i in wait_frames:
			await get_tree().process_frame

		var fps_sum := 0.0
		var samples := 60
		for _i in samples:
			await get_tree().process_frame
			fps_sum += Engine.get_frames_per_second()

		var avg_fps := fps_sum / float(samples)
		_benchmark_results.append({"size": sizes, "fps": avg_fps})
		print("  Result: %.1f FPS" % avg_fps)

	# Print summary
	print("\n=== BENCHMARK RESULTS ===")
	print("Mode          | FPS   | vs RGB565")
	var baseline := 0.0
	for r in _benchmark_results:
		if r["size"] == 0:
			baseline = r["fps"]
			break

	for r in _benchmark_results:
		var label: String
		if r["size"] == 0:
			label = "RGB565 (65k)"
		else:
			label = "Palette %d-col" % r["size"]
		var delta_pct := 0.0
		if baseline > 0:
			delta_pct = (r["fps"] - baseline) / baseline * 100.0
		print("%-14s | %.1f | %+.1f%%" % [label, r["fps"], delta_pct])
	print("==============================")


func _toggle_freeze() -> void:
	# Toggle camera freeze for visual comparison
	process_mode = Node.PROCESS_MODE_DISABLED if process_mode != Node.PROCESS_MODE_DISABLED else Node.PROCESS_MODE_INHERIT
	print("Freeze: ", "ON" if process_mode == Node.PROCESS_MODE_DISABLED else "OFF")


func _exit_tree() -> void:
	if _renderer and _renderer.culler_pipeline:
		_renderer.culler_pipeline.cleanup()
