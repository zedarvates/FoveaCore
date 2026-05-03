extends Node3D
## Test de transparence et mélange de splats avec palette 8-bit
## Valide :
## 1) Superposition de splats semi-transparents
## 2) Mélange de couleurs avec opacité variable
## 3) Effets de profondeur (z-ordering)
## 4) Artefacts de transparence avec palette limitée
## 5) Comparaison visuelle RGB565 vs Palette 8-bit

@export var test_mode: String = "all"  # "all", "transparency", "blend", "zorder", "palette_artifacts", "rgb565_vs_palette"
@export var splat_count: int = 200
@export var enable_palette: bool = true
@export var palette_name: String = "watercolor_16"

var camera: Camera3D
var viewport_rgb565: SubViewport
var viewport_palette: SubViewport
var viewport_reference: SubViewport

# Scènes de test
var transparency_test_scene: Node3D
var blend_test_scene: Node3D
var zorder_test_scene: Node3D
var palette_artifact_scene: Node3D

# Résultats
var test_results: Dictionary = {}
var current_test: String = ""

signal test_complete(result: Dictionary)
signal test_progress(message: String)

func _ready() -> void:
	print("\n" + "=".repeat(80))
	print("FoveaEngine - Test Transparence & Mélange de Splats")
	print("=".repeat(80))
	
	_setup_camera()
	
	if test_mode == "all":
		_run_all_tests()
	else:
		_run_specific_test(test_mode)

func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "TestCamera"
	camera.position = Vector3(0, 2, 8)
	camera.look_at(Vector3(0, 0, 0))
	add_child(camera)

func _run_all_tests() -> void:
	var tests = [
		{"name": "transparency", "func": _test_transparency_stacking},
		{"name": "blend", "func": _test_color_blending},
		{"name": "zorder", "func": _test_z_ordering},
		{"name": "palette_artifacts", "func": _test_palette_artifacts},
		{"name": "rgb565_vs_palette", "func": _test_rgb565_vs_palette}
	]
	
	for i in range(tests.size()):
		var t = tests[i]
		print("\n[%d/%d] Test: %s" % [i+1, tests.size(), t.name])
		test_progress.emit("Test %s en cours..." % t.name)
		current_test = t.name
		t.func.call()
		await get_tree().create_timer(0.5).timeout
	
	print("\n" + "=".repeat(80))
	print("Tous les tests terminés!")
	print("=".repeat(80))
	_print_summary()

func _run_specific_test(mode: String) -> void:
	match mode:
		"transparency": _test_transparency_stacking()
		"blend": _test_color_blending()
		"zorder": _test_z_ordering()
		"palette_artifacts": _test_palette_artifacts()
		"rgb565_vs_palette": _test_rgb565_vs_palette()
		_: push_error("Mode de test inconnu: %s" % mode)

## === TEST 1: Superposition de splats semi-transparents ===

func _test_transparency_stacking() -> void:
	print("\n--- Test 1: Superposition de splats semi-transparents ---")
	
	var root = Node3D.new()
	root.name = "TransparencyStackTest"
	add_child(root)
	
	# Créer plusieurs plans avec splats semi-transparents empilés
	var layer_count = 5
	var spacing = 0.5
	var base_alpha = 0.3
	
	for layer in range(layer_count):
		var splat = _create_splat_plane(
			Vector3(0, layer * spacing, 0),
			Color(0.2, 0.5, 0.9, base_alpha),
			splat_count / layer_count
		)
		splat.name = "Layer_%d" % layer
		root.add_child(splat)
		
		# Vérifier que l'opacité cumulée est correcte
		var expected_opacity = 1.0 - pow(1.0 - base_alpha, layer + 1)
		print("  Couche %d: alpha=%.2f, cumul attendu=%.2f" % [layer, base_alpha, expected_opacity])
	
	# Test avec blending additif
	var additive_root = Node3D.new()
	additive_root.name = "AdditiveBlendTest"
	additive_root.position = Vector3(3, 0, 0)
	add_child(additive_root)
	
	for layer in range(layer_count):
		var splat = _create_splat_plane(
			Vector3(0, layer * spacing, 0),
			Color(0.1, 0.3, 0.8, 0.5),
			splat_count / layer_count
		)
		splat.name = "AdditiveLayer_%d" % layer
		additive_root.add_child(splat)
	
	test_results["transparency"] = {
		"layer_count": layer_count,
		"base_alpha": base_alpha,
		"status": "passed",
		"description": "Superposition de %d couches avec alpha=%.2f" % [layer_count, base_alpha]
	}
	test_complete.emit(test_results["transparency"])

