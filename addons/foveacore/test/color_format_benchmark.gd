# color_format_benchmark.gd
# Godot 4.x - Benchmark de comparaison RGB565 vs Palette 8-bit + Dithering
# Mesures : temps rendu GPU, VRAM, bande passante CPU→GPU, PSNR/SSIM, artefacts banding

extends Node

# Configuration
@export var test_duration: float = 10.0  # secondes par test
@export var test_resolutions: Array = [640, 1280, 1920]  # largeurs en pixels
@export var use_dithering: bool = true
@export var save_results: bool = true
@export var results_file: String = "user://color_format_benchmark_results.csv"

# Références aux scènes de test
var _gradient_scene: Node2D = null
var _transparency_scene: Node2D = null
var _color_blend_scene: Node2D = null

# Nœuds de rendu
var _viewport_rgb565: SubViewport = null
var _viewport_palette: SubViewport = null
var _camera: Camera2D = null

# Textures de référence pour PSNR/SSIM
var _reference_texture_rgb565: ImageTexture = null
var _reference_texture_palette: ImageTexture = null

# Métriques
var _frame_times_rgb565: Array = []
var _frame_times_palette: Array = []
var _vram_usage_rgb565: Array = []
var _vram_usage_palette: Array = []
var _bandwidth_samples: Array = []
var _psnr_values: Array = []
var _ssim_values: Array = []
var _banding_artifacts: Array = []

var _current_test_index: int = 0
var _is_testing: bool = false
var _test_start_time: float = 0.0
var _frames_rendered: int = 0
var _test_results: Array = []

# Shaders pour analyse
var _banding_detection_shader: ShaderMaterial
var _psnr_calculation_shader: ShaderMaterial

# Constantes
const RGB565_FORMAT = Image.FORMAT_RGB565
const PALETTE_FORMAT = Image.FORMAT_L8  # 8-bit palette
const DITHER_THRESHOLD = 0.08

signal benchmark_complete(results: Array)
signal test_progress(current: int, total: int, message: String)


func _ready() -> void:
	print("ColorFormatBenchmark: Initialisation...")
	_create_test_scenes()
	_setup_viewports()
	_load_shaders()
	
	if Engine.is_editor_hint():
		set_process(true)
		_start_benchmark()
	else:
		set_process(false)


func _create_test_scenes() -> void:
	"""Crée les scènes de test avec gradients continus, transparence, mélanges"""
	
	# Scène 1: Gradients continus (test banding)
	_gradient_scene = Node2D.new()
	_gradient_scene.name = "GradientTest"
	
	var gradient_sprite = Sprite2D.new()
	var gradient_image = Image.create(512, 512, false, Image.FORMAT_RGBA8)
	
	# Création d'un gradient continu sans banding
	for y in range(512):
		for x in range(512):
			var r = float(x) / 512.0
			var g = float(y) / 512.0
			var b = sin(float(x) / 100.0) * 0.5 + 0.5
			var a = 1.0
			gradient_image.set_pixel(x, y, Color(r, g, b, a))
	
	var gradient_texture = ImageTexture.create_from_image(gradient_image)
	gradient_sprite.texture = gradient_texture
	_gradient_scene.add_child(gradient_sprite)
	add_child(_gradient_scene)
	
	# Scène 2: Transparence et alpha blending
	_transparency_scene = Node2D.new()
	_transparency_scene.name = "TransparencyTest"
	
	var transparent_sprite = Sprite2D.new()
	var transparent_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	# Dégradé alpha
	for y in range(256):
		for x in range(256):
			var alpha = float(x) / 256.0
			transparent_image.set_pixel(x, y, Color(1.0, 0.5, 0.0, alpha))
	
	var transparent_texture = ImageTexture.create_from_image(transparent_image)
	transparent_sprite.texture = transparent_texture
	_transparency_scene.add_child(transparent_sprite)
	add_child(_transparency_scene)
	
	# Scène 3: Mélanges de couleurs complexes
	_color_blend_scene = Node2D.new()
	_color_blend_scene.name = "ColorBlendTest"
	
	var blend_sprite = Sprite2D.new()
	var blend_image = Image.create(300, 300, false, Image.FORMAT_RGBA8)
	
	# Cercles de couleurs avec mélanges subtils
	for y in range(300):
		for x in range(300):
			var dx = x - 150
			var dy = y - 150
			var dist = sqrt(dx*dx + dy*dy)
			
			if dist < 100:
				# Dégradé radial subtil
				var t = dist / 100.0
				var r = 0.8 + 0.2 * sin(t * 10.0)
				var g = 0.3 + 0.4 * t
				var b = 0.9 - 0.4 * t
				blend_image.set_pixel(x, y, Color(r, g, b, 1.0))
			else:
				blend_image.set_pixel(x, y, Color(0.1, 0.1, 0.15, 1.0))
	
	var blend_texture = ImageTexture.create_from_image(blend_image)
	blend_sprite.texture = blend_texture
	_color_blend_scene.add_child(blend_sprite)
	add_child(_color_blend_scene)
	
	# Positionnement
	_gradient_scene.position = Vector2(100, 100)
	_transparency_scene.position = Vector2(400, 100)
	_color_blend_scene.position = Vector2(700, 100)


