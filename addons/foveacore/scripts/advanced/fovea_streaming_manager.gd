class_name FoveaStreamingManager
extends RefCounted

const FoveaSpatialChunkScript = preload("res://addons/foveacore/scripts/advanced/fovea_spatial_chunk.gd")

## FoveaEngine : FoveaStreamingManager
## Gère le chargement out-of-core asynchrone des chunks spatiaux de splats.
## Limite l'utilisation de la RAM CPU via un cache LRU.

# On stocke les informations de positionnement du fichier .fovea
class StreamingAsset:
	var path: String
	var splat_start_offset: int
	var chunks: Array = [] # Array[SpatialChunk]
	var total_splats: int

# Configuration des budgets
var max_ram_splats: int = 1000000 # Environ 16 Mo de RAM CPU max pour les splats
var max_uploads_per_frame: int = 32768
var has_newly_loaded_chunks: bool = false

# État interne
var _assets: Dictionary = {} # fovea_path -> StreamingAsset
var _lru_cache: Array[String] = [] # Clés sous forme de "path_chunkIndex"
var _loading_keys: Dictionary = {} # Clés en cours de chargement asynchrone -> true
var _lock: Mutex = Mutex.new()
var _current_ram_splats: int = 0

func _init() -> void:
	pass

# Enregistre un asset sans charger tous les octets bruts
func register_asset(fovea_path: String, aabb_min: Vector3, aabb_max: Vector3, raw_bytes: PackedByteArray = PackedByteArray()) -> StreamingAsset:
	_lock.lock()
	if _assets.has(fovea_path):
		var asset = _assets[fovea_path]
		_lock.unlock()
		return asset
	_lock.unlock()

	var file := FileAccess.open(fovea_path, FileAccess.READ)
	if file == null:
		push_error("FoveaStreamingManager: Impossible d'ouvrir en lecture: " + fovea_path)
		return null

	# Lire les métadonnées de l'en-tête (72 octets)
	var magic := file.get_buffer(8).get_string_from_utf8()
	if magic != "FOVEA_3D":
		file.close()
		push_error("FoveaStreamingManager: Magic bytes invalides dans: " + fovea_path)
		return null

	var version := file.get_32()
	var total_splats := file.get_32()
	var color_codebook_size := file.get_32()
	var covar_codebook_size := file.get_32()
	file.close()

	var splat_start_offset = 72 + color_codebook_size * 12 + covar_codebook_size * 32

	var asset = StreamingAsset.new()
	asset.path = fovea_path
	asset.splat_start_offset = splat_start_offset
	asset.total_splats = total_splats

	# Si raw_bytes n'est pas fourni, on le lit du fichier temporairement pour indexer
	var bytes := raw_bytes
	if bytes.is_empty():
		var temp_file := FileAccess.open(fovea_path, FileAccess.READ)
		if temp_file:
			temp_file.seek(splat_start_offset)
			bytes = temp_file.get_buffer(total_splats * 16)
			temp_file.close()

	# Diviser l'espace en chunks et calculer les file_slices
	asset.chunks = _precompute_slices(asset, bytes, aabb_min, aabb_max)

	_lock.lock()
	_assets[fovea_path] = asset
	_lock.unlock()

	print("FoveaStreamingManager: Asset '%s' enregistre pour streaming (%d splats, %d chunks)." % [
		fovea_path.get_file(), total_splats, asset.chunks.size()
	])
	return asset

func unregister_asset(fovea_path: String) -> void:
	_lock.lock()
	if _assets.has(fovea_path):
		var asset = _assets[fovea_path]
		for chunk in asset.chunks:
			_current_ram_splats -= chunk.raw_bytes.size() / 16
			chunk.raw_bytes = PackedByteArray()
			chunk.is_loaded = false
		_assets.erase(fovea_path)
		
		# Nettoyer LRU
		var new_lru: Array[String] = []
		for key in _lru_cache:
			if not key.begins_with(fovea_path + "_"):
				new_lru.append(key)
		_lru_cache = new_lru
	_lock.unlock()