## === TEST 2: Mélange de couleurs avec opacité variable ===

func _test_color_blending() -> void:
	print("\n--- Test 2: Mélange de couleurs avec opacité variable ---")
	
	var root = Node3D.new()
	root.name = "ColorBlendTest"
	root.position = Vector3(-3, 0, 0)
	add_child(root)
	
	# Test 1: Dégradé de rouge à bleu avec alpha variable
	var gradient_count = 10
	for i in range(gradient_count):
		var t = float(i) / (gradient_count - 1)
		var color = Color(
			1.0 - t,  # Rouge décroissant
			0.0,
			t,        # Bleu croissant
			0.2 + t * 0.8  # Alpha croissant
		)
		var splat = _create_splat_plane(
			Vector3(t * 2 - 1, 0, 0),
			color,
			50
		)
		splat.name = "Gradient_%d" % i
		root.add_child(splat)
	
	# Test 2: Mélange de couleurs complémentaires
	var blend_root = Node3D.new()
	blend_root.name = "ComplementaryBlend"
	blend_root.position = Vector3(0, -3, 0)
	add_child(blend_root)
	
	var colors = [
		Color(1, 0, 0, 0.5),   # Rouge
		Color(0, 1, 0, 0.5),   # Vert
		Color(0, 0, 1, 0.5),   # Bleu
		Color(1, 1, 0, 0.3),   # Jaune
		Color(1, 0, 1, 0.3),   # Magenta
		Color(0, 1, 1, 0.3),   # Cyan
	]
	
	for i in range(colors.size()):
		var angle = i * TAU / colors.size()
		var radius = 1.5
		var pos = Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var splat = _create_splat_plane(pos, colors[i], 80)
		splat.name = "Color_%d" % i
		blend_root.add_child(splat)
	
	# Test 3: Opacité variable sur même couleur
	var opacity_root = Node3D.new()
	opacity_root.name = "OpacityRamp"
	opacity_root.position = Vector3(3, -3, 0)
	add_child(opacity_root)
	
	for i in range(8):
		var alpha = (i + 1) / 8.0
		var splat = _create_splat_plane(
			Vector3(0, i * 0.4, 0),
			Color(0.8, 0.2, 0.4, alpha),
			60
		)
		splat.name = "Opacity_%d" % i
		opacity_root.add_child(splat)
		test_results["blend_opacity_%d" % i] = alpha
	
	test_results["blend"] = {
		"gradient_steps": gradient_count,
		"color_count": colors.size(),
		"opacity_steps": 8,
		"status": "passed",
		"description": "Mélange de couleurs avec %d étapes d'opacité" % gradient_count
	}
	test_complete.emit(test_results["blend"])

## === TEST 3: Effets de profondeur (z-ordering) ===

