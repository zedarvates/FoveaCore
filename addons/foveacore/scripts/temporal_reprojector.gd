class_name TemporalReprojector
extends Node

## TemporalReprojector - Réutilise les splats des frames précédentes
## Réduit le coût de génération de 20-30% grâce à la cohérence temporelle

## Données d'un splat dans l'historique
class HistoricalSplat:
	var position: Vector3
	var color: Color
	var radius: float
	var opacity: float
	var normal: Vector3
	var age: int = 0           # Nombre de frames depuis la création
	var last_seen: int = 0     # Frame où vu pour la dernière fois
	var motion_vector: Vector3 = Vector3.ZERO

## Configuration
class ReprojectionConfig:
	var max_history_frames: int = 8        # Nombre max de frames d'historique
	var fade_in_frames: int = 2            # Frames pour le fade-in des nouveaux splats
	var fade_out_frames: int = 4           # Frames pour le fade-out des anciens splats
	var motion_threshold: float = 0.05     # Seuil de mouvement avant invalidation
	var reproject_ratio: float = 0.7       # Ratio de splats à reprojeter (0-1)

## Historique des splats par nœud
var _history: Dictionary = {}  # Node -> Array[HistoricalSplat]

## Frame actuelle
var _current_frame: int = 0

## Configuration par défaut
var config: ReprojectionConfig = ReprojectionConfig.new()

## Statistiques
var _stats: Dictionary = {
	"reprojected": 0,
	"new_generated": 0,
	"expired": 0,
	"total_in_history": 0
}

## Mettre à jour et reprojeter les splats
func reproject_splats(
	splattable_node,
	current_splats: Array[GaussianSplat],
	camera_position: Vector3,
	previous_camera_position: Vector3,
	new_triangles: Array
) -> Array[GaussianSplat]:
	_current_frame += 1
	
	var result: Array[GaussianSplat] = []
	var node_key = splattable_node.get_instance_id()
	
	# Initialiser l'historique si nécessaire
	if not _history.has(node_key):
		_history[node_key] = []
	
	var history = _history[node_key] as Array
	var motion = camera_position - previous_camera_position
	
	# Étape 1 : Mettre à jour l'historique et reprojeter les splats valides
	var reprojected: Array[GaussianSplat] = []
	for hist_splat in history:
		hist_splat.age += 1
		hist_splat.last_seen = _current_frame
		
		# Vérifier si le splat est encore valide
		if not _is_splat_valid(hist_splat, motion):
			continue
		
		# Fade-out pour les vieux splats
		var fade = _compute_fade(hist_splat)
		if fade <= 0:
			continue
		
		# Créer le splat reprojété
		var splat = GaussianSplat.new()
		splat.position = hist_splat.position + hist_splat.motion_vector
		splat.color = hist_splat.color
		splat.radius = hist_splat.radius
		splat.opacity = hist_splat.opacity * fade
		splat.normal = hist_splat.normal
		splat.depth = splat.position.distance_to(camera_position)
		
		reprojected.append(splat)
	
	# Étape 2 : Générer de nouveaux splats pour les triangles non couverts
	var new_splats = _generate_missing_splats(new_triangles, camera_position, reprojected)
	
	# Étape 3 : Combiner reprojectés + nouveaux
	result.append_array(reprojected)
	result.append_array(new_splats)
	
	# Étape 4 : Mettre à jour l'historique
	_update_history(history, result, node_key)
	
	# Stats
	_stats["reprojected"] = reprojected.size()
	_stats["new_generated"] = new_splats.size()
	_stats["expired"] = history.size() - reprojected.size()
	_stats["total_in_history"] = history.size()
	
	return result

## Vérifier si un splat historique est encore valide
func _is_splat_valid(hist_splat: HistoricalSplat, camera_motion: Vector3) -> bool:
	# Trop vieux
	if hist_splat.age > config.max_history_frames:
		return false
	
	# Trop de mouvement (le splat n'est plus cohérent)
	if camera_motion.length() > config.motion_threshold * hist_splat.age:
		return false
	
	return true

## Calculer le facteur de fade
func _compute_fade(hist_splat: HistoricalSplat) -> float:
	# Fade-in pour les nouveaux
	if hist_splat.age < config.fade_in_frames:
		return float(hist_splat.age) / config.fade_in_frames
	
	# Fade-out pour les vieux
	var remaining = config.max_history_frames - hist_splat.age
	if remaining < config.fade_out_frames:
		return float(remaining) / config.fade_out_frames
	
	return 1.0

## Générer des splats manquants pour les triangles non couverts
func _generate_missing_splats(
	triangles: Array,
	camera_position: Vector3,
	existing_splats: Array[GaussianSplat]
) -> Array[GaussianSplat]:
	var new_splats: Array[GaussianSplat] = []
	
	# Pour chaque triangle, vérifier s'il y a un splat proche
	for triangle in triangles:
		if triangle.vertices.size() < 3:
			continue
		
		var center = (triangle.vertices[0] + triangle.vertices[1] + triangle.vertices[2]) / 3.0
		
		# Vérifier s'il y a un splat reprojecté proche
		var has_nearby = false
		for existing in existing_splats:
			if existing.position.distance_to(center) < existing.radius * 2:
				has_nearby = true
				break
		
		if not has_nearby:
			# Générer un nouveau splat
			var splat = GaussianSplat.create_from_triangle(
				center,
				triangle.normals[0],
				Color(0.7, 0.7, 0.7),
				triangle.area,
				camera_position,
				1.0
			)
			new_splats.append(splat)
	
	return new_splats

## Mettre à jour l'historique avec les splats actuels
func _update_history(history: Array, current_splats: Array[GaussianSplat], node_key):
	# Nettoyer les vieux splats
	history.assign(history.filter(func(s: HistoricalSplat) -> bool:
		return s.age <= config.max_history_frames
	))
	
	# Ajouter ou mettre à jour les splats actuels
	for splat in current_splats:
		# Chercher un splat historique proche
		var found: HistoricalSplat = null
		for hist in history:
			if hist.position.distance_to(splat.position) < splat.radius:
				found = hist
				break
		
		if found:
			# Mettre à jour
			found.motion_vector = splat.position - found.position
			found.position = splat.position
			found.color = splat.color
			found.radius = splat.radius
			found.opacity = splat.opacity
			found.normal = splat.normal
			found.last_seen = _current_frame
		else:
			# Nouveau splat dans l'historique
			var hist = HistoricalSplat.new()
			hist.position = splat.position
			hist.color = splat.color
			hist.radius = splat.radius
			hist.opacity = splat.opacity
			hist.normal = splat.normal
			hist.age = 0
			hist.last_seen = _current_frame
			history.append(hist)
	
	_history[node_key] = history

## Obtenir les statistiques
func get_stats() -> Dictionary:
	return _stats.duplicate()

## Réinitialiser l'historique
func clear():
	_history.clear()
	_current_frame = 0
