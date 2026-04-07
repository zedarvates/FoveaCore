class_name GaussianSplat

## GaussianSplat - Représentation d'un splat gaussien individuel
## Position, couleur, rayon, orientation pour le rendu

enum LayerType { BASE, SATURATION, LIGHT, SHADOW, LIQUID, DEFORMABLE }
enum BrushType { GAUSSIAN, SPONGE, DRY_BRUSH, STIPPLE, STONE, HATCHING }

## Type de couche pour le rendu artistique (peinture numérique)
var layer_type: LayerType = LayerType.BASE

## Type de tampon (Pinceau/Eponge) pour le rendu texturé
var brush_type: BrushType = BrushType.GAUSSIAN

## Résistance de la matière (pour les interactions molles)
var stiffness: float = 1.0

## Vitesse actuelle du splat (pour la physique locale)
var velocity: Vector3 = Vector3.ZERO

## Position mondiale du splat
var position: Vector3 = Vector3.ZERO

## Offset par rapport à la face d'origine (utile pour les ombres déportées)
var origin_offset: Vector3 = Vector3.ZERO

## Normale de la surface d'origine
var surface_normal: Vector3 = Vector3.UP

## Normale du splat (pour l'orientation)
var normal: Vector3 = Vector3.UP

## Couleur du splat (RGB)
var color: Color = Color.WHITE

## Rayon du splat (dans l'espace mondial)
var radius: float = 0.05

## Opacité du splat (0-1)
var opacity: float = 1.0

## Covariance 2D (pour l'ellipticité du splat projeté)
var covariance: Vector2 = Vector2.ONE

## Profondeur pour le tri (distance à la caméra)
var depth: float = 0.0

## Zone foveated (0 = périphérie, 1 = fovéale)
var foveal_weight: float = 1.0


## Créer un splat depuis un point sur un triangle
static func from_triangle_point(
	point: Vector3,
	normal: Vector3,
	color: Color,
	triangle_area: float,
	camera_position: Vector3,
	density: float = 1.0
) -> GaussianSplat:
	var splat: GaussianSplat = GaussianSplat.new()
	splat.position = point
	splat.normal = normal.normalized()
	splat.color = color
	splat.radius = _estimate_radius(triangle_area, density)
	splat.opacity = 1.0
	splat.depth = point.distance_to(camera_position)

	# Calculer la covariance basée sur l'angle de vue
	var view_dir: Vector3 = (camera_position - point).normalized()
	var angle: float = abs(view_dir.dot(splat.normal))
	splat.covariance = Vector2(1.0, angle)

	return splat


## Estimer le rayon du splat basé sur l'aire du triangle
static func _estimate_radius(triangle_area: float, density: float) -> float:
	# Un splat couvre environ sqrt(area / density)
	var base_radius: float = sqrt(triangle_area / max(density, 0.1))
	# Limiter pour éviter les splats trop grands ou petits
	return clamp(base_radius, 0.01, 0.5)


## Appliquer le poids foveated
func apply_foveal_weight(weight: float) -> void:
	foveal_weight = clamp(weight, 0.0, 1.0)
	# Réduire l'opacité en périphérie
	opacity = foveal_weight
	# Augmenter le rayon en périphérie (splats plus grands mais moins denses)
	radius = radius / max(foveal_weight, 0.1)