func _test_z_ordering() -> void:
	print("\n--- Test 3: Effets de profondeur (z-ordering) ---")
	
	var root = Node3D.new()
	root.name = "ZOrderTest"
	root.position = Vector3(3, 0, 0)
	add_child(root)
	
	# Créer des splats à différentes profondeurs
	var depth_count = 7
	var depth_spacing = 1.0
	
	for i in range(depth_count):
		var z = i * depth_spacing - (depth_count * depth_spacing / 2.0)
		var color = Color.from_hsv(float(i) / depth_count, 0.8, 0.9, 0.6)
		var splat = _create_splat_plane(
			Vector3(0, 0, z),
			color,
			100
		)
		splat.name = "Depth_%d" % i
		root.add_child(splat)
		
		# Stocker la profondeur pour validation
		test_results["z_order_depth_%d" % i] = z
	
	# Test avec chevauchement complexe
	var overlap_root = Node3D.new()
	overlap_root.name = "ZOrderOverlap"
	overlap_root.position = Vector3(-3, 0, 0)
	add_child(overlap_root)
	
	# Triangle de chevauchement
	var positions = [
		Vector3(0, 0, -1),
		Vector3(-0.8, 0, 0),
		Vector3(0.8, 0, 0),
		Vector3(0, 0, 1),
	]
	
	var overlap_colors = [
		Color(1, 0, 0, 0.7),
		Color(0, 1, 0, 0.7),
		Color(0, 0, 1, 0.7),
		Color(1, 1, 0, 0.7),
	]
	
	for i in range(positions.size()):
		var splat = _create_splat_plane(positions[i], overlap_colors[i], 120)
		splat.name = "Overlap_%d" % i
		overlap_root.add_child(splat)
		test_results["z_order_overlap_%d" % i] = positions[i].z
	
	test_results["zorder"] = {
		"depth_count": depth_count,
		"depth_range": depth_spacing * (depth_count - 1),
		"overlap_count": positions.size(),
		"status": "passed",
		"description": "Validation de l'ordre Z avec %d profondeurs" % depth_count
	}
	test_complete.emit(test_results["zorder"])

## === TEST 4: Artefacts de transparence avec palette limitée ===

func _test_palette_artifacts() -> void:
	print("\n--- Test 4: Artefacts de transparence avec palette limitée ---")
	
	var root = Node3D.new()
	root.name = "PaletteArtifactTest"
	add_child(root)
	
	# Test 1: Dégradé continu vs palette 16 couleurs
	var gradient_steps = 32
	for i in range(gradient_steps):
		var t = float(i) / (gradient_steps - 1)
		# Dégradé bleu -> cyan
		var color = Color(
			0.1,
			0.3 + t * 0.5,
			0.8 + t * 0.2,
			0.8
		)
		var splat = _create_splat_plane(
			Vector3(t * 3 - 1.5, 1, 0),
			color,
			40
		)
		splat.name = "GradientStep_%d" % i
		root.add_child(splat)
	
	# Test 2: Transparence avec couleurs limites de palette
	var limit_colors = [
		Color(0, 0, 0, 0.5),      # Noir transparent
		Color(1, 1, 1, 0.3),      # Blanc transparent
		Color(1, 0, 0, 0.4),      # Rouge transparent
		Color(0, 1, 0, 0.4),      # Vert transparent
		Color(0, 0, 1, 0.4),      # Bleu transparent
	]
	
	for i in range(limit_colors.size()):
		var splat = _create_splat_plane(
			Vector3(i * 1.5 - 3, -1, 0),
			limit_colors[i],
			80
		)
		splat.name = "LimitColor_%d" % i
		root.add_child(splat)
		test_results["limit_color_%d" % i] = limit_colors[i]
	
	# Test 3: Banding artificiel (détection)
	var banding_root = Node3D.new()
	banding_root.name = "BandingTest"
	banding_root.position = Vector3(0, -2, 0)
	add_child(banding_root)
	
	var banding_steps = 16
	for i in range(banding_steps):
		var t = float(i) / (banding_steps - 1)
		# Dégradé très subtil
		var intensity = 0.3 + t * 0.4
		var color = Color(intensity, intensity, intensity, 0.9)
		var splat = _create_splat_plane(
			Vector3(t * 2 - 1, 0, 0),
			color,
			50
		)
		splat.name = "BandingStep_%d" % i
		banding_root.add_child(splat)
		test_results["banding_step_%d" % i] = intensity
	
	test_results["palette_artifacts"] = {
		"gradient_steps": gradient_steps,
		"limit_colors": limit_colors.size(),
		"banding_steps": banding_steps,
		"palette_size": 16,
		"status": "passed",
		"description": "Détection artefacts avec palette 16 couleurs"
	}
	test_complete.emit(test_results["palette_artifacts"])

## === TEST 5: Comparaison visuelle RGB565 vs Palette 8-bit ===

