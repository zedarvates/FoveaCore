class_name GPUCullerPipeline
extends RefCounted

## FoveaEngine : Pipeline de Compute Shader pour le Backface Culling + Tri Bitonique
## VERSION TRIANGLE - Optimise pour le rendu par maillage triangulaire
## Phase 3 : Temporal & Interleaved Sorting - tri non-bloquant sur plusieurs frames

class BlockData:
    var start_index: int
    var end_index: int
    var aabb: AABB

class SpatialChunk:
    var index: int
    var aabb: AABB
    var raw_bytes: PackedByteArray
    var is_loaded: bool = false

signal chunk_loaded(chunk_index: int)
signal chunk_unloaded(chunk_index: int)

var chunk_load_radius: float = 20.0
var _cached_chunks: Dictionary = {} # fovea_path -> Array[SpatialChunk]
var _previously_loaded_chunks: Dictionary = {} # fovea_path -> Array[int]

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var sort_shader_rid: RID
var sort_pipeline_rid: RID

# Persistent Vulkan buffer cache to avoid per-frame allocation stalls
# Structure: { fovea_path: { "input": RID, "output": RID, "counter": RID, "camera_ubo": RID, "uniform_set": RID, "size": int } }
var _gpu_buffers: Dictionary = {}

# Configuration du nettoyage (appliqué une seule fois au chargement pour éviter la surcharge CPU par frame)
var enable_cleaning: bool = true
var floater_neighbor_radius: int = 1
var floater_min_neighbors: int = 2
var enable_decimation: bool = false
var decimation_target: int = 50000
var enable_coplanar_merge: bool = false
var coplanar_z_bucket: int = 512
var coplanar_min_group: int = 4

const SPLAT_BYTE_SIZE: int = 16 # Format Fast-Path (FoveaPackedSplat)

## Etat du tri temporel entrelace
## interleave_factor = 1 : tri complet chaque frame (comportement legacy)
## interleave_factor = 2 : moitie des splats ce frame, l'autre moitie la prochaine
## interleave_factor = 4 : quart des splats par frame (recommande VR 90Hz)
var interleave_factor: int = 4
var _frame_counter: int    = 0

## Cache pour eviter d'acceder au disque ou de recalculer a chaque frame
var _cached_bytes: Dictionary = {}
var _cached_blocks: Dictionary = {}

func _init() -> void:
    rd = RenderingServer.create_local_rendering_device()
    if rd:
        _load_compute_shader()
    else:
        push_warning("GPUCullerPipeline: local rendering device not available (headless or dummy/compatibility renderer).")

func _load_compute_shader() -> void:
    if not rd:
        return
    var shader_file: RDShaderFile = load("res://addons/foveacore/shaders/gpu_culling_compute.glsl")
    var spirv: RDShaderSPIRV = shader_file.get_spirv()
    shader_rid    = rd.shader_create_from_spirv(spirv)
    pipeline_rid  = rd.compute_pipeline_create(shader_rid)

    # Nouveau shader bitonique : opere directement sur PackedSplat, sans depth+indices separes
    var sort_file: RDShaderFile = load("res://addons/foveacore/shaders/sort_bitonic_splats.glsl")
    sort_shader_rid   = rd.shader_create_from_spirv(sort_file.get_spirv())
    sort_pipeline_rid = rd.compute_pipeline_create(sort_shader_rid)

