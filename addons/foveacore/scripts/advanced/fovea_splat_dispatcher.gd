class_name FoveaSplatDispatcher
extends RefCounted

## FoveaEngine — FoveaSplatDispatcher
## Phase 3 : Vectorized Splat Dispatcher
##
## Remplace l'approche "1 GPUCullerPipeline par asset" (O(N) dispatches GPU par frame)
## par un pipeline VECTORISÉ : tous les assets sont regroupés en un seul mega-buffer
## et traités en UNE SEULE passe GPU, réduisant à O(1) les synchronisations CPU↔GPU.
##
## Architecture du pipeline par frame :
##   1. CPU Frustum Cull → filtre les blocs spatiaux de chaque asset hors-champ
##   2. Tagging         → chaque splat reçoit son asset_id dans le byte layer_id
##   3. Concaténation   → tous les bytes visibles forment un mega-buffer CPU→GPU
##   4. GPU Culling     → gpu_culling_multi.glsl (backface + frustum + Hi-Z)
##   5. Depth Precompute → depth_precompute.glsl (calcule dist² une fois pour toutes)
##   6. Keyed Sort       → sort_bitonic_keyed.glsl (lit depths[], sans recalcul)
##   7. Résultat         → RID du buffer trié (l'appelant lit avec rd.buffer_get_data)
##
## Usage :
##   var dispatcher := FoveaSplatDispatcher.new()
##   dispatcher.register_asset("res://obj.fovea", Vector3(-5,-5,-5), Vector3(5,5,5))
##   var result := dispatcher.process_frame(camera, depth_tex)
##   if result.count > 0:
##       var bytes := dispatcher.rd.buffer_get_data(result.buffer_rid)
##       dispatcher.rd.free_rid(result.buffer_rid)
##
## Règles CLAUDE.md :
##   - GDScript strictement typé
##   - Aucun appel bloquant dans _init() hormis la création du RenderingDevice
##   - Écritures GPU uniquement en batch (pas de set_instance_transform)

const SPLAT_BYTE_SIZE: int = 16    # FoveaPackedSplat = 4 × uint32
const MAX_ASSETS: int    = 256     # asset_id codé sur 8 bits
const BLOCK_SIZE: int    = 4096    # Splats par bloc spatial (Morton order)

# ── Données par asset enregistré ─────────────────────────────────────────────

class AssetEntry:
	var path: String
	var aabb_min: Vector3
	var aabb_max: Vector3
	var asset_id: int
	## Cache des octets bruts du fichier .fovea (évite la relecture disque)
	var cached_bytes: PackedByteArray
	## Cache des blocs spatiaux avec leurs AABB pré-calculées
	var cached_blocks: Array  # Array[BlockData]
	## Cache des chunks spatiaux
	var cached_chunks: Array = [] # Array[SpatialChunk]

class BlockData:
	var start_index: int
	var end_index: int
	var aabb: AABB

class SpatialChunk:
	var index: int
	var aabb: AABB
	var raw_bytes: PackedByteArray
	var is_loaded: bool = false

signal chunk_loaded(asset_id: int, chunk_index: int)
signal chunk_unloaded(asset_id: int, chunk_index: int)

var chunk_load_radius: float = 20.0
var _previously_loaded_chunks: Dictionary = {} # asset_id -> Array[int]

# ── État interne ──────────────────────────────────────────────────────────────

## Registre des assets : chemin → AssetEntry
var _entries: Dictionary = {}
## Compteur d'IDs (non recyclés pour la simplicité)
var _next_id: int = 0

## RenderingDevice local (isolé du rendu principal pour éviter les conflits)
var rd: RenderingDevice

## Shaders et pipelines compute
var _cull_shader:   RID
var _cull_pipeline: RID
var _depth_shader:   RID
var _depth_pipeline: RID
var _sort_shader:   RID
var _sort_pipeline: RID

## Compteur de frames pour l'entrelacement temporel du tri
var _frame_counter: int = 0

## Facteur d'entrelacement du tri GPU (1=complet, 2=demi, 4=quart — recommandé VR)
var sort_interleave_factor: int = 4

# ── Initialisation ────────────────────────────────────────────────────────────