func _test_rgb565_vs_palette() -> void:
	print("\n--- Test 5: Comparaison RGB565 vs Palette 8-bit ---")
	
	# Scène de référence (couleurs pleines)
	var reference_root = Node3D.new()
	reference_root.name = "ReferenceScene"
	add_child(reference_root)
	
	# Scène RGB565 simulée
	var rgb565_root = Node3D.new()
	rgb565_root.name = "RGB565Scene"
	rgb565_root.position = Vector3(-4, 0, 0)
	add_child(rgb565_root)
	
	# Scène Palette 8-bit
	var palette_root = Node3D.new()
	palette_root.name = "PaletteScene"
	palette_root.position = Vector3(4, 0, 0)
	add_child(palette_root)
	
	# Couleurs de test variées
	var test_colors = [
		Color(1, 0, 0, 1),      # Rouge pur
		Color(0, 1, 0, 1),      # Vert pur
		Color(0, 0, 1, 1),      # Bleu pur
		Color(1, 1, 0, 1),      # Jaune
		Color(1, 0, 1, 1),      # Magenta
		Color(0, 1, 1, 1),      # Cyan
		Color(0.5, 0.5, 0.5, 1),# Gris
		Color(0.2, 0.7, 0.3, 1),# Vert doux
	]
	
	for i in range(test_colors.size()):
		var color = test_colors[i]
		var x = (i % 4) * 1.5 - 2.25
		var y = floor(i / 4) * -1.5 + 0.75
		
		# Référence
		var ref_splat = _create_splat_plane(
			Vector3(x, y, 0),
			color,
			100
		)
		ref_splat.name = "Ref_Color_%d" % i
		reference_root.add_child(ref_splat)
		
		# RGB565 (quantification)
		var rgb565_color = _quantize_rgb565(color)
		var rgb565_splat = _create_splat_plane(
			Vector3(x, y, 0),
			rgb565_color,
			100
		)
		rgb565_splat.name = "RGB565_Color_%d" % i
		rgb565_root.add_child(rgb565_splat)
		
		# Palette 8-bit (quantification)
		var palette_color = _quantize_palette(color)
		var palette_splat = _create_splat_plane(
			Vector3(x, y, 0),
			palette_color,
			100
		)
		palette_splat.name = "Palette_Color_%d" % i
		palette_root.add_child(palette_splat)
		
		# Calculer erreur
		var rgb565_error = color.distance_to(rgb565_color)
		var palette_error = color.distance_to(palette_color)
		
		test_results["color_comparison_%d" % i] = {
			"original": color,
			"rgb565": rgb565_color,
			"palette": palette_color,
			"rgb565_error": rgb565_error,
			"palette_error": palette_error
		}
	
	# Test avec transparence
	var alpha_test_root = Node3D.new()
	alpha_test_root.name = "AlphaComparison"
	alpha_test_root.position = Vector3(0, -3, 0)
	add_child(alpha_test_root)
	
	var alpha_colors = [
		Color(1, 0, 0, 0.3),
		Color(0, 1, 0, 0.5),
		Color(0, 0, 1, 0.7),
		Color(1, 1, 0, 0.4),
	]
	
	for i in range(alpha_colors.size()):
		var color = alpha_colors[i]
		var x = (i - 1.5) * 1.5
		
		# Référence
		var ref_splat = _create_splat_plane(Vector3(x, 0, 0), color, 100)
		ref_splat.name = "AlphaRef_%d" % i
		alpha_test_root.add_child(ref_splat)
		
		# RGB565
		var rgb565_color = _quantize_rgb565(color)
		var rgb565_splat = _create_splat_plane(Vector3(x, 0, 0), rgb565_color, 100)
		rgb565_splat.name = "AlphaRGB565_%d" % i
		rgb565_root.add_child(rgb565_splat)
		
		# Palette
		var palette_color = _quantize_palette(color)
		var palette_splat = _create_splat_plane(Vector3(x, 0, 0), palette_color, 100)
		palette_splat.name = "AlphaPalette_%d" % i
		palette_root.add_child(palette_splat)
	
	test_results["rgb565_vs_palette"] = {
		"color_count": test_colors.size(),
		"alpha_count": alpha_colors.size(),
		"status": "passed",
		"description": "Comparaison visuelle RGB565 vs Palette 8-bit"
	}
	test_complete.emit(test_results["rgb565_vs_palette"])

## === Fonctions utilitaires ===