# Calcule les tranches de fichier pour chaque chunk
func _precompute_slices(asset: StreamingAsset, bytes: PackedByteArray, aabb_min: Vector3, aabb_max: Vector3) -> Array:
	var chunks: Array = []
	chunks.resize(4096)
	
	var size_cell := (aabb_max - aabb_min) / 16.0
	for i in range(4096):
		var chunk = FoveaSpatialChunkScript.new()
		chunk.index = i
		var cx := i & 15
		var cy := (i >> 4) & 15
		var cz := (i >> 8) & 15
		var pos_cell := aabb_min + Vector3(cx, cy, cz) * size_cell
		chunk.aabb = AABB(pos_cell, size_cell)
		chunk.raw_bytes = PackedByteArray()
		chunk.is_loaded = false
		# Stocker les tranches de fichier (offset absolu, taille en bytes)
		chunk.set_meta("file_slices", [])
		chunks[i] = chunk

	var total_splats = bytes.size() / 16
	var buckets: Array[Array] = []
	buckets.resize(4096)
	for i in range(4096):
		buckets[i] = []

	for i in range(total_splats):
		var offset := i * 16
		var qx := bytes.decode_u16(offset)
		var qy := bytes.decode_u16(offset + 2)
		var qz := bytes.decode_u16(offset + 4)
		
		var cell_x := clamp(int(float(qx) / 65535.0 * 16.0), 0, 15)
		var cell_y := clamp(int(float(qy) / 65535.0 * 16.0), 0, 15)
		var cell_z := clamp(int(float(qz) / 65535.0 * 16.0), 0, 15)
		
		var chunk_idx = cell_x + (cell_y << 4) + (cell_z << 8)
		buckets[chunk_idx].append(i)

	for i in range(4096):
		var indices: Array = buckets[i]
		if indices.is_empty():
			continue
		var chunk = chunks[i]
		var slices: Array = []
		
		var start_idx: int = indices[0]
		var count: int = 1
		for j in range(1, indices.size()):
			var idx: int = indices[j]
			if idx == start_idx + count:
				count += 1
			else:
				var file_offset = asset.splat_start_offset + start_idx * 16
				slices.append({ "offset": file_offset, "size": count * 16 })
				start_idx = idx
				count = 1
		
		var file_offset = asset.splat_start_offset + start_idx * 16
		slices.append({ "offset": file_offset, "size": count * 16 })
		chunk.set_meta("file_slices", slices)

	return chunks

# Met à jour la priorité des chunks et gère le chargement/déchargement
func update_streaming(camera: Camera3D, chunk_load_radius: float = 20.0) -> void:
	if camera == null:
		return
	var cam_pos = camera.global_position
	var gaze_dir := -camera.global_transform.basis.z.normalized()

	var chunks_to_load: Array[Dictionary] = []

	_lock.lock()
	for fovea_path in _assets:
		var asset: StreamingAsset = _assets[fovea_path]
		for chunk in asset.chunks:
			var slices: Array = chunk.get_meta("file_slices")
			if slices.is_empty():
				continue
				
			var dist = _distance_to_aabb(cam_pos, chunk.aabb)
			var key = fovea_path + "_" + str(chunk.index)
			
			if dist <= chunk_load_radius:
				# Si le chunk n'est pas chargé et pas encore en cours de chargement
				if not chunk.is_loaded and not _loading_keys.has(key):
					# Calcul de priorité : plus proche et dans le regard = priorité haute (valeur faible)
					var to_chunk: Vector3 = (chunk.aabb.position + chunk.aabb.size * 0.5 - cam_pos).normalized()
					var gaze_align: float = gaze_dir.dot(to_chunk) # [-1..1]
					var priority: float = dist - 5.0 * gaze_align # Plus de poids à l'alignement gaze
					
					chunks_to_load.append({
						"asset": asset,
						"chunk": chunk,
						"key": key,
						"priority": priority
					})
				elif chunk.is_loaded:
					# Mettre à jour LRU si déjà chargé
					_touch_lru(key)
			else:
				# Si le chunk est chargé mais en dehors du rayon, on l'éligible à l'éviction immédiate
				# (L'éviction sera faite par le budget de RAM)
				pass
	_lock.unlock()

	# Trier les chunks par priorité (tri ascendant : plus petit en premier)
	chunks_to_load.sort_custom(func(a, b):
		return a.priority < b.priority
	)

	# Lancer le chargement des chunks prioritaires
	for item in chunks_to_load:
		_request_chunk_load(item.asset, item.chunk, item.key)