func _init() -> void:
	rd = RenderingServer.create_local_rendering_device()
	_load_shaders()

func _load_shaders() -> void:
	# Shader de culling multi-asset (avec subgroup ballot)
	var cull_file: RDShaderFile = load("res://addons/foveacore/shaders/gpu_culling_multi.glsl")
	var cull_spirv: RDShaderSPIRV = cull_file.get_spirv()
	_cull_shader   = rd.shader_create_from_spirv(cull_spirv)
	_cull_pipeline = rd.compute_pipeline_create(_cull_shader)

	# Shader de pré-calcul des clés de profondeur
	var depth_file: RDShaderFile = load("res://addons/foveacore/shaders/depth_precompute.glsl")
	var depth_spirv: RDShaderSPIRV = depth_file.get_spirv()
	_depth_shader   = rd.shader_create_from_spirv(depth_spirv)
	_depth_pipeline = rd.compute_pipeline_create(_depth_shader)

	# Shader de tri bitonique avec clés pré-calculées
	var sort_file: RDShaderFile = load("res://addons/foveacore/shaders/sort_bitonic_keyed.glsl")
	var sort_spirv: RDShaderSPIRV = sort_file.get_spirv()
	_sort_shader   = rd.shader_create_from_spirv(sort_spirv)
	_sort_pipeline = rd.compute_pipeline_create(_sort_shader)

# ── API publique ──────────────────────────────────────────────────────────────

## Enregistre un asset .fovea dans le dispatcher.
## @param path     Chemin vers le fichier .fovea
## @param aabb_min AABB minimum de l'asset (pour déquantification)
## @param aabb_max AABB maximum de l'asset
## @returns asset_id alloué (0..255), ou -1 si MAX_ASSETS est atteint
func register_asset(path: String, aabb_min: Vector3, aabb_max: Vector3) -> int:
	if _entries.has(path):
		return (_entries[path] as AssetEntry).asset_id
	if _next_id >= MAX_ASSETS:
		push_error("FoveaSplatDispatcher: MAX_ASSETS (%d) atteint." % MAX_ASSETS)
		return -1

	var entry := AssetEntry.new()
	entry.path     = path
	entry.aabb_min = aabb_min
	entry.aabb_max = aabb_max
	entry.asset_id = _next_id
	_next_id += 1
	_entries[path] = entry

	print("FoveaSplatDispatcher: Asset enregistré '%s' → id=%d" % [path.get_file(), entry.asset_id])
	return entry.asset_id

## Désenregistre un asset (libère le cache mémoire, pas l'asset_id).
func unregister_asset(path: String) -> void:
	if _entries.has(path):
		_entries.erase(path)
		print("FoveaSplatDispatcher: Asset désenregistré '%s'." % path.get_file())

