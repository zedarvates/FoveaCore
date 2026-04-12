class_name PredictiveSplatter

## PredictiveSplatter — Prédit le mouvement de tête et pré-génère les splats
## Réduit la latence perçue en VR

## Configuration
class PredictionConfig:
	var prediction_horizon: float = 0.05      # Horizon de prédiction (secondes)
	var history_size: int = 10                # Nombre de positions d'historique
	var smoothing_factor: float = 0.3         # Facteur de lissage
	var pre_splat_margin: float = 0.5         # Marge de pre-splatting (unités)

## Historique des positions de caméra
var _position_history: Array[Dictionary] = []
var _rotation_history: Array[Dictionary] = []

## Configuration
var config: PredictionConfig = PredictionConfig.new()

## Dernière position prédite
var _last_predicted_position: Vector3 = Vector3.ZERO
var _last_predicted_rotation: Quaternion = Quaternion.IDENTITY

## Enregistrer une position de caméra
func record_camera_state(position: Vector3, rotation: Quaternion, timestamp: float) -> void:
	var state: Dictionary = {
		"position": position,
		"rotation": rotation,
		"timestamp": timestamp
	}

	_position_history.append(state)
	_rotation_history.append(state)

	# Limiter la taille de l'historique
	if _position_history.size() > config.history_size:
		_position_history.pop_front()
		_rotation_history.pop_front()

## Prédire la position future de la caméra
func predict_future_state(current_time: float) -> Dictionary:
	if _position_history.size() < 2:
		return {
			"position": _last_predicted_position,
			"rotation": _last_predicted_rotation,
			"confidence": 0.0
		}

	# Calculer la vitesse linéaire moyenne
	var recent: Dictionary = _position_history[-1]
	var older: Dictionary = _position_history[-2]
	var dt: float = recent["timestamp"] - older["timestamp"]

	if dt <= 0.0:
		dt = 0.016  # Fallback à 60fps

	var linear_velocity: Vector3 = (recent["position"] - older["position"]) / dt

	# Calculer la vitesse angulaire moyenne
	var angular_velocity: Vector3 = _compute_angular_velocity()

	# Prédire la position future
	var predicted_position: Vector3 = recent["position"] + linear_velocity * config.prediction_horizon
	var predicted_rotation: Quaternion = recent["rotation"] * Quaternion(Vector3.RIGHT, angular_velocity.x * config.prediction_horizon)
	predicted_rotation = predicted_rotation * Quaternion(Vector3.UP, angular_velocity.y * config.prediction_horizon)
	predicted_rotation = predicted_rotation * Quaternion(Vector3.FORWARD, angular_velocity.z * config.prediction_horizon)

	# Lissage avec la dernière prédiction
	if _last_predicted_position != Vector3.ZERO:
		predicted_position = lerp(_last_predicted_position, predicted_position, config.smoothing_factor)

	_last_predicted_position = predicted_position
	_last_predicted_rotation = predicted_rotation.normalized()

	# Calculer la confiance basée sur la cohérence du mouvement
	var confidence: float = _compute_confidence()

	return {
		"position": predicted_position,
		"rotation": _last_predicted_rotation,
		"velocity": linear_velocity,
		"angular_velocity": angular_velocity,
		"confidence": confidence
	}

## Calculer la vitesse angulaire moyenne
func _compute_angular_velocity() -> Vector3:
	if _rotation_history.size() < 2:
		return Vector3.ZERO

	var recent: Dictionary = _rotation_history[-1]
	var older: Dictionary = _rotation_history[-2]
	var dt: float = recent["timestamp"] - older["timestamp"]

	if dt <= 0.0:
		dt = 0.016

	var delta_rotation: Quaternion = recent["rotation"] * older["rotation"].inverse()
	var axis: Vector3 = delta_rotation.get_axis()
	var angle: float = delta_rotation.get_angle()

	return axis * (angle / dt)

## Calculer la confiance de la prédiction
func _compute_confidence() -> float:
	if _position_history.size() < 3:
		return 0.3

	# Vérifier la cohérence de la vitesse
	var velocities: Array[Vector3] = []
	for i in range(1, _position_history.size()):
		var dt: float = _position_history[i]["timestamp"] - _position_history[i - 1]["timestamp"]
		if dt > 0.0:
			var vel: Vector3 = (_position_history[i]["position"] - _position_history[i - 1]["position"]) / dt
			velocities.append(vel)

	if velocities.size() < 2:
		return 0.5

	# Calculer la variance des vitesses
	var mean_vel: Vector3 = Vector3.ZERO
	for v in velocities:
		mean_vel += v
	mean_vel /= float(velocities.size())

	var variance: float = 0.0
	for v in velocities:
		variance += (v - mean_vel).length_squared()
	variance /= float(velocities.size())

	# Confiance inversement proportionnelle à la variance
	var confidence: float = 1.0 / (1.0 + variance)
	return clamp(confidence, 0.0, 1.0)

## Obtenir la zone de pre-splatting (AABB étendu)
func get_pre_splat_zone(center: Vector3, base_size: Vector3) -> AABB:
	var margin: float = config.pre_splat_margin
	var predicted_pos: Vector3 = _last_predicted_position

	# Étendre la zone dans la direction du mouvement
	var direction: Vector3 = predicted_pos - center
	var extended_size: Vector3 = base_size + Vector3(margin, margin, margin) + direction.normalized() * margin

	return AABB(center - extended_size / 2.0, extended_size)

## Réinitialiser l'historique
func clear() -> void:
	_position_history.clear()
	_rotation_history.clear()
	_last_predicted_position = Vector3.ZERO
	_last_predicted_rotation = Quaternion.IDENTITY
