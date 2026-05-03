extends RefCounted
class_name GaussianSplat
## GaussianSplat — 3D Gaussian Splatting primitive
## Stores position, covariance (scale+rotation), opacity, and color (SH-derived)
## Supporte la quantification de couleurs (palette 8-bit) et le dithering

var position: Vector3 = Vector3.ZERO
var rotation: Quaternion = Quaternion.IDENTITY
var scale: Vector3 = Vector3.ONE

var opacity: float = 1.0
var color: Color = Color.WHITE
var depth: float = 0.0
var normal: Vector3 = Vector3.UP

# Données de quantification (pour rendu optimisé)
var palette_index: int = 0  # Index dans la palette 8-bit (0-255)
var dither_seed: int = 0    # Seed pour dithering stochastique

# Derived render properties (computed on demand)
var radius: float = 1.0
var covariance: Vector2 = Vector2.ONE  # Simplified 2D covariance for ellipse

func _init(p: Vector3 = Vector3.ZERO) -> void:
	position = p

func compute_derived() -> void:
	radius = (scale.x + scale.y + scale.z) / 3.0
	covariance = Vector2(scale.x / radius, scale.y / radius)

func apply_foveal_weight(weight: float) -> void:
	opacity *= weight

## Convertit la couleur RGB en index de palette (quantification)
func quantize_color(palette: Array[Color]) -> int:
	var min_dist = INF
	var best_index = 0
	
	for i in range(palette.size()):
		var dist = _color_distance_squared(color, palette[i])
		if dist < min_dist:
			min_dist = dist
			best_index = i
	
	palette_index = best_index
	return best_index

## Distance perceptuelle entre deux couleurs (Lab-like approximation)
static func _color_distance_squared(c1: Color, c2: Color) -> float:
	# Pondération perceptuelle (plus sensible au vert)
	var r = (c1.r + c2.r) / 2.0
	var dr = c1.r - c2.r
	var dg = c1.g - c2.g
	var db = c1.b - c2.b
	
	return (2.0 + r) * dr * dr + 4.0 * dg * dg + (2.0 + (1.0 - r)) * db * db

## Applique le dithering Floyd-Steinberg à la couleur
func apply_dithering(x: int, y: int, error: Color) -> Color:
	# Ajoute l'erreur de quantification avec facteur de diffusion
	var dithered = Color(
		clamp(color.r + error.r * 7.0 / 16.0, 0.0, 1.0),
		clamp(color.g + error.g * 7.0 / 16.0, 0.0, 1.0),
		clamp(color.b + error.b * 7.0 / 16.0, 0.0, 1.0)
	)
	return dithered

## Génère une seed de dithering basée sur la position spatiale
func generate_dither_seed(grid_size: int = 256) -> int:
	var gx = int((position.x + 1000.0) * grid_size) % 256
	var gy = int((position.y + 1000.0) * grid_size) % 256
	var gz = int((position.z + 1000.0) * grid_size) % 256
	
	# Hash simple pour distribution uniforme
	return (gx * 73856093 ^ gy * 19349663 ^ gz * 83492791) & 0xFF

func to_dict() -> Dictionary:
	return {
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"opacity": opacity,
		"color": color,
		"radius": radius,
		"covariance": covariance,
		"depth": depth,
		"palette_index": palette_index,
		"dither_seed": dither_seed
	}

func from_dict(data: Dictionary) -> void:
	position = data.get("position", Vector3.ZERO)
	rotation = data.get("rotation", Quaternion.IDENTITY)
	scale = data.get("scale", Vector3.ONE)
	opacity = data.get("opacity", 1.0)
	color = data.get("color", Color.WHITE)
	radius = data.get("radius", 1.0)
	covariance = data.get("covariance", Vector2.ONE)
	depth = data.get("depth", 0.0)
	palette_index = data.get("palette_index", 0)
	dither_seed = data.get("dither_seed", 0)

static func create_from_triangle(
	pos: Vector3, 
	normal: Vector3, 
	splat_color: Color, 
	area: float, 
	camera_pos: Vector3, 
	density: float = 1.0
) -> GaussianSplat:
	var splat = GaussianSplat.new(pos)
	splat.color = splat_color
	splat.opacity = 0.8 # Base opacity
	splat.depth = pos.distance_to(camera_pos)
	splat.normal = normal
	
	# Scale based on triangle area and density
	var base_scale = sqrt(area) * (1.0 / density)
	splat.scale = Vector3(base_scale, base_scale, base_scale * 0.1)
	
	# Rotate to align with normal
	if normal.length_squared() > 0.01:
		var up = Vector3.UP
		if abs(normal.dot(up)) > 0.99:
			up = Vector3.RIGHT
		splat.rotation = Quaternion(Basis.looking_at(normal, up))
	
	splat.compute_derived()
	return splat

## Calcule la mémoire utilisée par ce splat (en octets)
func get_memory_usage(use_palette: bool = true) -> int:
	if use_palette:
		# 16 octets (structure optimisée avec index 8-bit)
		return 16
	else:
		# 20 octets (RGB565 + padding)
		return 20

## Compare la différence de couleur après quantification
func get_quantization_error(original_color: Color, palette: Array[Color]) -> float:
	var quantized = palette[palette_index]
	return sqrt(_color_distance_squared(original_color, quantized))
