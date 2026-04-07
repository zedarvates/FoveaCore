class_name NeuralFoveation

## NeuralFoveation — Utilise un modèle d'attention simulé pour optimiser la densité de splats
## Alternative légère au eye-tracking matériel

## Configuration
class NeuralConfig:
	var attention_resolution: Vector2i = Vector2i(64, 64)  # Résolution de la carte d'attention
	var temporal_smoothing: float = 0.8                     # Lissage temporel
	var saliency_weight: float = 0.6                        # Poids de la saillance visuelle
	var motion_weight: float = 0.4                          # Poids du mouvement
	var foveal_radius_base: float = 0.15                    # Rayon fovéal de base

## Carte d'attention (simulée)
var _attention_map: Image = null
var _previous_attention: Image = null

## Configuration
var config: NeuralConfig = NeuralConfig.new()

## Points d'intérêt détectés
var _interest_points: Array[Dictionary] = []

## Initialiser la carte d'attention
func _init() -> void:
	_attention_map = Image.create(
		config.attention_resolution.x,
		config.attention_resolution.y,
		false,
		Image.FORMAT_RF
	)
	_previous_attention = _attention_map.duplicate()

## Mettre à jour la carte d'attention
func update_attention_map(
	camera_position: Vector3,
	camera_rotation: Quaternion,
	scene_objects: Array,
	motion_vectors: Array
) -> void:
	# Sauvegarder l'ancienne carte
	_previous_attention = _attention_map.duplicate()

	# Réinitialiser la carte
	_attention_map.fill(Color(0, 0, 0, 1))

	# Calculer la saillance basée sur les objets de la scène
	for obj in scene_objects:
		if not obj.has("position") or not obj.has("size"):
			continue

		# Projeter la position de l'objet en espace écran
		var screen_pos: Vector2 = _world_to_screen(obj["position"], camera_position, camera_rotation)
		if screen_pos == Vector2(-1, -1):
			continue

		# Ajouter à la carte d'attention
		var size: Vector3 = obj.get("size", Vector3.ONE)
		var screen_size: float = max(size.x, size.z) * 10.0  # Approximation
		_add_gaussian_to_map(screen_pos, screen_size, config.saliency_weight)

	# Ajouter l'impact du mouvement
	for motion in motion_vectors:
		if not motion.has("position") or not motion.has("velocity"):
			continue

		var screen_pos: Vector2 = _world_to_screen(motion["position"], camera_position, camera_rotation)
		if screen_pos == Vector2(-1, -1):
			continue

		var motion_strength: float = motion["velocity"].length()
		_add_gaussian_to_map(screen_pos, 0.05, config.motion_weight * motion_strength)

	# Lissage temporel
	_blend_with_previous(config.temporal_smoothing)

## Ajouter un gaussian à la carte
func _add_gaussian_to_map(center: Vector2, radius: float, weight: float) -> void:
	var img_w: int = _attention_map.get_width()
	var img_h: int = _attention_map.get_height()

	var cx: int = int(center.x * img_w)
	var cy: int = int(center.y * img_h)
	var r: int = int(radius * max(img_w, img_h))

	for y in range(max(0, cy - r), min(img_h, cy + r + 1)):
		for x in range(max(0, cx - r), min(img_w, cx + r + 1)):
			var dist: float = Vector2(x - cx, y - cy).length()
			if dist <= r:
				var gaussian: float = exp(-pow(dist / max(r, 1), 2.0)) * weight
				var current: float = _attention_map.get_pixel(x, y).r
				_attention_map.set_pixel(x, y, Color(min(current + gaussian, 1.0), 0, 0, 1))

## Fusionner avec la carte précédente
func _blend_with_previous(factor: float) -> void:
	for y in range(_attention_map.get_height()):
		for x in range(_attention_map.get_width()):
			var current: float = _attention_map.get_pixel(x, y).r
			var previous: float = _previous_attention.get_pixel(x, y).r
			var blended: float = lerpf(previous, current, 1.0 - factor)
			_attention_map.set_pixel(x, y, Color(blended, 0, 0, 1))

## Obtenir le rayon fovéal ajusté pour un point
func get_adjusted_foveal_radius(screen_pos: Vector2) -> float:
	var img_w: int = _attention_map.get_width()
	var img_h: int = _attention_map.get_height()

	var px: int = clamp(int(screen_pos.x * img_w), 0, img_w - 1)
	var py: int = clamp(int(screen_pos.y * img_h), 0, img_h - 1)

	var attention: float = _attention_map.get_pixel(px, py).r

	# Plus l'attention est élevée, plus le rayon fovéal est petit (plus de détail)
	return config.foveal_radius_base * (1.0 - attention * 0.5)

## Obtenir le multiplicateur de densité pour un point
func get_density_multiplier(screen_pos: Vector2) -> float:
	var img_w: int = _attention_map.get_width()
	var img_h: int = _attention_map.get_height()

	var px: int = clamp(int(screen_pos.x * img_w), 0, img_w - 1)
	var py: int = clamp(int(screen_pos.y * img_h), 0, img_h - 1)

	var attention: float = _attention_map.get_pixel(px, py).r

	# Lerp entre densité périphérique et fovéale
	return lerpf(0.3, 2.0, attention)

## Convertir position monde en écran
func _world_to_screen(world_pos: Vector3, camera_pos: Vector3, camera_rot: Quaternion) -> Vector2:
	# Transformation simplifiée
	var forward: Vector3 = camera_rot * Vector3.FORWARD
	var right: Vector3 = camera_rot * Vector3.RIGHT
	var up: Vector3 = camera_rot * Vector3.UP

	var to_object: Vector3 = world_pos - camera_pos
	var distance: float = to_object.length()

	if distance <= 0:
		return Vector2(-1, -1)

	var ndc_x: float = to_object.dot(right) / distance
	var ndc_y: float = to_object.dot(up) / distance

	# Vérifier si dans le champ de vision
	var fov_half: float = deg_to_rad(60.0)  # FOV typique VR
	if abs(ndc_x) > tan(fov_half) or abs(ndc_y) > tan(fov_half):
		return Vector2(-1, -1)

	# Convertir en coordonnées UV [0, 1]
	var u: float = (ndc_x / tan(fov_half) + 1.0) / 2.0
	var v: float = (-ndc_y / tan(fov_half) + 1.0) / 2.0

	return Vector2(clamp(u, 0.0, 1.0), clamp(v, 0.0, 1.0))

## Obtenir les points d'intérêt
func get_interest_points() -> Array[Dictionary]:
	return _interest_points.duplicate()

## Réinitialiser
func clear() -> void:
	if _attention_map:
		_attention_map.fill(Color(0, 0, 0, 1))
	if _previous_attention:
		_previous_attention.fill(Color(0, 0, 0, 1))
	_interest_points.clear()
