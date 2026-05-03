extends Node
class_name ColorQuantizationTest
## Test de quantification de couleurs et comparaison mémoire/performance
## pour les splats 3D Gaussian avec palette indexée

const ColorQuantization = preload("res://addons/foveacore/scripts/color_quantization.gd")
const GaussianSplat = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

var test_results: Dictionary = {}

func _ready() -> void:
	print("=== DÉMARRAGE DES TESTS DE QUANTIFICATION DE COULEURS ===")
	run_all_tests()

func run_all_tests() -> void:
	print("\n--- Test 1: K-Means sur couleurs aléatoires ---")
	test_kmeans_random_colors()
	
	print("\n--- Test 2: Median Cut sur couleurs ---")
	test_median_cut()
	
	print("\n--- Test 3: Comparaison mémoire RGB565 vs Palette 8-bit ---")
	test_memory_comparison()
	
	print("\n--- Test 4: Dithering Floyd-Steinberg ---")
	test_floyd_steinberg()
	
	print("\n--- Test 5: Quantification sur image réelle ---")
	test_quantization_on_image()
	
	print("\n--- Test 6: Performance conversion 100k splats ---")
	test_performance_large_dataset()
	
	print("\n=== RÉSUMÉ DES RÉSULTATS ===")
	print_results_summary()

func test_kmeans_random_colors() -> void:
	var colors: Array[Color] = []
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Générer 1000 couleurs aléatoires
	for i in range(1000):
		colors.append(Color(rng.randf(), rng.randf(), rng.randf()))
	
	var start_time = Time.get_ticks_msec()
	var result = ColorQuantization.kmeans_quantize(colors, 256)
	var elapsed = Time.get_ticks_msec() - start_time
	
	print("  Nombre de couleurs originales: ", colors.size())
	print("  Nombre de clusters: ", result.palette.size())
	print("  Temps de traitement: ", elapsed, " ms")
	print("  Erreur de quantification: ", result.stats["quantization_error"])
	
	test_results["kmeans"] = {
		"colors": colors.size(),
		"clusters": result.palette.size(),
		"time_ms": elapsed,
		"error": result.stats["quantization_error"]
	}
	
	# Vérifier que la palette a bien été réduite
	assert(result.palette.size() <= 256, "Palette trop grande")
	assert(result.palette.size() > 0, "Palette vide")

func test_median_cut() -> void:
	var colors: Array[Color] = []
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Générer 500 couleurs avec distribution non uniforme
	for i in range(500):
		if i < 200:
			# Cluster rouge
			colors.append(Color(rng.randf_range(0.7, 1.0), rng.randf_range(0.0, 0.3), rng.randf_range(0.0, 0.3)))
		elif i < 350:
			# Cluster vert
			colors.append(Color(rng.randf_range(0.0, 0.3), rng.randf_range(0.7, 1.0), rng.randf_range(0.0, 0.3)))
		else:
			# Cluster bleu
			colors.append(Color(rng.randf_range(0.0, 0.3), rng.randf_range(0.0, 0.3), rng.randf_range(0.7, 1.0)))
	
	var start_time = Time.get_ticks_msec()
	var result = ColorQuantization.median_cut_quantize(colors, 16)
	var elapsed = Time.get_ticks_msec() - start_time
	
	print("  Nombre de couleurs originales: ", colors.size())
	print("  Nombre de couleurs après Median Cut: ", result.palette.size())
	print("  Temps de traitement: ", elapsed, " ms")
	
	test_results["median_cut"] = {
		"colors": colors.size(),
		"quantized": result.palette.size(),
		"time_ms": elapsed
	}
	
	assert(result.palette.size() <= 16, "Trop de couleurs après Median Cut")