func _setup_viewports() -> void:
	"""Configure les viewports pour le rendu comparatif"""
	
	# Viewport RGB565
	_viewport_rgb565 = SubViewport.new()
	_viewport_rgb565.name = "Viewport_RGB565"
	_viewport_rgb565.size = Vector2i(1280, 720)
	_viewport_rgb565.transparent_bg = true
	_viewport_rgb565.handle_input_locally = false
	_viewport_rgb565.msaa_2d = SubViewport.MSAA_DISABLED
	_viewport_rgb565.use_debanding = false
	_viewport_rgb565.use_occlusion_culling = false
	add_child(_viewport_rgb565)
	
	# Viewport Palette 8-bit
	_viewport_palette = SubViewport.new()
	_viewport_palette.name = "Viewport_Palette"
	_viewport_palette.size = Vector2i(1280, 720)
	_viewport_palette.transparent_bg = true
	_viewport_palette.handle_input_locally = false
	_viewport_palette.msaa_2d = SubViewport.MSAA_DISABLED
	_viewport_palette.use_debanding = false
	_viewport_palette.use_occlusion_culling = false
	add_child(_viewport_palette)
	
	# Caméra 2D
	_camera = Camera2D.new()
	_camera.zoom = Vector2(1, 1)
	add_child(_camera)
	
	# Copier la scène dans les deux viewports
	var scene_container_rgb = Node2D.new()
	var scene_container_pal = Node2D.new()
	
	# Dupliquer les scènes de test
	var grad_dup = _gradient_scene.duplicate()
	var trans_dup = _transparency_scene.duplicate()
	var blend_dup = _color_blend_scene.duplicate()
	
	scene_container_rgb.add_child(grad_dup)
	scene_container_rgb.add_child(trans_dup)
	scene_container_rgb.add_child(blend_dup)
	
	var grad_dup2 = _gradient_scene.duplicate()
	var trans_dup2 = _transparency_scene.duplicate()
	var blend_dup2 = _color_blend_scene.duplicate()
	
	scene_container_pal.add_child(grad_dup2)
	scene_container_pal.add_child(trans_dup2)
	scene_container_pal.add_child(blend_dup2)
	
	_viewport_rgb565.add_child(scene_container_rgb)
	_viewport_palette.add_child(scene_container_pal)


func _load_shaders() -> void:
	"""Charge les shaders d'analyse"""
	
	# Shader de détection de banding
	var banding_shader_code = """
		shader_type canvas_item;
		
		uniform float threshold = 0.05;
		
		void fragment() {
			vec4 color = texture(TEXTURE, UV);
			
			// Détection de banding par analyse du gradient local
			float dx = dFdx(color.r) + dFdx(color.g) + dFdx(color.b);
			float dy = dFdy(color.r) + dFdy(color.g) + dFdy(color.b);
			
			float gradient_magnitude = sqrt(dx*dx + dy*dy);
			
			// Banding détecté si gradient très faible mais changement de couleur
			float banding = step(threshold, abs(color.r - color.g)) * 
						   step(threshold, abs(color.g - color.b)) *
						   (1.0 - gradient_magnitude);
			
			COLOR = vec4(vec3(banding), 1.0);
		}
	"""
	
	_banding_detection_shader = ShaderMaterial.new()
	_banding_detection_shader.shader = Shader.new()
	_banding_detection_shader.shader.code = banding_shader_code