## Charge le fichier via Rust et exécute le Culling sur le GPU
func process_splats_from_file(fovea_path: String, camera: Camera3D, depth_texture: RID, cull_threshold: float = 0.0,
    aabb_min: Vector3 = Vector3(-5, -5, -5), aabb_max: Vector3 = Vector3(5, 5, 5)) -> RID:
    if not rd:
        push_error("GPU Culler: RenderingDevice is not available. Skipping culling.")
        return RID()
    # 1. Chargement des octets bruts (via GDExtension si disponible, sinon fallback GDScript)
    var raw_bytes: PackedByteArray = _load_fovea_bytes(fovea_path)
    if raw_bytes.is_empty():
        push_error("FoveaEngine: Échec du chargement du fichier Fast-Path.")
        return RID()
        
    var cam_pos = camera.global_position
    # 1.5. Culling de frustum CPU par bloc spatial + Chargement à la distance (Phase 3: Spatial Chunking)
    var chunks := _precompute_spatial_chunks(fovea_path, raw_bytes, aabb_min, aabb_max)
    var frustum = FrustumUtils.Frustum.new()
    frustum.from_matrix(camera.get_camera_projection(), camera.global_transform)
    
    var current_loaded_indices: Array[int] = []
    var prev_loaded_indices: Array = _previously_loaded_chunks.get(fovea_path, [])
    
    var visible_bytes := PackedByteArray()
    var loaded_count := 0
    var visible_count := 0
    var non_empty_chunks := 0
    
    for chunk in chunks:
        if chunk.raw_bytes.is_empty():
            continue
        non_empty_chunks += 1
        
        var dist := _distance_to_aabb(cam_pos, chunk.aabb)
        if dist <= chunk_load_radius:
            chunk.is_loaded = true
            loaded_count += 1
            current_loaded_indices.append(chunk.index)
            
            # Check frustum culling
            if frustum.contains_aabb(chunk.aabb):
                visible_count += 1
                visible_bytes.append_array(chunk.raw_bytes)
        else:
            chunk.is_loaded = false

    # Emit signals / prints for newly loaded/unloaded chunks
    for idx in current_loaded_indices:
        if not prev_loaded_indices.has(idx):
            emit_signal("chunk_loaded", idx)
            print("FoveaEngine: Spatial Chunk %d loaded (distance <= %.1fm)" % [idx, chunk_load_radius])
            
    for idx in prev_loaded_indices:
        if not current_loaded_indices.has(idx):
            emit_signal("chunk_unloaded", idx)
            print("FoveaEngine: Spatial Chunk %d unloaded (distance > %.1fm)" % [idx, chunk_load_radius])
            
    _previously_loaded_chunks[fovea_path] = current_loaded_indices
    
    if loaded_count > 0:
        print("FoveaEngine: Spatial Chunking: %d/%d active chunks loaded, %d/%d chunks visible." % [
            loaded_count, non_empty_chunks, visible_count, loaded_count])
            
    if visible_bytes.is_empty():
        print("FoveaEngine: Aucun bloc visible sur le CPU, skip complet GPU.")
        return RID()
        
    var total_splats = visible_bytes.size() / SPLAT_BYTE_SIZE
    print("FoveaEngine: Dispatching Compute Shader pour %d splats visibles..." % total_splats)

    # 2. Caching des Buffers GPU persistants
    var max_buffer_size = raw_bytes.size()
    var cache: Dictionary = _gpu_buffers.get(fovea_path, {})
    var needs_recreation = cache.is_empty() or cache.get("size", 0) < max_buffer_size
    
    if needs_recreation:
        # Libérer l'ancien cache s'il existait
        if not cache.is_empty():
            if cache.get("input", RID()).is_valid(): rd.free_rid(cache["input"])
            if cache.get("output", RID()).is_valid(): rd.free_rid(cache["output"])
            if cache.get("counter", RID()).is_valid(): rd.free_rid(cache["counter"])
            if cache.get("camera_ubo", RID()).is_valid(): rd.free_rid(cache["camera_ubo"])
            if cache.get("uniform_set", RID()).is_valid(): rd.free_rid(cache["uniform_set"])
        
        # Créer les nouveaux buffers persistants à la taille maximale
        var input_buf = rd.storage_buffer_create(max_buffer_size)
        var output_buf = rd.storage_buffer_create(max_buffer_size)
        
        var zero_counter := PackedByteArray([0,0,0,0])
        var counter_buf = rd.storage_buffer_create(4, zero_counter)
        var camera_ubo_buf = rd.storage_buffer_create(128)
        
        # Créer le uniform set persistant 0
        var uniform_input = RDUniform.new()
        uniform_input.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        uniform_input.binding = 0
        uniform_input.add_id(input_buf)
        
        var uniform_output = RDUniform.new()
        uniform_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        uniform_output.binding = 1
        uniform_output.add_id(output_buf)
        
        var uniform_counter = RDUniform.new()
        uniform_counter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        uniform_counter.binding = 2
        uniform_counter.add_id(counter_buf)
        
        var uniform_set_0 = rd.uniform_set_create([uniform_input, uniform_output, uniform_counter], shader_rid, 0)
        
        cache = {
            "input": input_buf,
            "output": output_buf,
            "counter": counter_buf,
            "camera_ubo": camera_ubo_buf,
            "uniform_set": uniform_set_0,
            "size": max_buffer_size
        }
        _gpu_buffers[fovea_path] = cache

    var input_buffer = cache["input"]
    var output_buffer = cache["output"]
    var counter_buffer = cache["counter"]
    var camera_ubo = cache["camera_ubo"]
    var uniform_set = cache["uniform_set"]

    # Mettre à jour les buffers persistants pour cette frame
    rd.buffer_update(input_buffer, 0, visible_bytes.size(), visible_bytes)
    
    var zero_bytes := PackedByteArray([0,0,0,0])
    rd.buffer_update(counter_buffer, 0, 4, zero_bytes)
    
    # 4. Set 1, binding 0: Depth texture
    var sampler_state = RDSamplerState.new()
    sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    var sampler_rid = rd.sampler_create(sampler_state)
    
    var uniform_depth = RDUniform.new()
    uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    uniform_depth.binding = 0
    uniform_depth.add_id(sampler_rid)
    uniform_depth.add_id(depth_texture)
    
    # 4.5. Set 1, binding 1: CameraData UBO (stereo view-projection matrices)
    cam_pos = camera.global_position
    var view_matrix = camera.get_camera_transform().affine_inverse()
    var proj_matrix = camera.get_camera_projection()
    var view_proj = proj_matrix * view_matrix
    
    var camera_data_bytes = PackedByteArray()
    camera_data_bytes.resize(128) # 2 x mat4 (std140)
    var vp_data = view_proj
    for col_idx in 4:
        for row_idx in 4:
            camera_data_bytes.encode_float((col_idx * 16) + (row_idx * 4), vp_data[col_idx][row_idx])
    # Copy same matrix for right eye (single-view fallback)
    for col_idx in 4:
        for row_idx in 4:
            camera_data_bytes.encode_float(64 + (col_idx * 16) + (row_idx * 4), vp_data[col_idx][row_idx])
    
    rd.buffer_update(camera_ubo, 0, 128, camera_data_bytes)
    var uniform_camera = RDUniform.new()
    uniform_camera.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_camera.binding = 1
    uniform_camera.add_id(camera_ubo)
    
    var uniform_set_depth = rd.uniform_set_create([uniform_depth, uniform_camera], shader_rid, 1)
    
    # 5. Push constants matching shader Params layout
    var push_bytes = PackedByteArray()
    push_bytes.resize(56) # vec3+uint+float+float+vec3+float+vec3+float = 56 bytes
    push_bytes.encode_float(0, cam_pos.x)
    push_bytes.encode_float(4, cam_pos.y)
    push_bytes.encode_float(8, cam_pos.z)
    push_bytes.encode_u32(12, total_splats)
    push_bytes.encode_float(16, cull_threshold)
    push_bytes.encode_float(20, 0.0) # padding
    push_bytes.encode_float(24, aabb_min.x)
    push_bytes.encode_float(28, aabb_min.y)
    push_bytes.encode_float(32, aabb_min.z)
    push_bytes.encode_float(36, 0.0) # pad1
    push_bytes.encode_float(40, aabb_max.x)
    push_bytes.encode_float(44, aabb_max.y)
    push_bytes.encode_float(48, aabb_max.z)
    push_bytes.encode_float(52, 0.0) # pad2
    
    # 6. Exécution du Compute Shader
    var compute_list = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set_depth, 1)
    rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
    
    var workgroups = ceil(total_splats / 256.0)
    rd.compute_list_dispatch(compute_list, workgroups, 1, 1)
    rd.compute_list_end()
    
    # 7. Attente et Lecture du compteur
    rd.submit()
    rd.sync()
    
    var result_counter_bytes = rd.buffer_get_data(counter_buffer)
    var valid_splat_count = result_counter_bytes.decode_u32(0)
    
    var culled_percentage = 100.0 - ((float(valid_splat_count) / total_splats) * 100.0)
    print("FoveaEngine: Compute Culling terminé. Splats restants : %d (%.1f%% supprimés)" % [valid_splat_count, culled_percentage])
    
    # 7. TRI BITONIQUE TEMPOREL (Phase 3 : Temporal & Interleaved Sorting)
    # AVANT : submit()+sync() a CHAQUE etape => O(log^2(N)) stalls CPU<->GPU
    # APRES  : toutes les passes dans UNE seule compute list => 1 seul submit()+sync()
    # + repartition temporelle : seulement 1/interleave_factor des splats est retrie
    #   ce frame, evitant le pic GPU qui causait les frame drops VR.
    if valid_splat_count > 1:
        _temporal_sort_bitonic(
            output_buffer, valid_splat_count, cam_pos,
            aabb_min, aabb_max
        )
        print("FoveaEngine: GPU Bitonic Sort temporel termine (frame %d, facteur %d)." % \
            [_frame_counter, interleave_factor])
 
    _frame_counter += 1
 
    # Libération du sampler temporaire
    rd.free_rid(sampler_rid)
 
    return output_buffer