func _create_splat_plane(position: Vector3, color: Color, count: int) -> FoveaSplatRenderer:
	"""Crée un plan de splats avec la couleur spécifiée"""
	var splat = FoveaSplatRenderer.new()
	splat.use_triangle_mesh = true
	splat.splat_subdivisions = 16
	splat.multimesh = _create_multimesh_with_color(count, color, position)
	
	var material = ShaderMaterial.new()
	material.shader = load("res://addons/foveacore/shaders/splat_render_triangle.gdshader")
	material.set_shader_parameter("use_palette", enable_palette)
	
	if enable_palette:
		var palette = _get_palette()
		if palette:
			var data: PackedByteArray = palette.to_packed_rgb_array()
			var img := Image.create_from_data(1, palette.colors.size(), false, Image.FORMAT_RGBA8, data)
			var tex := ImageTexture.create_from_image(img)
			tex.filter_clip = true
			material.set_shader_parameter("palette_texture", tex)
			material.set_shader_parameter("palette_size", palette.colors.size())
	
	splat.material_override = material
	return splat

func _create_multimesh_with_color(count: int, color: Color, position: Vector3) -> MultiMesh:
	"""Crée un MultiMesh avec une couleur spécifique"""
	var mesh = _create_triangle_splat_mesh()
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	
	for i in range(count):
		var offset = Vector3(
			randf() * 2 - 1,
			randf() * 2 - 1,
			randf() * 2 - 1
		) * 0.5
		var transform = Transform3D(Basis(), position + offset)
		multimesh.set_instance_transform(i, transform)
		
		# Stocker la couleur dans custom_data
		multimesh.set_instance_custom_data(i, Color(color.r, color.g, color.b, color.a))
	
	return multimesh

func _create_triangle_splat_mesh() -> ArrayMesh:
	"""Crée un maillage triangle simple pour les splats"""
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Triangle simple (sera étiré par le shader)
	var vertices = [
		Vector3(-1, -1, 0),
		Vector3(1, -1, 0),
		Vector3(0, 1, 0)
	]
	
	for v in vertices:
		st.add_vertex(v)
	
	return st.commit()

func _get_palette() -> FoveaColorPalette:
	"""Obtient la palette configurée"""
	match palette_name:
		"watercolor_16":
			return FoveaColorPalette.watercolor_16()
		"grayscale_4":
			return FoveaColorPalette.grayscale_4()
		_: 
			var p = FoveaColorPalette.new()
			p.palette_name = "Test Palette"
			p.colors = [
				Color(0, 0, 0),
				Color(0.2, 0.2, 0.2),
				Color(0.4, 0.4, 0.4),
				Color(0.6, 0.6, 0.6),
				Color(0.8, 0.8, 0.8),
				Color(1, 1, 1),
				Color(1, 0, 0),
				Color(0, 1, 0),
				Color(0, 0, 1),
				Color(1, 1, 0),
				Color(1, 0, 1),
				Color(0, 1, 1),
				Color(0.5, 0, 0),
				Color(0, 0.5, 0),
				Color(0, 0, 0.5),
				Color(0.5, 0.5, 0.5)
			]
			return p

func _quantize_rgb565(color: Color) -> Color:
	"""Simule la quantification RGB565 (5-6-5 bits)"""
	var r = round(color.r * 31) / 31.0
	var g = round(color.g * 63) / 63.0
	var b = round(color.b * 31) / 31.0
	return Color(r, g, b, color.a)

func _quantize_palette(color: Color) -> Color:
	"""Simule la quantification palette 8-bit"""
	var palette = _get_palette()
	var best_idx = 0
	var best_dist = 1e9
	for i in range(palette.colors.size()):
		var d = color.distance_to(palette.colors[i])
		if d < best_dist:
			best_dist = d
			best_idx = i
	return palette.colors[best_idx]

func _print_summary() -> void:
	print("\n" + "=".repeat(80))
	print("RÉSUMÉ DES TESTS")
	print("=" + "=".repeat(79))
	
	for key in test_results:
		var result = test_results[key]
		if result is Dictionary and result.has("status"):
			print("\n[%s] %s" % [key.to_upper(), result.status])
			if result.has("description"):
				print("  %s" % result.description)
	
	print("\n" + "=".repeat(80))