## Traitement d'un frame : culling + tri vectorisé de tous les assets enregistrés.
## @param camera    Caméra 3D active (pour frustum + matrices stéréo)
## @param depth_tex RID de la texture de profondeur (invalide = désactive Hi-Z)
## @param cull_threshold Seuil backface (0.0 = élimine tout > 90°)
## @returns { buffer_rid: RID, count: int } — appelant doit libérer buffer_rid via rd.free_rid()
##          Retourne {} si aucun splat visible.
func process_frame(camera: Camera3D, depth_tex: RID, cull_threshold: float = 0.0) -> Dictionary:
	if _entries.is_empty():
		return {}

	var cam_pos: Vector3 = camera.global_position

	# ── Étape 1 : Construire le buffer AssetData (32 bytes/asset) ─────────────
	var num_assets: int = _next_id
	var asset_data_bytes := PackedByteArray()
	asset_data_bytes.resize(num_assets * 32)
	for path: String in _entries:
		var entry: AssetEntry = _entries[path]
		var base: int = entry.asset_id * 32
		asset_data_bytes.encode_float(base + 0,  entry.aabb_min.x)
		asset_data_bytes.encode_float(base + 4,  entry.aabb_min.y)
		asset_data_bytes.encode_float(base + 8,  entry.aabb_min.z)
		asset_data_bytes.encode_float(base + 12, 0.0)  # pad0
		asset_data_bytes.encode_float(base + 16, entry.aabb_max.x)
		asset_data_bytes.encode_float(base + 20, entry.aabb_max.y)
		asset_data_bytes.encode_float(base + 24, entry.aabb_max.z)
		asset_data_bytes.encode_float(base + 28, 0.0)  # pad1

	# ── Étape 2 : CPU Frustum Cull + Distance Load + Concaténation du mega-buffer ─────────────
	var frustum := FrustumUtils.Frustum.new()
	frustum.from_matrix(camera.get_camera_projection(), camera.global_transform)

	var mega_bytes := PackedByteArray()
	var total_chunks_culled: int = 0
	var total_chunks_input:  int = 0
	var total_chunks_loaded: int = 0

	for path: String in _entries:
		var entry: AssetEntry = _entries[path]

		# Chargement des octets (avec cache disque)
		if entry.cached_bytes.is_empty():
			entry.cached_bytes = _load_fovea_bytes(path)
			if entry.cached_bytes.is_empty():
				push_warning("FoveaSplatDispatcher: Impossible de charger '%s'." % path)
				continue

		# Pré-calcul des chunks spatiaux (avec cache)
		if entry.cached_chunks.is_empty():
			entry.cached_chunks = _precompute_spatial_chunks(path, entry.cached_bytes, entry.aabb_min, entry.aabb_max)

		var asset_id_byte: int = entry.asset_id
		var current_loaded_indices: Array[int] = []
		var prev_loaded_indices: Array = _previously_loaded_chunks.get(asset_id_byte, [])

		for chunk: SpatialChunk in entry.cached_chunks:
			if chunk.raw_bytes.is_empty():
				continue
			total_chunks_input += 1
			
			var dist := _distance_to_aabb(cam_pos, chunk.aabb)
			if dist <= chunk_load_radius:
				chunk.is_loaded = true
				total_chunks_loaded += 1
				current_loaded_indices.append(chunk.index)
				
				# Check frustum culling
				if frustum.contains_aabb(chunk.aabb):
					# Tague chaque splat avec son asset_id dans le byte layer_id (offset 13)
					var chunk_bytes := chunk.raw_bytes.duplicate()
					var n_splats := chunk_bytes.size() / SPLAT_BYTE_SIZE
					for i: int in range(n_splats):
						chunk_bytes[i * SPLAT_BYTE_SIZE + 13] = asset_id_byte
					mega_bytes.append_array(chunk_bytes)
				else:
					total_chunks_culled += 1
			else:
				chunk.is_loaded = false

		# Emit signals / prints for newly loaded/unloaded chunks
		for idx in current_loaded_indices:
			if not prev_loaded_indices.has(idx):
				emit_signal("chunk_loaded", asset_id_byte, idx)
				print("FoveaSplatDispatcher: Asset %d Spatial Chunk %d loaded (distance <= %.1fm)" % [asset_id_byte, idx, chunk_load_radius])
				
		for idx in prev_loaded_indices:
			if not current_loaded_indices.has(idx):
				emit_signal("chunk_unloaded", asset_id_byte, idx)
				print("FoveaSplatDispatcher: Asset %d Spatial Chunk %d unloaded (distance > %.1fm)" % [asset_id_byte, idx, chunk_load_radius])
				
		_previously_loaded_chunks[asset_id_byte] = current_loaded_indices

	if mega_bytes.is_empty():
		return {}

	if total_chunks_culled > 0:
		print("FoveaSplatDispatcher: CPU Frustum Cull : %d/%d chunks éliminés." % [
			total_chunks_culled, total_chunks_loaded])

	var total_splats: int = mega_bytes.size() / SPLAT_BYTE_SIZE
	print("FoveaSplatDispatcher: Dispatch vectorisé — %d splats (multi-asset)." % total_splats)

	# ── Étape 3 : GPU Culling multi-asset ─────────────────────────────────────
	var cull_result := _gpu_cull_multi(mega_bytes, total_splats, num_assets,
			asset_data_bytes, camera, depth_tex, cull_threshold)
	if cull_result.is_empty():
		return {}

	var output_buffer: RID = cull_result["buffer"]
	var valid_count: int   = cull_result["count"]

	if valid_count == 0:
		rd.free_rid(output_buffer)
		return {}

	print("FoveaSplatDispatcher: GPU Culling → %d splats valides (%.1f%% éliminés)." % [
		valid_count, (1.0 - float(valid_count) / total_splats) * 100.0])

	# ── Étape 4 : Pré-calcul des clés de profondeur ───────────────────────────
	var depth_buffer: RID = _precompute_depths(
			output_buffer, valid_count, num_assets, asset_data_bytes, cam_pos)

	# ── Étape 5 : Tri bitonique keyed (une seule compute list) ────────────────
	_keyed_sort_bitonic(output_buffer, depth_buffer, valid_count)
	rd.free_rid(depth_buffer)

	print("FoveaSplatDispatcher: Tri bitonique keyed terminé (frame %d, facteur %d)." % [
		_frame_counter, sort_interleave_factor])
	_frame_counter += 1

	return { "buffer_rid": output_buffer, "count": valid_count }