## Tri bitonique GPU en UNE SEULE compute list non-bloquante.
## Toutes les etapes (stage/step) sont enchainees sans submit() intermediaire.
## Support Temporal Interleaved : seule une fraction des splats est triee ce frame.
func _temporal_sort_bitonic(
        buffer_rid: RID,
        splat_count: int,
        cam_pos:   Vector3,
        aabb_min:  Vector3,
        aabb_max:  Vector3
) -> void:
    # Puissance de 2 superieure ou egale a splat_count
    var padded: int = 1
    while padded < splat_count:
        padded <<= 1

    var sort_uniform: RDUniform = RDUniform.new()
    sort_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    sort_uniform.binding      = 0
    sort_uniform.add_id(buffer_rid)
    var sort_set: RID = rd.uniform_set_create([sort_uniform], sort_shader_rid, 0)

    var sort_workgroups: int = int(ceil(float(padded) / 256.0))
    var aabb_range: float = (aabb_max - aabb_min).length()

    # Calcul du masque temporel pour ce frame
    # interleave_factor=1 => frame_mask=0 (tous les splats chaque frame)
    # interleave_factor=2 => frame_mask=1, frame_id= 0 ou 1 alternativement
    # interleave_factor=4 => frame_mask=3, frame_id= 0,1,2,3 en rotation
    var frame_mask: int = interleave_factor - 1  # 0, 1, ou 3
    var frame_id:   int = _frame_counter & frame_mask

    # --- Enchainage de TOUTES les passes dans une seule compute list ---
    var compute_list: int = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, sort_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, sort_set, 0)

    var stage: int = 2
    while stage <= padded:
        var step_size: int = stage >> 1
        while step_size > 0:
            var pc_bytes: PackedByteArray = PackedByteArray()
            pc_bytes.resize(64)  # Alignement std430 sur 16 bytes
            pc_bytes.encode_u32(0,  splat_count)
            pc_bytes.encode_u32(4,  padded)
            pc_bytes.encode_u32(8,  step_size)
            pc_bytes.encode_u32(12, stage)
            pc_bytes.encode_float(16, cam_pos.x)
            pc_bytes.encode_float(20, cam_pos.y)
            pc_bytes.encode_float(24, cam_pos.z)
            pc_bytes.encode_float(28, aabb_range)
            pc_bytes.encode_u32(32,  frame_mask)
            pc_bytes.encode_u32(36,  frame_id)
            pc_bytes.encode_float(40, aabb_min.x)
            pc_bytes.encode_float(44, aabb_min.y)
            pc_bytes.encode_float(48, aabb_min.z)
            pc_bytes.encode_float(52, 0.0)  # pad0
            pc_bytes.encode_float(56, 0.0)  # pad1
            pc_bytes.encode_float(60, 0.0)  # pad2

            rd.compute_list_set_push_constant(compute_list, pc_bytes, 64)
            rd.compute_list_dispatch(compute_list, sort_workgroups, 1, 1)

            step_size >>= 1
        stage <<= 1

    rd.compute_list_end()
    # UN SEUL submit+sync pour toutes les passes = elimine tous les stalls intermediaires
    rd.submit()
    rd.sync()

