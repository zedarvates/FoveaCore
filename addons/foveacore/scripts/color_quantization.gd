class_name ColorQuantization
extends RefCounted
## ColorQuantization — Algorithmes de quantification de couleurs
## Implémente K-Means et Median Cut pour réduire une palette à 256 couleurs max
## avec support du dithering Floyd-Steinberg

const KMEANS_MAX_ITERATIONS = 10
const KMEANS_MAX_CLUSTERS = 256

## Structure pour stocker un pixel avec sa position pour le dithering
class PixelData:
	var color: Color
	var x: int
	var y: int
	var error: Color = Color.ZERO
	
	func _init(c: Color, px: int, py: int):
		color = c
		x = px
		y = py

## Résultat de la quantification
class QuantizationResult:
	var palette: Array[Color]  # Palette de couleurs (max 256)
	var indices: PackedByteArray  # Indices des couleurs pour chaque pixel
	var color_map: Dictionary  # Mapping couleur -> index
	var stats: Dictionary  # Statistiques de la quantification
	
	func _init():
		palette = []
		indices = PackedByteArray()
		color_map = {}
		stats = {
			"original_colors": 0,
			"quantized_colors": 0,
			"quantization_error": 0.0,
			"method": "",
			"processing_time_ms": 0.0
		}

## K-Means clustering pour la quantification de couleurs
## Entrée: Tableau de couleurs, nombre de clusters désiré
## Sortie: Palette de couleurs quantifiées
static func kmeans_quantize(colors: Array[Color], max_clusters: int = 256) -> QuantizationResult:
	var result = QuantizationResult.new()
	var start_time = Time.get_ticks_msec()
	
	if colors.size() == 0:
		return result
	
	# Limiter le nombre de clusters
	var k = min(max_clusters, colors.size())
	k = min(k, KMEANS_MAX_CLUSTERS)
	
	# Si peu de couleurs, pas besoin de K-Means
	if colors.size() <= k:
		result.palette = colors
		result.stats["method"] = "direct"
		result.stats["processing_time_ms"] = Time.get_ticks_msec() - start_time
		return result
	
	# Initialisation des centroids (K-Means++)
	var centroids: Array[Color] = []
	centroids.append(colors[0])
	
	for i in range(1, k):
		var max_dist = 0.0
		var next_centroid = colors[0]
		
		for color in colors:
			var min_dist = INF
			for centroid in centroids:
				var dist = _color_distance_squared(color, centroid)
				min_dist = min(min_dist, dist)
			
			if min_dist > max_dist:
				max_dist = min_dist
				next_centroid = color
		
		centroids.append(next_centroid)
	
	# Itérations K-Means
	var assignments: Array[int] = []
	assignments.resize(colors.size())
	
	for iteration in range(KMEANS_MAX_ITERATIONS):
		# Étape d'assignation
		for i in range(colors.size()):
			var min_dist = INF
			var best_cluster = 0
			
			for c in range(centroids.size()):
				var dist = _color_distance_squared(colors[i], centroids[c])
				if dist < min_dist:
					min_dist = dist
					best_cluster = c
			
			assignments[i] = best_cluster
		
		# Étape de mise à jour des centroids
		var sums: Array[Color] = []
		var counts: Array[int] = []
		sums.resize(k)
		counts.resize(k)
		
		for i in range(k):
			sums[i] = Color.ZERO
			counts[i] = 0
		
		for i in range(colors.size()):
			var cluster = assignments[i]
			sums[cluster] += colors[i]
			counts[cluster] += 1
		
		var changed = false
		for i in range(k):
			if counts[i] > 0:
				var new_centroid = Color(
					sums[i].r / counts[i],
					sums[i].g / counts[i],
					sums[i].b / counts[i]
				)
				
				if _color_distance_squared(new_centroid, centroids[i]) > 0.001:
					changed = true
				
				centroids[i] = new_centroid
		
		if not changed:
			break
	
	# Nettoyage des clusters vides et réassignation
	var valid_centroids: Array[Color] = []
	for i in range(k):
		var has_points = false
		for j in range(assignments.size()):
			if assignments[j] == i:
				has_points = true
				break
		
		if has_points:
			valid_centroids.append(centroids[i])
	
	# Si on a perdu des clusters, on complète avec des couleurs éloignées
	while valid_centroids.size() < k and valid_centroids.size() < colors.size():
		var farthest_color = colors[0]
		var max_min_dist = 0.0
		
		for color in colors:
			var min_dist = INF
			for centroid in valid_centroids:
				min_dist = min(min_dist, _color_distance_squared(color, centroid))
			
			if min_dist > max_min_dist:
				max_min_dist = min_dist
				farthest_color = color
		
		if max_min_dist > 0.001:
			valid_centroids.append(farthest_color)
		else:
			break
	
	result.palette = valid_centroids
	
	# Calculer l'erreur de quantification
	var total_error = 0.0
	for i in range(colors.size()):
		var min_dist = INF
		for centroid in result.palette:
			var dist = _color_distance_squared(colors[i], centroid)
			min_dist = min(min_dist, dist)
		total_error += min_dist
	
	result.stats["original_colors"] = colors.size()
	result.stats["quantized_colors"] = result.palette.size()
	result.stats["quantization_error"] = sqrt(total_error / colors.size())
	result.stats["method"] = "kmeans"
	result.stats["processing_time_ms"] = Time.get_ticks_msec() - start_time
	
	return result

