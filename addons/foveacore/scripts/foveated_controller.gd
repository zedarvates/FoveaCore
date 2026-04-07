extends Node
class_name FoveatedController

## FoveatedController - Contrôle complet du foveated rendering
## Gère les zones, l'eye-tracking, et l'adaptation dynamique

## Configuration des zones foveales
class FovealZones:
	var foveal_radius: float = 0.15        # Rayon zone fovéale (radians ou unités)
	var parafoveal_radius: float = 0.375   # Rayon zone parafovéale (2.5× foveal)
	var foveal_density: float = 2.0        # Multiplicateur densité fovéale
	var parafoveal_density: float = 1.0    # Multiplicateur densité parafovéale
	var peripheral_density: float = 0.3    # Multiplicateur densité périphérique


## Point de regard actuel
var _gaze_point: Vector3 = Vector3.ZERO
var _gaze_direction: Vector3 = Vector3.FORWARD
var _has_eye_tracking: bool = false

## Configuration
var _zones: FovealZones = FovealZones.new()

## Historique pour la stabilité temporelle
var _gaze_history: Array[Vector3] = []
var _gaze_stability_frames: int = 3


func _ready() -> void:
	pass


## Configurer les zones
func setup_zones(foveal_radius: float, foveal_density: float, parafoveal_density: float, peripheral_density: float) -> void:
	_zones.foveal_radius = foveal_radius
	_zones.parafoveal_radius = foveal_radius * 2.5
	_zones.foveal_density = foveal_density
	_zones.parafoveal_density = parafoveal_density
	_zones.peripheral_density = peripheral_density


## Mettre à jour le point de regard
func update_gaze(gaze_point: Vector3, gaze_direction: Vector3 = Vector3.FORWARD) -> void:
	_gaze_history.append(gaze_point)

	# Limiter l'historique
	if _gaze_history.size() > _gaze_stability_frames:
		_gaze_history.pop_front()

	# Moyenne pour la stabilité
	if _gaze_history.size() >= _gaze_stability_frames:
		var avg: Vector3 = Vector3.ZERO
		for p: Vector3 in _gaze_history:
			avg += p
		_gaze_point = avg / float(_gaze_history.size())
	else:
		_gaze_point = gaze_point

	_gaze_direction = gaze_direction.normalized()


## Obtenir le point de regard stabilisé
func get_gaze_point() -> Vector3:
	return _gaze_point


## Obtenir la direction du regard
func get_gaze_direction() -> Vector3:
	return _gaze_direction


## Calculer le poids foveal pour un point
func get_foveal_weight(point: Vector3) -> float:
	var dist: float = point.distance_to(_gaze_point)

	if dist < _zones.foveal_radius:
		return 1.0
	elif dist < _zones.parafoveal_radius:
		var t: float = (dist - _zones.foveal_radius) / (_zones.parafoveal_radius - _zones.foveal_radius)
		return lerp(1.0, 0.5, t)
	else:
		return 0.3


## Calculer le multiplicateur de densité pour un point
func get_density_multiplier(point: Vector3) -> float:
	var dist: float = point.distance_to(_gaze_point)

	if dist < _zones.foveal_radius:
		return _zones.foveal_density
	elif dist < _zones.parafoveal_radius:
		return _zones.parafoveal_density
	else:
		return _zones.peripheral_density


## Activer/désactiver l'eye-tracking
func set_eye_tracking(enabled: bool) -> void:
	_has_eye_tracking = enabled


## Vérifier si l'eye-tracking est disponible
func has_eye_tracking() -> bool:
	return _has_eye_tracking


## Obtenir la configuration des zones
func get_zones() -> FovealZones:
	return _zones
