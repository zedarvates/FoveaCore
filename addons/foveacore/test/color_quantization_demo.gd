extends Node
class_name ColorQuantizationDemo
## Démonstration complète du système de quantification de couleurs
## pour les splats 3D Gaussian avec palette indexée et dithering

const ColorQuantization = preload("res://addons/foveacore/scripts/color_quantization.gd")
const GaussianSplat = preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

var demo_palette: Array[Color] = []
var demo_splats: Array[GaussianSplat] = []

func _ready() -> void:
	print("\n" + "=".repeat(70))
	print("DÉMONSTRATION: Quantification de couleurs pour Gaussian Splats")
	print("=".repeat(70))
	
	demo_palette = generate_demo_palette()
	demo_splats = generate_demo_splats(1000)
	
	run_demo()

func generate_demo_palette() -> Array[Color]:
	"""Génère une palette de démo avec des couleurs représentatives"""
	var palette: Array[Color] = []
	
	# Couleurs de base
	var base_colors = [
		Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1),
		Color(1, 1, 0), Color(1, 0, 1), Color(0, 1, 1),
		Color(1, 0.5, 0), Color(0.5, 0, 1), Color(0, 1, 0.5),
		Color(1, 1, 1), Color(0, 0, 0), Color(0.5, 0.5, 0.5)
	]
	
	# Ajouter des variations
	for base in base_colors:
		palette.append(base)
		for i in range(5):
			var variation = Color(
				clamp(base.r + randf_range(-0.2, 0.2), 0, 1),
				clamp(base.g + randf_range(-0.2, 0.2), 0, 1),
				clamp(base.b + randf_range(-0.2, 0.2), 0, 1)
			)
			palette.append(variation)
	
	# Remplir jusqu'à 256 couleurs
	while palette.size() < 256:
		palette.append(Color(randf(), randf(), randf()))
	
	return palette.slice(0, 256)

func generate_demo_splats(count: int) -> Array[GaussianSplat]:
	"""Génère des splats de démo avec des couleurs variées"""
	var splats: Array[GaussianSplat] = []
	
	for i in range(count):
		var pos = Vector3(
			randf_range(-10, 10),
			randf_range(-10, 10),
			randf_range(-10, 10)
		)
		
		var splat = GaussianSplat.new(pos)
		splat.color = Color(randf(), randf(), randf())
		splat.opacity = randf_range(0.5, 1.0)
		splat.scale = Vector3.ONE * randf_range(0.1, 0.5)
		splat.compute_derived()
		
		# Quantifier la couleur
		splat.quantize_color(demo_palette)
		splat.dither_seed = splat.generate_dither_seed()
		
		splats.append(splat)
	
	return splats

func run_demo() -> void:
	print("\n1. PALETTE DE COULEURS GÉNÉRÉE")
	print("   Nombre de couleurs: ", demo_palette.size())
	print("   Format: RGB (32-bit float par composante)")
	
	print("\n2. CRÉATION DES SPLATS")
	print("   Nombre de splats: ", demo_splats.size())
	
	# Calculer statistiques
	var total_memory_old = 0
	var total_memory_new = 0
	var total_error = 0.0
	
	for splat in demo_splats:
		total_memory_old += splat.get_memory_usage(false)  # RGB565
		total_memory_new += splat.get_memory_usage(true)   # Palette
		
		var error = splat.get_quantization_error(splat.color, demo_palette)
		total_error += error
	
	var avg_error = total_error / demo_splats.size()
	
	print("\n3. COMPARAISON MÉMOIRE")
	print("   Format RGB565:    ", total_memory_old, " octets (", total_memory_old / 1024, " KB)")
	print("   Format Palette:   ", total_memory_new, " octets (", total_memory_new / 1024, " KB)")
	print("   Économie:         ", total_memory_old - total_memory_new, " octets")
	print("   Ratio:            %.2fx" % (float(total_memory_old) / float(total_memory_new)))
	
	print("\n4. ERREUR DE QUANTIFICATION")
	print("   Erreur moyenne:   ", avg_error)
	print("   (0 = parfait, 1 = maximum)")
	
	# Test de dithering
	print("\n5. TEST DITHERING")
	var test_color = Color(0.5, 0.5, 0.5)
	var error_color = Color(0.1, -0.1, 0.05)
	var dithered = test_color
	
	for i in range(3):
		dithered = GaussianSplat.apply_dithering_static(dithered, i, i, error_color)
	
	print("   Couleur originale: ", test_color)
	print("   Après dithering:   ", dithered)
	
	# Performance
	print("\n6. PERFORMANCE")
	var start = Time.get_ticks_usec()
	for i in range(1000):
		var s = demo_splats[i % demo_splats.size()]
		s.quantize_color(demo_palette)
	var elapsed = Time.get_ticks_usec() - start
	
	print("   1000 quantifications: ", elapsed, " µs")
	print("   Par quantification:   ", float(elapsed) / 1000.0, " µs")
	
	print("\n" + "=".repeat(70))
	print("DÉMONSTRATION TERMINÉE")
	print("=".repeat(70))

static func apply_dithering_static(color: Color, x: int, y: int, error: Color) -> Color:
	"""Version statique pour test"""
	return Color(
		clamp(color.r + error.r * 7.0 / 16.0, 0.0, 1.0),
		clamp(color.g + error.g * 7.0 / 16.0, 0.0, 1.0),
		clamp(color.b + error.b * 7.0 / 16.0, 0.0, 1.0)
	)