## Libère toutes les ressources GPU (appeler à la destruction de la scène).
func cleanup() -> void:
	if rd:
		if _cull_pipeline.is_valid():
			rd.free_rid(_cull_pipeline)
			_cull_pipeline = RID()
		if _cull_shader.is_valid():
			rd.free_rid(_cull_shader)
			_cull_shader = RID()
		if _depth_pipeline.is_valid():
			rd.free_rid(_depth_pipeline)
			_depth_pipeline = RID()
		if _depth_shader.is_valid():
			rd.free_rid(_depth_shader)
			_depth_shader = RID()
		if _sort_pipeline.is_valid():
			rd.free_rid(_sort_pipeline)
			_sort_pipeline = RID()
		if _sort_shader.is_valid():
			rd.free_rid(_sort_shader)
			_sort_shader = RID()
		rd.free()
		rd = null

# ── Pipeline GPU interne ──────────────────────────────────────────────────────

func _gpu_cull_multi(
		mega_bytes:       PackedByteArray,
		total_splats:     int,
		num_assets:       int,
		asset_data_bytes: PackedByteArray,
		camera:           Camera3D,
		depth_tex:        RID,
		cull_threshold:   float
) -> Dictionary:
	# Créer les buffers GPU
	var input_buf  := rd.storage_buffer_create(mega_bytes.size(), mega_bytes)
	var output_buf := rd.storage_buffer_create(mega_bytes.size())

	var zero4: PackedByteArray = PackedByteArray()
	zero4.resize(4)
	var counter_buf := rd.storage_buffer_create(4, zero4)
	var asset_buf   := rd.storage_buffer_create(asset_data_bytes.size(), asset_data_bytes)

	# Set 0 : input, output, counter, asset_data
	var u_input   := RDUniform.new()
	u_input.uniform_type  = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_input.binding       = 0
	u_input.add_id(input_buf)

	var u_output  := RDUniform.new()
	u_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_output.binding      = 1
	u_output.add_id(output_buf)

	var u_counter := RDUniform.new()
	u_counter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_counter.binding      = 2
	u_counter.add_id(counter_buf)

	var u_assets  := RDUniform.new()
	u_assets.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_assets.binding      = 3
	u_assets.add_id(asset_buf)

	var set0: RID = rd.uniform_set_create([u_input, u_output, u_counter, u_assets], _cull_shader, 0)

	# Set 1 : depth_map (fallback 1×1 si invalide) + camera UBO
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	var sampler_rid: RID = rd.sampler_create(sampler_state)

	var actual_depth_tex: RID = depth_tex
	var dummy_tex: RID = RID()
	if not actual_depth_tex.is_valid():
		dummy_tex       = _create_dummy_depth_texture()
		actual_depth_tex = dummy_tex

	var u_depth := RDUniform.new()
	u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_depth.binding      = 0
	u_depth.add_id(sampler_rid)
	u_depth.add_id(actual_depth_tex)

	var cam_ubo_bytes: PackedByteArray = _build_camera_ubo_bytes(camera)
	var cam_buf: RID = rd.storage_buffer_create(cam_ubo_bytes.size(), cam_ubo_bytes)
	var u_camera := RDUniform.new()
	u_camera.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_camera.binding      = 1
	u_camera.add_id(cam_buf)

	var set1: RID = rd.uniform_set_create([u_depth, u_camera], _cull_shader, 1)

	# Push constants : 32 bytes
	var cam_pos: Vector3 = camera.global_position
	var push := PackedByteArray()
	push.resize(32)
	push.encode_float(0,  cam_pos.x)
	push.encode_float(4,  cam_pos.y)
	push.encode_float(8,  cam_pos.z)
	push.encode_u32(12,   total_splats)
	push.encode_float(16, cull_threshold)
	push.encode_u32(20,   num_assets)
	push.encode_u32(24,   0)
	push.encode_u32(28,   0)

	# Exécution
	var wg: int = ceili(float(total_splats) / 256.0)
	var cl: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _cull_pipeline)
	rd.compute_list_bind_uniform_set(cl, set0, 0)
	rd.compute_list_bind_uniform_set(cl, set1, 1)
	rd.compute_list_set_push_constant(cl, push, 32)
	rd.compute_list_dispatch(cl, wg, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

	# Lecture du compteur atomique
	var count_bytes: PackedByteArray = rd.buffer_get_data(counter_buf)
	var valid_count: int = count_bytes.decode_u32(0)

	# Nettoyage (garder output_buf pour la suite du pipeline)
	rd.free_rid(input_buf)
	rd.free_rid(counter_buf)
	rd.free_rid(asset_buf)
	rd.free_rid(cam_buf)
	if dummy_tex.is_valid():
		rd.free_rid(dummy_tex)

	if valid_count == 0:
		rd.free_rid(output_buf)
		return {}

	return { "buffer": output_buf, "count": valid_count }

func _precompute_depths(
		splat_buf:        RID,
		count:            int,
		num_assets:       int,
		asset_data_bytes: PackedByteArray,
		cam_pos:          Vector3
) -> RID:
	# Allouer le buffer de clés de profondeur (1 float par splat)
	var depth_buf_size: int = count * 4  # float32 par splat
	var depth_buf: RID = rd.storage_buffer_create(depth_buf_size)

	var asset_buf: RID = rd.storage_buffer_create(asset_data_bytes.size(), asset_data_bytes)

	var u_splats  := RDUniform.new()
	u_splats.uniform_type  = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_splats.binding       = 0
	u_splats.add_id(splat_buf)

	var u_depths  := RDUniform.new()
	u_depths.uniform_type  = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_depths.binding       = 1
	u_depths.add_id(depth_buf)

	var u_assets  := RDUniform.new()
	u_assets.uniform_type  = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_assets.binding       = 2
	u_assets.add_id(asset_buf)

	var set0: RID = rd.uniform_set_create([u_splats, u_depths, u_assets], _depth_shader, 0)

	# Push constants : 32 bytes
	var push := PackedByteArray()
	push.resize(32)
	push.encode_u32(0,    count)
	push.encode_float(4,  cam_pos.x)
	push.encode_float(8,  cam_pos.y)
	push.encode_float(12, cam_pos.z)
	push.encode_u32(16,   num_assets)
	push.encode_u32(20,   0)
	push.encode_u32(24,   0)
	push.encode_u32(28,   0)

	var wg: int = ceili(float(count) / 256.0)
	var cl: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _depth_pipeline)
	rd.compute_list_bind_uniform_set(cl, set0, 0)
	rd.compute_list_set_push_constant(cl, push, 32)
	rd.compute_list_dispatch(cl, wg, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

	rd.free_rid(asset_buf)
	return depth_buf

func _keyed_sort_bitonic(splat_buf: RID, depth_buf: RID, count: int) -> void:
	# Puissance de 2 supérieure ou égale à count
	var padded: int = 1
	while padded < count:
		padded <<= 1

	var u_splats := RDUniform.new()
	u_splats.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_splats.binding      = 0
	u_splats.add_id(splat_buf)

	var u_depths := RDUniform.new()
	u_depths.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_depths.binding      = 1
	u_depths.add_id(depth_buf)

	var sort_set: RID = rd.uniform_set_create([u_splats, u_depths], _sort_shader, 0)
	var wg: int = ceili(float(padded) / 256.0)

	# Masque temporel interleaved
	var frame_mask: int = sort_interleave_factor - 1   # 0 / 1 / 3
	var frame_id:   int = _frame_counter & frame_mask

	# Toutes les passes du tri dans UNE SEULE compute list → 1 seul submit/sync
	var cl: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _sort_pipeline)
	rd.compute_list_bind_uniform_set(cl, sort_set, 0)

	var stage: int = 2
	while stage <= padded:
		var step: int = stage >> 1
		while step > 0:
			var push := PackedByteArray()
			push.resize(32)
			push.encode_u32(0,  count)
			push.encode_u32(4,  padded)
			push.encode_u32(8,  step)
			push.encode_u32(12, stage)
			push.encode_u32(16, frame_mask)
			push.encode_u32(20, frame_id)
			push.encode_u32(24, 0)
			push.encode_u32(28, 0)

			rd.compute_list_set_push_constant(cl, push, 32)
			rd.compute_list_dispatch(cl, wg, 1, 1)
			step >>= 1
		stage <<= 1

	rd.compute_list_end()
	# UN SEUL submit+sync pour toutes les passes
	rd.submit()
	rd.sync()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _build_camera_ubo_bytes(camera: Camera3D) -> PackedByteArray:
	## Construit le bloc UBO caméra stéréo (128 bytes = 2 × mat4)
	var view_matrix := camera.get_camera_transform().affine_inverse()
	var proj_matrix := camera.get_camera_projection()
	var vp          := proj_matrix * Projection(view_matrix)

	var bytes := PackedByteArray()
	bytes.resize(128)
	for r: int in 4:
		for c: int in 4:
			bytes.encode_float((r * 16) + (c * 4), vp[r][c])
			# Œil droit = même matrice en mode single-view (fallback)
			bytes.encode_float(64 + (r * 16) + (c * 4), vp[r][c])
	return bytes