func test_memory_comparison() -> void:
	var num_splats = 100000
	
	# Calcul mémoire RGB565 (ancien format)
	var rgb565_per_splat = 2  # 2 octets pour la couleur
	var rgb565_total = num_splats * rgb565_per_splat
	
	# Calcul mémoire palette 8-bit (nouveau format)
	var palette_size = 256 * 3 * 4  # 256 couleurs * 3 floats * 4 bytes
	var index_per_splat = 1  # 1 octet pour l'index
	var palette_total = palette_size + (num_splats * index_per_splat)
	
	# Mémoire totale par splat
	var rgb565_per_splat_total = rgb565_per_splat  # Juste la couleur
	var palette_per_splat_total = (palette_size / num_splats) + index_per_splat
	
	print("  Nombre de splats: ", num_splats)
	print("  RGB565: ", rgb565_total, " octets (", rgb565_per_splat, " octets/splat)")
	print("  Palette 8-bit: ", palette_total, " octets (", palette_per_splat_total, " octets/splat)")
	print("  Économie mémoire: ", rgb565_total - palette_total, " octets")
	print("  Ratio: ", float(rgb565_total) / float(palette_total), "x")
	
	# Avec structure complète (16 octets vs 20 octets)
	var struct_old = 20  # RGB565 + padding
	var struct_new = 16  # Index 8-bit + padding
	var savings_struct = (struct_old - struct_new) * num_splats
	
	print("  \n  Structure complète:")
	print("    Ancien format: ", struct_old, " octets/splat")
	print("    Nouveau format: ", struct_new, " octets/splat")
	print("    Économie: ", savings_struct, " octets (", (savings_struct * 100.0) / (struct_old * num_splats), "%)")
	
test_results["memory"] = {
		"num_splats": num_splats,
		"rgb565_total": rgb565_total,
		"palette_total": palette_total,
		"savings": rgb565_total - palette_total,
		"struct_savings": savings_struct
	}

func test_floyd_steinberg() -> void:
	# Créer une image de test avec des dégradés
	var img = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	
	for y in range(256):
		for x in range(256):
			var r = float(x) / 255.0
			var g = float(y) / 255.0
			var b = (float(x + y) / 512.0)
			img.set_pixel(x, y, Color(r, g, b))
	
	var start_time = Time.get_ticks_msec()
	var dithered = ColorQuantization.apply_floyd_steinberg_dither(img)
	var elapsed = Time.get_ticks_msec() - start_time
	
	print("  Taille image: 256x256")
	print("  Temps de dithering: ", elapsed, " ms")
	print("  Pixels traités: ", 256 * 256)
	
	test_results["dithering"] = {
		"image_size": 256 * 256,
		"time_ms": elapsed
	}

func test_quantization_on_image() -> void:
	# Créer une image de test
	var img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for y in range(64):
		for x in range(64):
			img.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf()))
	
	var start_time = Time.get_ticks_msec()
	var result = ColorQuantization.generate_palette_from_image(img, 256, "kmeans")
	var elapsed = Time.get_ticks_msec() - start_time
	
	print("  Taille image: 64x64")
	print("  Couleurs uniques: ", result.stats["original_colors"])
	print("  Couleurs quantifiées: ", result.palette.size())
	print("  Temps: ", elapsed, " ms")
	print("  Méthode: ", result.stats["method"])
	
test_results["image_quantization"] = {
		"pixels": 64 * 64,
		"colors": result.palette.size(),
		"time_ms": elapsed
	}

func test_performance_large_dataset() -> void:
	var num_splats = 100000
	var colors: Array[Color] = []
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Simuler des couleurs de splats
	for i in range(num_splats):
		colors.append(Color(rng.randf(), rng.randf(), rng.randf()))
	
	var start_time = Time.get_ticks_msec()
	var result = ColorQuantization.kmeans_quantize(colors, 256)
	var elapsed = Time.get_ticks_msec() - start_time
	
	print("  Nombre de splats: ", num_splats)
	print("  Temps de quantification: ", elapsed, " ms")
	print("  Splats par seconde: ", int(num_splats / (elapsed / 1000.0)))
	print("  Couleurs dans palette: ", result.palette.size())
	
	test_results["performance"] = {
		"num_splats": num_splats,
		"time_ms": elapsed,
		"splats_per_sec": num_splats / (elapsed / 1000.0),
		"palette_size": result.palette.size()
	}

func print_results_summary() -> void:
	print("\n" + "=".repeat(50))
	print("RÉSUMÉ DES PERFORMANCES")
	print("=".repeat(50))
	
	if "kmeans" in test_results:
		var r = test_results["kmeans"]
		print("K-Means: %d couleurs -> %d clusters en %d ms" % [r.colors, r.clusters, r.time_ms])
	
	if "memory" in test_results:
		var r = test_results["memory"]
		print("Mémoire: %d splats, économie de %d octets (%.1f%%)" % [
			r.num_splats, r.savings, (r.savings * 100.0) / r.rgb565_total
		])
	
	if "performance" in test_results:
		var r = test_results["performance"]
		print("Performance: %.0f splats/seconde" % r.splats_per_sec)
	
	print("\n=== TESTS COMPLÉTÉS ===")

func _process(delta: float) -> void:
	# Stoppe le process après les tests
	set_process(false)