func _start_benchmark() -> void:
	"""Démarre le benchmark"""
	if _is_testing:
		push_warning("Benchmark déjà en cours")
		return
	
	_is_testing = true
	_current_test_index = 0
	_test_results.clear()
	_frames_rendered = 0
	
	print("ColorFormatBenchmark: Démarrage du benchmark RGB565 vs Palette 8-bit")
	_run_next_test()


func _run_next_test() -> void:
	"""Exécute le test suivant"""
	if _current_test_index >= test_resolutions.size():
		_complete_benchmark()
		return
	
	var resolution = test_resolutions[_current_test_index]
	
	print("ColorFormatBenchmark: Test %d/%d - Résolution: %dx%d" % [
		_current_test_index + 1, test_resolutions.size(), resolution, resolution * 9/16])
	
	# Ajuster la taille des viewports
	_viewport_rgb565.size = Vector2i(resolution, resolution * 9/16)
	_viewport_palette.size = Vector2i(resolution, resolution * 9/16)
	
	# Réinitialiser les métriques
	_frame_times_rgb565.clear()
	_frame_times_palette.clear()
	_vram_usage_rgb565.clear()
	_vram_usage_palette.clear()
	_psnr_values.clear()
	_ssim_values.clear()
	_banding_artifacts.clear()
	
	_frames_rendered = 0
	_test_start_time = Time.get_ticks_msec()
	
	set_process(true)


func _process(delta: float) -> void:
	if not _is_testing:
		return
	
	var frame_start = Time.get_ticks_usec()
	
	# Capturer les images des viewports
	var image_rgb565 = _viewport_rgb565.get_texture().get_image()
	var image_palette = _viewport_palette.get_texture().get_image()
	
	# Convertir en formats cibles
	if use_dithering:
		_apply_floyd_steinberg_dithering(image_palette)
	
	image_rgb565.convert(RGB565_FORMAT)
	image_palette.convert(PALETTE_FORMAT)
	
	var frame_end = Time.get_ticks_usec()
	var frame_time_ms = (frame_end - frame_start) / 1000.0
	
	# Mesurer l'utilisation VRAM (approximative)
	var vram_rgb565 = image_rgb565.get_data().size()
	var vram_palette = image_palette.get_data().size()
	
	_frame_times_rgb565.append(frame_time_ms)
	_vram_usage_rgb565.append(vram_rgb565)
	_vram_usage_palette.append(vram_palette)
	
	# Calculer PSNR et SSIM périodiquement
	if _frames_rendered % 10 == 0:
		var psnr = _calculate_psnr(image_rgb565, image_palette)
		var ssim = _calculate_ssim(image_rgb565, image_palette)
		_psnr_values.append(psnr)
		_ssim_values.append(ssim)
	
	# Détecter les artefacts de banding
	var banding_score = _detect_banding(image_palette)
	_banding_artifacts.append(banding_score)
	
	_frames_rendered += 1
	
	# Vérifier la durée du test
	var elapsed = (Time.get_ticks_msec() - _test_start_time) / 1000.0
	if elapsed >= test_duration:
		_complete_current_test()


func _apply_floyd_steinberg_dithering(image: Image) -> void:
	"""Applique le dithering de Floyd-Steinberg"""
	var width = image.get_width()
	var height = image.get_height()
	
	for y in range(height):
		for x in range(width):
			var old_pixel = image.get_pixel(x, y)
			var new_pixel = _quantize_color(old_pixel)
			image.set_pixel(x, y, new_pixel)
			
			var error = old_pixel - new_pixel
			
			if x + 1 < width:
				image.set_pixel(x + 1, y, image.get_pixel(x + 1, y) + error * 7/16)
			if x - 1 >= 0 and y + 1 < height:
				image.set_pixel(x - 1, y + 1, image.get_pixel(x - 1, y + 1) + error * 3/16)
			if y + 1 < height:
				image.set_pixel(x, y + 1, image.get_pixel(x, y + 1) + error * 5/16)
			if x + 1 < width and y + 1 < height:
				image.set_pixel(x + 1, y + 1, image.get_pixel(x + 1, y + 1) + error * 1/16)