func _load_fovea_bytes(fovea_path: String) -> PackedByteArray:
    if _cached_bytes.has(fovea_path):
        return _cached_bytes[fovea_path]

    var bytes: PackedByteArray = PackedByteArray()
    if ClassDB.can_instantiate("FoveaAssetLoader"):
        var loader = ClassDB.instantiate("FoveaAssetLoader")
        if loader:
            bytes = loader.load_fast_path(fovea_path)
    if bytes.is_empty():
        if not FileAccess.file_exists(fovea_path):
            push_error("GPU Culler: File not found: " + fovea_path)
            return PackedByteArray()
        var file = FileAccess.open(fovea_path, FileAccess.READ)
        if not file:
            return PackedByteArray()
        var all_bytes = file.get_buffer(file.get_length())
        file.close()
        
        if all_bytes.size() >= 48 and all_bytes.slice(0, 8).get_string_from_ascii() == "FOVEA_3D":
            var color_k = all_bytes.decode_u32(16)
            var covar_k = all_bytes.decode_u32(20)
            var header_size = 48
            var palette_size = color_k * 12
            var covar_size = covar_k * 32
            var splats_start = header_size + palette_size + covar_size
            if all_bytes.size() >= splats_start:
                bytes = all_bytes.slice(splats_start)
        elif all_bytes.size() >= 16:
            bytes = all_bytes.slice(16)
        else:
            bytes = all_bytes
        
    if not bytes.is_empty():
        var before_size = bytes.size() / SPLAT_BYTE_SIZE
        if enable_cleaning:
            bytes = FoveaSplatCleaner.filter_nan_inf(bytes)
            bytes = FoveaSplatCleaner.filter_floaters(bytes, floater_neighbor_radius, floater_min_neighbors)
            if enable_decimation and decimation_target > 0:
                bytes = FoveaSplatCleaner.decimate(bytes, decimation_target)
        if enable_coplanar_merge:
            bytes = FoveaSplatCleaner.merge_coplanar(bytes, coplanar_z_bucket, 24, 1024, coplanar_min_group)
        
        var after_size = bytes.size() / SPLAT_BYTE_SIZE
        if before_size != after_size:
            print("GPUCullerPipeline: Nettoyage statique au chargement de '%s' : %d -> %d splats (-%d)." % [
                fovea_path.get_file(), before_size, after_size, before_size - after_size
            ])
        
    _cached_bytes[fovea_path] = bytes
    return bytes

