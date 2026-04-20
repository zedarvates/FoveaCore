extends RefCounted
class_name GaussianSplat
## GaussianSplat — 3D Gaussian Splatting primitive
## Stores position, covariance (scale+rotation), opacity, and color (SH-derived)

var position: Vector3 = Vector3.ZERO
var rotation: Quaternion = Quaternion.IDENTITY
var scale: Vector3 = Vector3.ONE

var opacity: float = 1.0
var color: Color = Color.WHITE
var depth: float = 0.0
var normal: Vector3 = Vector3.UP

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

func to_dict() -> Dictionary:
	return {
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"opacity": opacity,
		"color": color,
		"radius": radius,
		"covariance": covariance,
		"depth": depth
	}

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