func _quantize_color(color: Color) -> Color:
	"""Quantifie la couleur en 8-bit (256 couleurs)"""
	var r = round(color.r * 255) / 255.0
	var g = round(color.g * 255) / 255.0
	var b = round(color.b * 255) / 255.0
	return Color(r, g, b, color.a)


func _calculate_psnr(img1: Image, img2: Image) -> float:
	"""Calcule le Peak Signal-to-Noise Ratio"""
	var mse = 0.0
	var pixel_count = 0
	
	var size = min(img1.get_width(), img2.get_width())
	
	for y in range(size):
		for x in range(size):
			var c1 = img1.get_pixel(x, y)
			var c2 = img2.get_pixel(x, y)
			
			mse += (c1.r - c2.r)**2 + (c1.g - c2.g)**2 + (c1.b - c2.b)**2
			pixel_count += 1
	
	if pixel_count == 0:
		return 0.0
	
	mse /= pixel_count * 3  # 3 channels
	
	if mse == 0:
		return 100.0
	
	var psnr = 10 * log(255.0 * 255.0 / mse) / log(10)
	return psnr


func _calculate_ssim(img1: Image, img2: Image) -> float:
	"""Calcule le Structural Similarity Index (simplifié)"""
	var c1 = 0.01 * 255
	var c2 = 0.03 * 255
	
	var mu1 = 0.0
	var mu2 = 0.0
	var sigma1_sq = 0.0
	var sigma2_sq = 0.0
	var sigma12 = 0.0
	var n = 0
	
	var size = min(img1.get_width(), img2.get_width())
	
	for y in range(size):
		for x in range(size):
			var c1_pixel = img1.get_pixel(x, y)
			var c2_pixel = img2.get_pixel(x, y)
			
			var lum1 = (c1_pixel.r + c1_pixel.g + c1_pixel.b) / 3.0 * 255
			var lum2 = (c2_pixel.r + c2_pixel.g + c2_pixel.b) / 3.0 * 255
			
			mu1 += lum1
			mu2 += lum2
			n += 1
	
	if n == 0:
		return 0.0
	
	mu1 /= n
	mu2 /= n
	
	for y in range(size):
		for x in range(size):
			var c1_pixel = img1.get_pixel(x, y)
			var c2_pixel = img2.get_pixel(x, y)
			
			var lum1 = (c1_pixel.r + c1_pixel.g + c1_pixel.b) / 3.0 * 255
			var lum2 = (c2_pixel.r + c2_pixel.g + c2_pixel.b) / 3.0 * 255
			
			sigma1_sq += (lum1 - mu1)**2
			sigma2_sq += (lum2 - mu2)**2
			sigma12 += (lum1 - mu1) * (lum2 - mu2)
	
	sigma1_sq /= n
	sigma2_sq /= n
	sigma12 /= n
	
	var ssim = ((2 * mu1 * mu2 + c1*c1) * (2 * sigma12 + c2*c2)) / 
			   ((mu1*mu1 + mu2*mu2 + c1*c1) * (sigma1_sq + sigma2_sq + c2*c2))
	
	return ssim


func _detect_banding(image: Image) -> float:
	"""Détecte les artefacts de banding"""
	var banding_score = 0.0
	var sample_count = 0
	
	# Analyser les gradients horizontaux et verticaux
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			if x + 2 < image.get_width():
				var c1 = image.get_pixel(x, y)
				var c2 = image.get_pixel(x + 1, y)
				var c3 = image.get_pixel(x + 2, y)
				
				var diff1 = abs(c1.get_luminance() - c2.get_luminance())
				var diff2 = abs(c2.get_luminance() - c3.get_luminance())
				
				# Banding si sauts brusques dans un gradient supposé lisse
				if diff1 > 0.1 and diff2 > 0.1 and abs(diff1 - diff2) > 0.05:
					banding_score += 1.0
				
				sample_count += 1
	
	if sample_count == 0:
		return 0.0
	
	return banding_score / sample_count


