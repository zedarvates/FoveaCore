class_name NetworkInterpolator

## NetworkInterpolator - Interpolation fluide des positions réseau pour VR MMO
## Combine dead reckoning et interpolation Hermite

## État d'un joueur distant
class RemotePlayerState:
	var player_id: int = 0
	var position: Vector3 = Vector3.ZERO
	var rotation: Quaternion = Quaternion.IDENTITY
	var velocity: Vector3 = Vector3.ZERO
	var angular_velocity: Vector3 = Vector3.ZERO
	var last_update_time: float = 0.0
	var is_dead_reckoning: bool = false

## État reçu du réseau (snapshot)
class NetworkSnapshot:
	var player_id: int = 0
	var position: Vector3 = Vector3.ZERO
	var rotation: Quaternion = Quaternion.IDENTITY
	var velocity: Vector3 = Vector3.ZERO
	var timestamp: float = 0.0

## Configuration
class InterpolationConfig:
	var interpolation_delay: float = 0.1        # Délai d'interpolation (secondes)
	var dead_reckoning_threshold: float = 0.05   # Seuil d'erreur pour dead reckoning
	var max_correction_speed: float = 5.0        # Vitesse max de correction
	var use_hermite: bool = true                 # Utiliser l'interpolation Hermite

## États des joueurs distants
var _player_states: Dictionary = {}  # player_id -> RemotePlayerState
var _history: Dictionary = {}        # player_id -> Array[NetworkSnapshot]

## Configuration
var config: InterpolationConfig = InterpolationConfig.new()

## Recevoir un snapshot réseau
func receive_snapshot(snapshot: NetworkSnapshot) -> void:
	var pid: int = snapshot.player_id

	# Initialiser l'état si nécessaire
	if not _player_states.has(pid):
		_player_states[pid] = RemotePlayerState.new()
		_player_states[pid].player_id = pid
		_history[pid] = []

	var state: RemotePlayerState = _player_states[pid] as RemotePlayerState

	# Ajouter à l'historique
	_history[pid].append(snapshot)

	# Garder seulement les snapshots récents
	var max_history: int = int(config.interpolation_delay * 60.0) + 5
	if (_history[pid] as Array).size() > max_history:
		(_history[pid] as Array).pop_front()

	# Mettre à jour l'état avec le dernier snapshot
	state.position = snapshot.position
	state.rotation = snapshot.rotation
	state.velocity = snapshot.velocity
	state.last_update_time = snapshot.timestamp

## Obtenir la position interpolée pour un joueur
func get_interpolated_state(player_id: int, current_time: float) -> RemotePlayerState:
	if not _player_states.has(player_id):
		return null

	var state: RemotePlayerState = _player_states[player_id] as RemotePlayerState
	var target_time: float = current_time - config.interpolation_delay

	# Trouver les snapshots encadrant le temps cible
	var history: Array = _history[player_id] as Array
	if history.size() < 2:
		return state

	var prev: NetworkSnapshot = null
	var next: NetworkSnapshot = null

	for i in range(history.size() - 1):
		var snap_i: NetworkSnapshot = history[i] as NetworkSnapshot
		var snap_next: NetworkSnapshot = history[i + 1] as NetworkSnapshot
		if snap_i.timestamp <= target_time and snap_next.timestamp > target_time:
			prev = snap_i
			next = snap_next
			break

	if prev == null or next == null:
		# Dead reckoning si pas de snapshots disponibles
		return _dead_reckoning(state, current_time)

	# Interpolation
	var t: float = (target_time - prev.timestamp) / (next.timestamp - prev.timestamp)
	t = clamp(t, 0.0, 1.0)

	var result: RemotePlayerState = RemotePlayerState.new()
	result.player_id = player_id

	if config.use_hermite:
		# Interpolation Hermite avec les vitesses
		result.position = _hermite_interpolate(
			prev.position, prev.velocity,
			next.position, next.velocity,
			t
		)
		result.rotation = prev.rotation.slerp(next.rotation, t)
	else:
		# Interpolation linéaire simple
		result.position = lerp(prev.position, next.position, t)
		result.rotation = prev.rotation.slerp(next.rotation, t)

	result.velocity = lerp(prev.velocity, next.velocity, t)

	return result

## Dead reckoning : prédire la position basée sur la vitesse
func _dead_reckoning(state: RemotePlayerState, current_time: float) -> RemotePlayerState:
	var result: RemotePlayerState = RemotePlayerState.new()
	result.player_id = state.player_id

	var time_delta: float = current_time - state.last_update_time
	result.position = state.position + state.velocity * time_delta
	result.rotation = state.rotation
	result.velocity = state.velocity
	result.is_dead_reckoning = true

	return result

## Interpolation Hermite
func _hermite_interpolate(
	p0: Vector3, m0: Vector3,  # Position et tangente au point 0
	p1: Vector3, m1: Vector3,  # Position et tangente au point 1
	t: float
) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t

	# Polynômes de Hermite
	var h00: float = 2.0 * t3 - 3.0 * t2 + 1.0
	var h10: float = t3 - 2.0 * t2 + t
	var h01: float = -2.0 * t3 + 3.0 * t2
	var h11: float = t3 - t2

	return h00 * p0 + h10 * m0 + h01 * p1 + h11 * m1

## Nettoyer les vieux snapshots
func cleanup(max_age: float = 5.0) -> void:
	var current_time: float = Time.get_unix_time_from_system()
	var to_remove: Array = []

	for pid in _history:
		var history: Array = _history[pid] as Array
		history.assign(history.filter(func(s: NetworkSnapshot) -> bool:
			return current_time - s.timestamp < max_age
		))

		if history.is_empty():
			to_remove.append(pid)

	for pid in to_remove:
		_history.erase(pid)
		_player_states.erase(pid)

## Obtenir les stats
func get_stats() -> Dictionary:
	return {
		"tracked_players": _player_states.size(),
		"interpolation_delay": config.interpolation_delay,
		"using_hermite": config.use_hermite
	}
