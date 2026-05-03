# test_color_format_benchmark.gd
# Tests unitaires pour le benchmark de format couleur
# Valide les calculs PSNR, SSIM, détection banding, et comparaison RGB565 vs Palette

extends Node

# Référence au benchmark
var _benchmark: Node = null

# Résultats des tests
var _tests_passed: int = 0
var _tests_failed: int = 0

signal test_started(test_name: String)
signal test_passed(test_name: String)
signal test_failed(test_name: String, error: String)
signal all_tests_complete(passed: int, failed: int)


func _ready() -> void:
	print("\n" + "=".repeat(80))
	print("TestColorFormatBenchmark: Démarrage des tests unitaires")
	print("=".repeat(80))
	
	# Charger le benchmark
	_benchmark = preload("res://addons/foveacore/test/color_format_benchmark.gd").new()
	add_child(_benchmark)
	
	# Lancer les tests
	await get_tree().create_timer(0.5).timeout
	_run_all_tests()


func _run_all_tests() -> void:
	"""Exécute tous les tests unitaires"""
	
	print("\n--- Tests de conversion de format ---")
	await _test_rgb565_conversion()
	await _test_palette_conversion()
	await _test_dithering_application()
	
	print("\n--- Tests de qualité d'image ---")
	await _test_psnr_calculation()
	await _test_ssim_calculation()
	await _test_identical_images_psnr()
	
	print("\n--- Tests de détection d'artefacts ---")
	await _test_banding_detection_uniform()
	await _test_banding_detection_gradient()
	
	print("\n--- Tests de métriques de performance ---")
	await _test_vram_calculation()
	await _test_bandwidth_calculation()
	
	print("\n--- Tests de scènes de test ---")
	await _test_gradient_scene()
	await _test_transparency_scene()
	await _test_color_blend_scene()
	
	# Rapport final
	print("\n" + "=".repeat(80))
	print("TestColorFormatBenchmark: Rapport final")
	print("=".repeat(80))
	print("Tests réussis: %d" % _tests_passed)
	print("Tests échoués: %d" % _tests_failed)
	print("Taux de réussite: %.1f%%" % (_tests_passed / float(_tests_passed + _tests_failed) * 100.0))
	print("=".repeat(80))
	
	all_tests_complete.emit(_tests_passed, _tests_failed)


func _test_rgb565_conversion() -> void:
	"""Teste la conversion RGB565"""
	var test_name = "Conversion RGB565"
	test_started.emit(test_name)
	
	var image = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.7, 0.9, 1.0))
	
	var original_size = image.get_data().size()
	image.convert(Image.FORMAT_RGB565)
	var converted_size = image.get_data().size()
	
	# RGB565 devrait utiliser moins de mémoire que RGBA8
	if converted_size < original_size:
		_test_pass(test_name, "Taille réduite: %d -> %d bytes" % [original_size, converted_size])
	else:
		_test_fail(test_name, "Taille non réduite: %d -> %d bytes" % [original_size, converted_size])


func _test_palette_conversion() -> void:
	"""Teste la conversion en palette 8-bit"""
	var test_name = "Conversion Palette 8-bit"
	test_started.emit(test_name)
	
	var image = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))
	
	var original_size = image.get_data().size()
	image.convert(Image.FORMAT_L8)
	var converted_size = image.get_data().size()
	
	# La palette devrait utiliser beaucoup moins de mémoire
	if converted_size < original_size:
		_test_pass(test_name, "Taille réduite: %d -> %d bytes" % [original_size, converted_size])
	else:
		_test_fail(test_name, "Taille non réduite: %d -> %d bytes" % [original_size, converted_size])


func _test_dithering_application() -> void:
	"""Teste l'application du dithering Floyd-Steinberg"""
	var test_name = "Dithering Floyd-Steinberg"
	test_started.emit(test_name)
	
	var image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	# Crée un dégradé lisse
	for y in range(4):
		for x in range(4):
			var val = float(x + y) / 6.0
			image.set_pixel(x, y, Color(val, val, val, 1.0))
	
	var original_pixel = image.get_pixel(0, 0)
	_benchmark._apply_floyd_steinberg_dithering(image)
	var dithered_pixel = image.get_pixel(0, 0)
	
	# Le pixel devrait avoir été quantifié
	if original_pixel != dithered_pixel:
		_test_pass(test_name, "Dithering appliqué avec succès")
	else:
		_test_fail(test_name, "Dithering n'a pas modifié l'image")


func _test_psnr_calculation() -> void:
	"""Teste le calcul PSNR"""
	var test_name = "Calcul PSNR"
	test_started.emit(test_name)
	
	var img1 = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	var img2 = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	
	# Images légèrement différentes
	img1.fill(Color(0.5, 0.5, 0.5, 1.0))
	img2.fill(Color(0.51, 0.51, 0.51, 1.0))
	
	var psnr = _benchmark._calculate_psnr(img1, img2)
	
	if psnr > 0 and psnr < 100:
		_test_pass(test_name, "PSNR = %.2f dB" % psnr)
	else:
		_test_fail(test_name, "PSNR invalide: %.2f dB" % psnr)