func _complete_current_test() -> void:
	"""Termine le test en cours"""
	set_process(false)
	
	# Calculer les moyennes
	var avg_frame_time_rgb565 = 0.0
	var avg_frame_time_palette = 0.0
	var avg_vram_rgb565 = 0.0
	var avg_vram_palette = 0.0
	var avg_psnr = 0.0
	var avg_ssim = 0.0
	var avg_banding = 0.0
	
	if _frame_times_rgb565.size() > 0:
		for t in _frame_times_rgb565:
			avg_frame_time_rgb565 += t
		avg_frame_time_rgb565 /= _frame_times_rgb565.size()
	
	if _frame_times_palette.size() > 0:
		for t in _frame_times_palette:
			avg_frame_time_palette += t
		avg_frame_time_palette /= _frame_times_palette.size()
	
	if _vram_usage_rgb565.size() > 0:
		for v in _vram_usage_rgb565:
			avg_vram_rgb565 += v
		avg_vram_rgb565 /= _vram_usage_rgb565.size()
	
	if _vram_usage_palette.size() > 0:
		for v in _vram_usage_palette:
			avg_vram_palette += v
		avg_vram_palette /= _vram_usage_palette.size()
	
	if _psnr_values.size() > 0:
		for p in _psnr_values:
			avg_psnr += p
		avg_psnr /= _psnr_values.size()
	
	if _ssim_values.size() > 0:
		for s in _ssim_values:
			avg_ssim += s
		avg_ssim /= _ssim_values.size()
	
	if _banding_artifacts.size() > 0:
		for b in _banding_artifacts:
			avg_banding += b
		avg_banding /= _banding_artifacts.size()
	
	# Calculer la bande passante (approximation)
	var resolution = test_resolutions[_current_test_index]
	var bandwidth_rgb565 = (avg_vram_rgb565 / 1024.0) / (avg_frame_time_rgb565 / 1000.0)  # KB/s
	var bandwidth_palette = (avg_vram_palette / 1024.0) / (avg_frame_time_palette / 1000.0)  # KB/s
	
	# Stocker les résultats
	var result = {
		"test_index": _current_test_index,
		"resolution": resolution,
		"format_rgb565": "RGB565",
		"format_palette": "Palette_8bit",
		"use_dithering": use_dithering,
		"avg_frame_time_rgb565_ms": avg_frame_time_rgb565,
		"avg_frame_time_palette_ms": avg_frame_time_palette,
		"fps_rgb565": 1000.0 / avg_frame_time_rgb565 if avg_frame_time_rgb565 > 0 else 0,
		"fps_palette": 1000.0 / avg_frame_time_palette if avg_frame_time_palette > 0 else 0,
		"vram_rgb565_bytes": avg_vram_rgb565,
		"vram_palette_bytes": avg_vram_palette,
		"vram_saving_pct": ((avg_vram_rgb565 - avg_vram_palette) / avg_vram_rgb565) * 100.0 if avg_vram_rgb565 > 0 else 0,
		"bandwidth_rgb565_kbps": bandwidth_rgb565,
		"bandwidth_palette_kbps": bandwidth_palette,
		"bandwidth_saving_pct": ((bandwidth_rgb565 - bandwidth_palette) / bandwidth_rgb565) * 100.0 if bandwidth_rgb565 > 0 else 0,
		"avg_psnr": avg_psnr,
		"avg_ssim": avg_ssim,
		"banding_artifacts_score": avg_banding,
		"test_duration_s": test_duration,
		"frames_rendered": _frames_rendered
	}
	
	_test_results.append(result)
	
	print("ColorFormatBenchmark: Test %d terminé" % (_current_test_index + 1))
	print("  RGB565: %.1f FPS, %.1f ms, %.1f KB VRAM" % [
		result.fps_rgb565, avg_frame_time_rgb565, avg_vram_rgb565 / 1024.0])
	print("  Palette: %.1f FPS, %.1f ms, %.1f KB VRAM" % [
		result.fps_palette, avg_frame_time_palette, avg_vram_palette / 1024.0])
	print("  PSNR: %.2f dB, SSIM: %.4f" % [avg_psnr, avg_ssim])
	print("  Banding score: %.4f" % avg_banding)
	
	_current_test_index += 1
	_run_next_test()


func _complete_benchmark() -> void:
	"""Termine le benchmark"""
	_is_testing = false
	print("\n" + "=".repeat(80))
	print("ColorFormatBenchmark: Benchmark terminé!")
	print("=".repeat(80))
	
	_analyze_results()
	
	if save_results:
		_save_results_to_file()
	
	benchmark_complete.emit(_test_results)