## Median Cut algorithm pour la quantification de couleurs
static func median_cut_quantize(colors: Array[Color], max_colors: int = 256) -> QuantizationResult:
	var result = QuantizationResult.new()
	var start_time = Time.get_ticks_msec()
	
	if colors.size() == 0:
		return result
	
	# Boîte initiale contenant toutes les couleurs
	var boxes: Array[ColorBox] = []
	var initial_box = ColorBox.new()
	initial_box.colors = colors
	initial_box.calculate_bounds()
	boxes.append(initial_box)
	
	# Diviser récursivement jusqu'à atteindre le nombre de couleurs désiré
	while boxes.size() < max_colors:
		# Trouver la boîte avec la plus grande étendue
		var largest_box_idx = -1
		var largest_extent = 0.0
		
		for i in range(boxes.size()):
			var extent = boxes[i].get_largest_extent()
			if extent > largest_extent:
				largest_extent = extent
				largest_box_idx = i
		
		if largest_box_idx == -1 or largest_extent < 1.0:
			break
		
		# Diviser cette boîte
		var box_to_split = boxes[largest_box_idx]
		var split_result = box_to_split.split()
		
		if split_result == null:
			break
		
		boxes.remove_at(largest_box_idx)
		boxes.append(split_result[0])
		boxes.append(split_result[1])
	
	# Extraire les couleurs moyennes de chaque boîte
	for box in boxes:
		result.palette.append(box.get_average_color())
	
	result.stats["original_colors"] = colors.size()
	result.stats["quantized_colors"] = result.palette.size()
	result.stats["method"] = "median_cut"
	result.stats["processing_time_ms"] = Time.get_ticks_msec() - start_time
	
	return result

## Dithering Floyd-Steinberg
static func apply_floyd_steinberg_dither(image: Image) -> Image:
	var width = image.get_width()
	var height = image.get_height()
	
	var dithered = Image.create(width, height, false, Image.FORMAT_RGBA8)
	dithered.copy_from(image)
	
	for y in range(height):
		for x in range(width):
			var old_pixel = dithered.get_pixel(x, y)
			var new_pixel = _quantize_pixel(old_pixel)
			dithered.set_pixel(x, y, new_pixel)
			
			var error = old_pixel - new_pixel
			
			if x + 1 < width:
				var p = dithered.get_pixel(x + 1, y)
				dithered.set_pixel(x + 1, y, p + error * 7.0 / 16.0)
			
			if x - 1 >= 0 and y + 1 < height:
				var p = dithered.get_pixel(x - 1, y + 1)
				dithered.set_pixel(x - 1, y + 1, p + error * 3.0 / 16.0)
			
			if y + 1 < height:
				var p = dithered.get_pixel(x, y + 1)
				dithered.set_pixel(x, y + 1, p + error * 5.0 / 16.0)
			
			if x + 1 < width and y + 1 < height:
				var p = dithered.get_pixel(x + 1, y + 1)
				dithered.set_pixel(x + 1, y + 1, p + error * 1.0 / 16.0)
	
	return dithered

## Quantification d'un pixel (réduction à la palette la plus proche)
static func _quantize_pixel(color: Color) -> Color:
	# Réduction à 8 bits par canal (simule une palette 256 couleurs)
	return Color(
		round(color.r * 255.0) / 255.0,
		round(color.g * 255.0) / 255.0,
		round(color.b * 255.0) / 255.0
	)