# Lancer une tâche asynchrone pour charger un chunk
func _request_chunk_load(asset: StreamingAsset, chunk, key: String) -> void:
	_lock.lock()
	_loading_keys[key] = true
	_lock.unlock()

	# Charger asynchronement via un thread
	var thread := Thread.new()
	thread.start(func() -> void:
		_async_load_thread_func(asset, chunk, key, thread)
	)

# Fonction de thread d'arrière-plan
func _async_load_thread_func(asset: StreamingAsset, chunk, key: String, thread: Thread) -> void:
	var slices: Array = chunk.get_meta("file_slices")
	var chunk_bytes := PackedByteArray()
	
	# Ouvrir le fichier en lecture
	var file := FileAccess.open(asset.path, FileAccess.READ)
	if file != null:
		for slice in slices:
			file.seek(slice.offset)
			chunk_bytes.append_array(file.get_buffer(slice.size))
		file.close()

	var lod0_count := chunk_bytes.size() / 16
	var chunk_bytes_lod1 := PackedByteArray()
	var chunk_bytes_lod2 := PackedByteArray()
	var chunk_bytes_lod3 := PackedByteArray()
	
	if lod0_count > 0:
		# Décimation asynchrone pour les LOD
		chunk_bytes_lod1 = FoveaSplatCleaner.decimate(chunk_bytes, int(lod0_count * 0.5))
		chunk_bytes_lod2 = FoveaSplatCleaner.decimate(chunk_bytes, int(lod0_count * 0.2))
		chunk_bytes_lod3 = FoveaSplatCleaner.decimate(chunk_bytes, int(lod0_count * 0.05))

	_lock.lock()
	chunk.raw_bytes = chunk_bytes
	chunk.raw_bytes_lod1 = chunk_bytes_lod1
	chunk.raw_bytes_lod2 = chunk_bytes_lod2
	chunk.raw_bytes_lod3 = chunk_bytes_lod3
	chunk.is_loaded = true
	has_newly_loaded_chunks = true
	_loading_keys.erase(key)
	
	var splat_count = chunk_bytes.size() / 16
	_current_ram_splats += splat_count
	_touch_lru(key)
	
	# Vérifier et appliquer le budget RAM (éviction LRU)
	_enforce_ram_budget()
	_lock.unlock()
	
	# Attendre la fin du thread proprement
	call_deferred("_cleanup_thread", thread)

func _cleanup_thread(thread: Thread) -> void:
	thread.wait_to_finish()

func _touch_lru(key: String) -> void:
	_lru_cache.erase(key)
	_lru_cache.append(key)

# Libère la RAM CPU des chunks les plus anciens si on dépasse le budget
func _enforce_ram_budget() -> void:
	while _current_ram_splats > max_ram_splats and not _lru_cache.is_empty():
		var oldest_key := _lru_cache[0]
		_lru_cache.remove_at(0)
		
		# Parser oldest_key ("fovea_path_chunkIndex")
		var last_underscore := oldest_key.rfind("_")
		if last_underscore == -1:
			continue
		var fovea_path := oldest_key.substr(0, last_underscore)
		var chunk_idx := oldest_key.substr(last_underscore + 1).to_int()
		
		if _assets.has(fovea_path):
			var asset: StreamingAsset = _assets[fovea_path]
			if chunk_idx < asset.chunks.size():
				var chunk = asset.chunks[chunk_idx]
				var evicted_splats = chunk.raw_bytes.size() / 16
				chunk.raw_bytes = PackedByteArray()
				chunk.is_loaded = false
				_current_ram_splats -= evicted_splats
				print("FoveaStreamingManager: Eviction LRU de %s (chunk %d, -%d splats). RAM=%d splats." % [
					fovea_path.get_file(), chunk_idx, evicted_splats, _current_ram_splats
				])

func _distance_to_aabb(point: Vector3, aabb: AABB) -> float:
	var closest_point := Vector3(
		clamp(point.x, aabb.position.x, aabb.end.x),
		clamp(point.y, aabb.position.y, aabb.end.y),
		clamp(point.z, aabb.position.z, aabb.end.z)
	)
	return point.distance_to(closest_point)