func _analyze_results() -> void:
	"""Analyse les résultats du benchmark"""
	if _test_results.size() == 0:
		push_warning("Aucun résultat à analyser")
		return
	
	print("\n=== ANALYSE COMPARATIVE ===")
	
	for result in _test_results:
		print("\nRésolution: %dx%d" % [result.resolution, result.resolution * 9/16])
		print("  Format RGB565:")
		print("    FPS: %.1f" % result.fps_rgb565)
		print("    Temps rendu: %.2f ms" % result.avg_frame_time_rgb565_ms)
		print("    VRAM: %.2f KB" % (result.vram_rgb565_bytes / 1024.0))
		print("  Format Palette 8-bit:")
		print("    FPS: %.1f" % result.fps_palette)
		print("    Temps rendu: %.2f ms" % result.avg_frame_time_palette_ms)
		print("    VRAM: %.2f KB" % (result.vram_palette_bytes / 1024.0))
		print("  Comparaison:")
		print("    Gain FPS: %.1f%%" % ((result.fps_palette - result.fps_rgb565) / result.fps_rgb565 * 100.0))
		print("    Économie VRAM: %.1f%%" % result.vram_saving_pct)
		print("    Économie bande passante: %.1f%%" % result.bandwidth_saving_pct)
		print("    Qualité PSNR: %.2f dB" % result.avg_psnr)
		print("    Similarité SSIM: %.4f" % result.avg_ssim)
		print("    Artefacts banding: %.4f" % result.banding_artifacts_score)
	
	# Recommandations
	print("\n=== RECOMMANDATIONS ===")
	for result in _test_results:
		var use_palette = result.fps_palette > result.fps_rgb565 and result.avg_psnr > 30.0
		print("Résolution %dx%d: %s" % [
			result.resolution, 
			result.resolution * 9/16,
			"Palette 8-bit recommandée" if use_palette else "RGB565 recommandé"])


func _save_results_to_file() -> void:
	"""Sauvegarde les résultats dans un fichier CSV"""
	var file = FileAccess.open(results_file, FileAccess.WRITE)
	if file == null:
		push_error("Impossible d'ouvrir le fichier de résultats: %s" % results_file)
		return
	
	# En-tête CSV
	file.store_line("TestIndex,Resolution,Format_RGB565,Format_Palette,UseDithering," +
		"FPS_RGB565,FPS_Palette,FrameTime_RGB565_ms,FrameTime_Palette_ms," +
		"VRAM_RGB565_Bytes,VRAM_Palette_Bytes,VRAM_Saving_Pct," +
		"Bandwidth_RGB565_KBps,Bandwidth_Palette_KBps,Bandwidth_Saving_Pct," +
		"PSNR,SSIM,BandingScore,TestDuration_s,FramesRendered")
	
	# Données
	for result in _test_results:
		var line = "%d,%d,%s,%s,%s," % [
			result.test_index,
			result.resolution,
			result.format_rgb565,
			result.format_palette,
			"true" if result.use_dithering else "false"]
		line += "%.1f,%.1f,%.2f,%.2f," % [
			result.fps_rgb565,
			result.fps_palette,
			result.avg_frame_time_rgb565_ms,
			result.avg_frame_time_palette_ms]
		line += "%.0f,%.0f,%.1f," % [
			result.vram_rgb565_bytes,
			result.vram_palette_bytes,
			result.vram_saving_pct]
		line += "%.1f,%.1f,%.1f," % [
			result.bandwidth_rgb565_kbps,
			result.bandwidth_palette_kbps,
			result.bandwidth_saving_pct]
		line += "%.2f,%.4f,%.4f,%.1f,%d" % [
			result.avg_psnr,
			result.avg_ssim,
			result.banding_artifacts_score,
			result.test_duration_s,
			result.frames_rendered]
		file.store_line(line)
	
	file.close()
	print("ColorFormatBenchmark: Résultats sauvegardés dans: %s" % results_file)


# API publique
func start_benchmark() -> void:
	"""Démarre le benchmark"""
	_start_benchmark()


func is_testing() -> bool:
	"""Vérifie si un benchmark est en cours"""
	return _is_testing


func get_results() -> Array:
	"""Retourne les résultats du benchmark"""
	return _test_results.duplicate()