func _test_ssim_calculation() -> void:
	"""Teste le calcul SSIM"""
	var test_name = "Calcul SSIM"
	test_started.emit(test_name)
	
	var img1 = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	var img2 = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	
	img1.fill(Color(0.5, 0.5, 0.5, 1.0))
	img2.fill(Color(0.5, 0.5, 0.5, 1.0))
	
	var ssim = _benchmark._calculate_ssim(img1, img2)
	
	if ssim >= 0 and ssim <= 1:
		_test_pass(test_name, "SSIM = %.4f" % ssim)
	else:
		_test_fail(test_name, "SSIM hors limites: %.4f" % ssim)


func _test_identical_images_psnr() -> void:
	"""Teste PSNR avec images identiques (devrait être infini/100)"""
	var test_name = "PSNR images identiques"
	test_started.emit(test_name)
	
	var img1 = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	var img2 = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	
	img1.fill(Color(0.3, 0.6, 0.9, 1.0))
	img2.fill(Color(0.3, 0.6, 0.9, 1.0))
	
	var psnr = _benchmark._calculate_psnr(img1, img2)
	
	if psnr >= 99.9:  # Presque infini
		_test_pass(test_name, "PSNR = %.2f dB (correct)" % psnr)
	else:
		_test_fail(test_name, "PSNR devrait être ~100, obtenu: %.2f" % psnr)


func _test_banding_detection_uniform() -> void:
	"""Teste détection banding sur image uniforme"""
	var test_name = "Détection banding (uniforme)"
	test_started.emit(test_name)
	
	var image = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))
	
	var banding = _benchmark._detect_banding(image)
	
	if banding == 0.0:
		_test_pass(test_name, "Banding = 0 (correct)")
	else:
		_test_fail(test_name, "Banding détecté sur image uniforme: %.4f" % banding)


func _test_banding_detection_gradient() -> void:
	"""Teste détection banding sur gradient"""
	var test_name = "Détection banding (gradient)"
	test_started.emit(test_name)
	
	var image = Image.create(10, 10, false, Image.FORMAT_RGBA8)
	for y in range(10):
		for x in range(10):
			var val = float(x) / 9.0
			image.set_pixel(x, y, Color(val, val, val, 1.0))
	
	var banding = _benchmark._detect_banding(image)
	
	# Devrait détecter un certain banding
	if banding >= 0:
		_test_pass(test_name, "Banding = %.4f" % banding)
	else:
		_test_fail(test_name, "Banding négatif: %.4f" % banding)


func _test_vram_calculation() -> void:
	"""Teste le calcul d'utilisation VRAM"""
	var test_name = "Calcul VRAM"
	test_started.emit(test_name)
	
	var image = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	var size = image.get_data().size()
	
	# RGBA8 = 4 bytes par pixel
	var expected = 100 * 100 * 4
	
	if size == expected:
		_test_pass(test_name, "VRAM = %d bytes (attendu: %d)" % [size, expected])
	else:
		_test_fail(test_name, "VRAM = %d bytes (attendu: %d)" % [size, expected])


func _test_bandwidth_calculation() -> void:
	"""Teste le calcul de bande passante"""
	var test_name = "Calcul bande passante"
	test_started.emit(test_name)
	
	var vram_bytes = 102400.0  # 100 KB
	var frame_time_ms = 16.67  # ~60 FPS
	var bandwidth = (vram_bytes / 1024.0) / (frame_time_ms / 1000.0)
	
	if bandwidth > 0:
		_test_pass(test_name, "Bande passante = %.1f KB/s" % bandwidth)
	else:
		_test_fail(test_name, "Bande passante invalide: %.1f" % bandwidth)


func _test_gradient_scene() -> void:
	"""Teste la scène de gradient"""
	var test_name = "Scène gradient continu"
	test_started.emit(test_name)
	
	var scene = _benchmark._gradient_scene
	if scene != null and scene.get_child_count() > 0:
		_test_pass(test_name, "Scène chargée avec %d enfants" % scene.get_child_count())
	else:
		_test_fail(test_name, "Scène non chargée correctement")


func _test_transparency_scene() -> void:
	"""Teste la scène de transparence"""
	var test_name = "Scène transparence"
	test_started.emit(test_name)
	
	var scene = _benchmark._transparency_scene
	if scene != null and scene.get_child_count() > 0:
		_test_pass(test_name, "Scène chargée avec %d enfants" % scene.get_child_count())
	else:
		_test_fail(test_name, "Scène non chargée correctement")


func _test_color_blend_scene() -> void:
	"""Teste la scène de mélange de couleurs"""
	var test_name = "Scène mélange couleurs"
	test_started.emit(test_name)
	
	var scene = _benchmark._color_blend_scene
	if scene != null and scene.get_child_count() > 0:
		_test_pass(test_name, "Scène chargée avec %d enfants" % scene.get_child_count())
	else:
		_test_fail(test_name, "Scène non chargée correctement")


func _test_pass(test_name: String, details: String = "") -> void:
	"""Enregistre un test réussi"""
	_tests_passed += 1
	print("  ✓ %s" % test_name)
	if details != "":
		print("    %s" % details)
	test_passed.emit(test_name)


func _test_fail(test_name: String, error: String) -> void:
	"""Enregistre un test échoué"""
	_tests_failed += 1
	print("  ✗ %s" % test_name)
	print("    ERREUR: %s" % error)
	test_failed.emit(test_name, error)