## Distance entre deux couleurs (Lab-like perceptuelle)
static func _color_distance_squared(c1: Color, c2: Color) -> float:
	# Conversion approximée en luminance pour une distance perceptuelle
	var r = (c1.r + c2.r) / 2.0
	var dr = c1.r - c2.r
	var dg = c1.g - c2.g
	var db = c1.b - c2.b
	
	# Distance pondérée (plus sensible au vert, moins au bleu)
	return (2.0 + r) * dr * dr + 4.0 * dg * dg + (2.0 + (1.0 - r)) * db * db

## Classe interne pour Median Cut
class ColorBox:
	var colors: Array[Color] = []
	var min_color: Color = Color(1, 1, 1)
	var max_color: Color = Color(0, 0, 0)
	
	func calculate_bounds() -> void:
		if colors.size() == 0:
			return
		
		min_color = Color(1, 1, 1)
		max_color = Color(0, 0, 0)
		
		for color in colors:
			min_color.r = min(min_color.r, color.r)
			min_color.g = min(min_color.g, color.g)
			min_color.b = min(min_color.b, color.b)
			max_color.r = max(max_color.r, color.r)
			max_color.g = max(max_color.g, color.g)
			max_color.b = max(max_color.b, color.b)
	
	func get_largest_extent() -> float:
		var extent_r = max_color.r - min_color.r
		var extent_g = max_color.g - min_color.g
		var extent_b = max_color.b - min_color.b
		return max(extent_r, max(extent_g, extent_b))
	
	func split() -> Array:
		var extent = get_largest_extent()
		if extent < 0.01:
			return null
		
		# Déterminer l'axe de coupe
		var axis = 0  # 0=R, 1=G, 2=B
		var extent_r = max_color.r - min_color.r
		var extent_g = max_color.g - min_color.g
		var extent_b = max_color.b - min_color.b
		
		if extent_g > extent_r and extent_g >= extent_b:
			axis = 1
		elif extent_b > extent_r and extent_b >= extent_g:
			axis = 2
		
		# Trier les couleurs selon l'axe
		colors.sort_custom(_compare_colors.bind(axis))
		
		# Diviser au milieu
		var median_idx = colors.size() / 2
		if median_idx == 0:
			return null
		
		var box1 = ColorBox.new()
		var box2 = ColorBox.new()
		
		for i in range(median_idx):
			box1.colors.append(colors[i])
		for i in range(median_idx, colors.size()):
			box2.colors.append(colors[i])
		
		box1.calculate_bounds()
		box2.calculate_bounds()
		
		return [box1, box2]
	
	func get_average_color() -> Color:
		if colors.size() == 0:
			return Color.BLACK
		
		var sum = Color.ZERO
		for color in colors:
			sum += color
		
		return Color(
			sum.r / colors.size(),
			sum.g / colors.size(),
			sum.b / colors.size()
		)
	
	static func _compare_colors(a: Color, b: Color, axis: int) -> bool:
		if axis == 0:
			return a.r < b.r
		elif axis == 1:
			return a.g < b.g
		else:
			return a.b < b.b

## Génération de palette à partir d'une image
static func generate_palette_from_image(image: Image, max_colors: int = 256, method: String = "kmeans") -> QuantizationResult:
	var width = image.get_width()
	var height = image.get_height()
	
	# Échantillonnage des pixels (tous ou sous-échantillonnage pour les grandes images)
	var sample_step = 1
	if width * height > 10000:
		sample_step = 2
	if width * height > 100000:
		sample_step = 4
	
	var colors: Array[Color] = []
	for y in range(0, height, sample_step):
		for x in range(0, width, sample_step):
			var pixel = image.get_pixel(x, y)
			if pixel.a > 0.5:  # Ignorer les pixels transparents
				colors.append(pixel)
	
	if method == "median_cut":
		return median_cut_quantize(colors, max_colors)
	else:
		return kmeans_quantize(colors, max_colors)

## Conversion d'une couleur RGB en index de palette (8-bit)
static func rgb_to_palette_index(color: Color, palette: Array[Color]) -> int:
	var min_dist = INF
	var best_index = 0
	
	for i in range(palette.size()):
		var dist = _color_distance_squared(color, palette[i])
		if dist < min_dist:
			min_dist = dist
			best_index = i
	
	return best_index

## Génération de la texture de palette pour le shader
static func create_palette_texture(palette: Array[Color]) -> ImageTexture:
	# Créer une image 16x16 (256 couleurs)
	var img = Image.create(16, 16, false, Image.FORMAT_RGBAF)
	
	for i in range(256):
		var x = i % 16
		var y = i / 16
		var color = Color.WHITE
		
		if i < palette.size():
			color = palette[i]
		
		img.set_pixel(x, y, color)
	
	var texture = ImageTexture.create_from_image(img)
	return texture