func _create_dummy_depth_texture() -> RID:
	## Texture de profondeur 1×1 blanche (Hi-Z désactivé si depth_tex invalide)
	var img := Image.create(1, 1, false, Image.FORMAT_RF)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	var rd_img_format := RDTextureFormat.new()
	rd_img_format.format     = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	rd_img_format.width      = 1
	rd_img_format.height     = 1
	rd_img_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
							   RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	var rd_img_view := RDTextureView.new()
	var data := img.get_data()
	return rd.texture_create(rd_img_format, rd_img_view, [data])

func _load_fovea_bytes(fovea_path: String) -> PackedByteArray:
	## Charge les octets d'un fichier .fovea (GDExtension Rust ou fallback GDScript)
	if ClassDB.can_instantiate("FoveaAssetLoader"):
		var loader := ClassDB.instantiate("FoveaAssetLoader")
		if loader:
			var bytes: PackedByteArray = loader.load_fast_path(fovea_path)
			if not bytes.is_empty():
				return bytes

	if not FileAccess.file_exists(fovea_path):
		push_error("FoveaSplatDispatcher: Fichier introuvable : " + fovea_path)
		return PackedByteArray()

	var f := FileAccess.open(fovea_path, FileAccess.READ)
	if not f:
		push_error("FoveaSplatDispatcher: Impossible d'ouvrir : " + fovea_path)
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes

func _precompute_blocks(raw_bytes: PackedByteArray, aabb_min: Vector3, aabb_max: Vector3) -> Array:
	## Découpe le buffer en blocs de BLOCK_SIZE splats et calcule leur AABB locale.
	var blocks: Array = []
	var total_splats: int  = raw_bytes.size() / SPLAT_BYTE_SIZE
	var block_count: int   = ceili(float(total_splats) / BLOCK_SIZE)
	var range_vec: Vector3 = aabb_max - aabb_min

	for b: int in range(block_count):
		var start: int = b * BLOCK_SIZE
		var end: int   = mini(start + BLOCK_SIZE, total_splats)

		var min_pos := Vector3(1e9, 1e9, 1e9)
		var max_pos := Vector3(-1e9, -1e9, -1e9)

		for i: int in range(start, end):
			var off: int = i * SPLAT_BYTE_SIZE
			var qx: int  = raw_bytes.decode_u16(off)
			var qy: int  = raw_bytes.decode_u16(off + 2)
			var qz: int  = raw_bytes.decode_u16(off + 4)
			var pos := aabb_min + Vector3(float(qx), float(qy), float(qz)) / 65535.0 * range_vec
			min_pos.x = minf(min_pos.x, pos.x)
			min_pos.y = minf(min_pos.y, pos.y)
			min_pos.z = minf(min_pos.z, pos.z)
			max_pos.x = maxf(max_pos.x, pos.x)
			max_pos.y = maxf(max_pos.y, pos.y)
			max_pos.z = maxf(max_pos.z, pos.z)

		var block := BlockData.new()
		block.start_index = start
		block.end_index   = end
		# Légère marge pour éviter le culling agressif aux bords des ellipses
		block.aabb        = AABB(min_pos, max_pos - min_pos).grow(0.1)
		blocks.append(block)

	return blocks