func _precompute_blocks(fovea_path: String, raw_bytes: PackedByteArray, aabb_min: Vector3, aabb_max: Vector3) -> Array[BlockData]:
    if _cached_blocks.has(fovea_path):
        return _cached_blocks[fovea_path]
        
    var blocks: Array[BlockData] = []
    var total_splats := raw_bytes.size() / SPLAT_BYTE_SIZE
    var block_size_splats := 4096 # 4096 splats per block
    var block_count := int(ceil(float(total_splats) / block_size_splats))
    
    var range_vec := aabb_max - aabb_min
    
    for b in range(block_count):
        var start := b * block_size_splats
        var end := int(min((b + 1) * block_size_splats, total_splats))
        
        var min_pos := Vector3(1e9, 1e9, 1e9)
        var max_pos := Vector3(-1e9, -1e9, -1e9)
        
        for i in range(start, end):
            var offset := i * SPLAT_BYTE_SIZE
            var qx := raw_bytes.decode_u16(offset)
            var qy := raw_bytes.decode_u16(offset + 2)
            var qz := raw_bytes.decode_u16(offset + 4)
            
            var px := float(qx) / 65535.0
            var py := float(qy) / 65535.0
            var pz := float(qz) / 65535.0
            
            var pos := aabb_min + Vector3(px, py, pz) * range_vec
            
            min_pos.x = min(min_pos.x, pos.x)
            min_pos.y = min(min_pos.y, pos.y)
            min_pos.z = min(min_pos.z, pos.z)
            
            max_pos.x = max(max_pos.x, pos.x)
            max_pos.y = max(max_pos.y, pos.y)
            max_pos.z = max(max_pos.z, pos.z)
            
        var block := BlockData.new()
        block.start_index = start
        block.end_index = end
        # On donne une petite marge (e.g. 0.1) aux AABB pour eviter le culling agressif aux bords des ellipses
        block.aabb = AABB(min_pos, max_pos - min_pos).grow(0.1)
        blocks.append(block)
        
    _cached_blocks[fovea_path] = blocks
    return blocks

func cleanup() -> void:
    if rd:
        if pipeline_rid.is_valid():
            rd.free_rid(pipeline_rid)
            pipeline_rid = RID()
        if shader_rid.is_valid():
            rd.free_rid(shader_rid)
            shader_rid = RID()
        if sort_pipeline_rid.is_valid():
            rd.free_rid(sort_pipeline_rid)
            sort_pipeline_rid = RID()
        if sort_shader_rid.is_valid():
            rd.free_rid(sort_shader_rid)
            sort_shader_rid = RID()
        
        # Libérer les buffers GPU persistants en cache
        for path in _gpu_buffers:
            var cache = _gpu_buffers[path]
            if cache.get("input", RID()).is_valid():
                rd.free_rid(cache["input"])
            if cache.get("output", RID()).is_valid():
                rd.free_rid(cache["output"])
            if cache.get("counter", RID()).is_valid():
                rd.free_rid(cache["counter"])
            if cache.get("camera_ubo", RID()).is_valid():
                rd.free_rid(cache["camera_ubo"])
            if cache.get("uniform_set", RID()).is_valid():
                rd.free_rid(cache["uniform_set"])
        _gpu_buffers.clear()
        
        rd.free()
        rd = null

func clear_cache() -> void:
    _cached_bytes.clear()
    _cached_blocks.clear()
    _cached_chunks.clear()

func _distance_to_aabb(point: Vector3, aabb: AABB) -> float:
    var closest_point := Vector3(
        clamp(point.x, aabb.position.x, aabb.end.x),
        clamp(point.y, aabb.position.y, aabb.end.y),
        clamp(point.z, aabb.position.z, aabb.end.z)
    )
    return point.distance_to(closest_point)

func _precompute_spatial_chunks(fovea_path: String, raw_bytes: PackedByteArray, aabb_min: Vector3, aabb_max: Vector3) -> Array[SpatialChunk]:
    if _cached_chunks.has(fovea_path):
        return _cached_chunks[fovea_path]

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
        var offset: int = i * SPLAT_BYTE_SIZE
        var qx: int = raw_bytes.decode_u16(offset)
        var qy: int = raw_bytes.decode_u16(offset + 2)
        var qz: int = raw_bytes.decode_u16(offset + 4)
        
        var cell_x: int = int(clamp(float(qx) / 65535.0 * 16.0, 0.0, 15.0))
        var cell_y: int = int(clamp(float(qy) / 65535.0 * 16.0, 0.0, 15.0))
        var cell_z: int = int(clamp(float(qz) / 65535.0 * 16.0, 0.0, 15.0))
        
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

    _cached_chunks[fovea_path] = chunks
    return chunks