func _distance_to_aabb(point: Vector3, aabb: AABB) -> float:
	var closest_point := Vector3(
		clamp(point.x, aabb.position.x, aabb.end.x),
		clamp(point.y, aabb.position.y, aabb.end.y),
		clamp(point.z, aabb.position.z, aabb.end.z)
	)
	return point.distance_to(closest_point)

func _precompute_spatial_chunks(fovea_path: String, raw_bytes: PackedByteArray, aabb_min: Vector3, aabb_max: Vector3) -> Array[SpatialChunk]:
	var chunks: Array[SpatialChunk] = []
	chunks.resize(4096)
	
	var size_cell := (aabb_max - aabb_min) / 16.0
	for i in range(4096):
		var chunk := SpatialChunk.new()
		chunk.index = i
		var cx := i & 15
		var cy := (i >> 4) & 15
		var cz := (i >> 8) & 15
		var pos_cell := aabb_min + Vector3(cx, cy, cz) * size_cell
		chunk.aabb = AABB(pos_cell, size_cell)
		chunk.raw_bytes = PackedByteArray()
		chunks[i] = chunk

	var total_splats := raw_bytes.size() / SPLAT_BYTE_SIZE
	var range_vec := aabb_max - aabb_min
	
	var buckets: Array[Array] = []
	buckets.resize(4096)
	for i in range(4096):
		buckets[i] = []

	# Map each splat to its chunk
	for i in range(total_splats):
		var offset := i * SPLAT_BYTE_SIZE
		var qx := raw_bytes.decode_u16(offset)
		var qy := raw_bytes.decode_u16(offset + 2)
		var qz := raw_bytes.decode_u16(offset + 4)
		
		var cell_x: int = clamp(int(float(qx) / 65535.0 * 16.0), 0, 15)
		var cell_y: int = clamp(int(float(qy) / 65535.0 * 16.0), 0, 15)
		var cell_z: int = clamp(int(float(qz) / 65535.0 * 16.0), 0, 15)
		
		var chunk_idx: int = cell_x + (cell_y << 4) + (cell_z << 8)
		buckets[chunk_idx].append(i)

	# Populate raw_bytes using contiguous index slicing
	for i in range(4096):
		var indices: Array = buckets[i]
		if indices.is_empty():
			continue
		var chunk: SpatialChunk = chunks[i]
		var chunk_bytes := PackedByteArray()
		
		var start_idx: int = indices[0]
		var count: int = 1
		for j in range(1, indices.size()):
			var idx: int = indices[j]
			if idx == start_idx + count:
				count += 1
			else:
				var src_offset := start_idx * SPLAT_BYTE_SIZE
				var size := count * SPLAT_BYTE_SIZE
				chunk_bytes.append_array(raw_bytes.slice(src_offset, src_offset + size))
				start_idx = idx
				count = 1
		
		var src_offset := start_idx * SPLAT_BYTE_SIZE
		var size := count * SPLAT_BYTE_SIZE
		chunk_bytes.append_array(raw_bytes.slice(src_offset, src_offset + size))
		
		chunk.raw_bytes = chunk_bytes

	return chunks
