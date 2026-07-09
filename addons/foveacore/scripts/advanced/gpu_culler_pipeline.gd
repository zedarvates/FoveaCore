class_name GPUCullerPipeline
extends RefCounted

const FoveaOctreeBakerClass := preload("res://addons/foveacore/scripts/advanced/fovea_octree_baker.gd")

## FoveaEngine : Pipeline de Compute Shader pour le Backface Culling + Tri Bitonique
## VERSION TRIANGLE - Optimise pour le rendu par maillage triangulaire
## Phase 3 : Temporal & Interleaved Sorting - tri non-bloquant sur plusieurs frames

class BlockData:
    var start_index: int
    var end_index: int
    var aabb: AABB



signal chunk_loaded(chunk_index: int)
signal chunk_unloaded(chunk_index: int)

var chunk_load_radius: float = 20.0
var _cached_chunks: Dictionary = {} # fovea_path -> Array
var _previously_loaded_chunks: Dictionary = {} # fovea_path -> Array[int]
var streaming_manager: RefCounted

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var depth_shader_rid: RID
var depth_pipeline_rid: RID
var sort_shader_rid: RID
var sort_pipeline_rid: RID
var raster_shader_rid: RID
var raster_pipeline_rid: RID

var publish_shader_rid: RID
var publish_pipeline_rid: RID

var delta_shader_rid: RID
var delta_pipeline_rid: RID
var animate_shader_rid: RID
var animate_pipeline_rid: RID

var inst_cull_shader_rid: RID
var inst_cull_pipeline_rid: RID
var indirect_shader_rid: RID
var indirect_pipeline_rid: RID

var hiz_shader_rid: RID
var hiz_pipeline_rid: RID
var hiz_texture_rid: RID
var _last_hiz_tex: RID

var last_valid_splat_count: int = 0
var last_output_buffer_rid: RID
var last_covar_texture_rid: RID
var last_palette_texture_rid: RID
var last_counter_buffer_rid: RID = RID()
var last_use_palette: bool = false
var last_palette_size: int = 16
var last_aabb_min: Vector3 = Vector3.ZERO
var last_aabb_max: Vector3 = Vector3.ZERO
var last_model_transform: Transform3D = Transform3D.IDENTITY
var skip_sync: bool = false

# Persistent Vulkan buffer cache to avoid per-frame allocation stalls
# Structure: { fovea_path: { "input": RID, "output": RID, "counter": RID, "camera_ubo": RID, "uniform_set": RID, "size": int } }
var _gpu_buffers: Dictionary = {}

# Configuration et Allocateur de segments VRAM pour le streaming out-of-core
const MAX_VRAM_SLOTS: int = 512
const BLOCK_SIZE: int = 4096
var _vram_slots_occupied: Array[String] = []
var _vram_allocations: Dictionary = {}
var _vram_lru: Array[String] = []
var _vram_fade_opacities: Dictionary = {}
var _vram_loaded_lod: Dictionary = {}
var _vram_pool_buffer: RID
var _vram_metadata_buffer: RID
var _vram_global_lod_buffers: Dictionary = {} # fovea_path -> RID
var _baked_octrees: Dictionary = {} # fovea_path -> CPU root node (Task 264)
var _static_input_buffers: Dictionary = {} # fovea_path -> RID (Task 267)
var max_uploads_per_frame: int = 3 # Régulateur de bande passante VRAM PCIe (Task 262)

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

## Task 269: Performance profiles for regulating active dynamic splats on GPU
var max_dynamic_splats: int = 50000
var max_dynamic_splats_ratio: float = 0.5

## Cache pour eviter d'acceder au disque ou de recalculer a chaque frame
var _cached_bytes: Dictionary = {}
var _cached_blocks: Dictionary = {}

func _init() -> void:
    streaming_manager = load("res://addons/foveacore/scripts/advanced/fovea_streaming_manager.gd").new()
    _vram_slots_occupied.resize(MAX_VRAM_SLOTS)
    _vram_slots_occupied.fill("")
    rd = RenderingServer.create_local_rendering_device()
    if rd:
        _load_compute_shader()
        _vram_pool_buffer = rd.storage_buffer_create(MAX_VRAM_SLOTS * BLOCK_SIZE * SPLAT_BYTE_SIZE)
        _vram_metadata_buffer = rd.storage_buffer_create(256 * 48) # 256 active chunks max
    else:
        push_warning("GPUCullerPipeline: local rendering device not available (headless or dummy/compatibility renderer).")

func _load_compute_shader() -> void:
    if not rd:
        return
    
    var shader_file: RDShaderFile = load("res://addons/foveacore/shaders/gpu_culling_compute.glsl")
    var spirv: RDShaderSPIRV = shader_file.get_spirv()
    var err: String = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if not err.is_empty():
        push_error("GPU Culler: Error compiling gpu_culling_compute.glsl: " + err)
    shader_rid    = rd.shader_create_from_spirv(spirv)
    if shader_rid.is_valid():
        pipeline_rid  = rd.compute_pipeline_create(shader_rid)
    else:
        push_error("GPU Culler: Failed to create shader_rid for gpu_culling_compute.glsl")

    # Shader de précalcul de profondeur
    var depth_file: RDShaderFile = load("res://addons/foveacore/shaders/depth_precompute.glsl")
    var depth_spirv := depth_file.get_spirv()
    var depth_err: String = depth_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if not depth_err.is_empty():
        push_error("GPU Culler: Error compiling depth_precompute.glsl: " + depth_err)
    depth_shader_rid = rd.shader_create_from_spirv(depth_spirv)
    if depth_shader_rid.is_valid():
        depth_pipeline_rid = rd.compute_pipeline_create(depth_shader_rid)
    else:
        push_error("GPU Culler: Failed to create depth_shader_rid")

    # Shader bitonique keyed : utilise les clés précalculées
    var sort_file: RDShaderFile = load("res://addons/foveacore/shaders/sort_bitonic_keyed.glsl")
    var sort_spirv := sort_file.get_spirv()
    var sort_err: String = sort_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if not sort_err.is_empty():
        push_error("GPU Culler: Error compiling sort_bitonic_keyed.glsl: " + sort_err)
    sort_shader_rid   = rd.shader_create_from_spirv(sort_spirv)
    if sort_shader_rid.is_valid():
        sort_pipeline_rid = rd.compute_pipeline_create(sort_shader_rid)
    else:
        push_error("GPU Culler: Failed to create sort_shader_rid")

    # Shader de génération de pyramide Hi-Z
    var hiz_file: RDShaderFile = load("res://addons/foveacore/shaders/hiz_generator.glsl")
    var hiz_spirv := hiz_file.get_spirv()
    var hiz_err: String = hiz_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if not hiz_err.is_empty():
        push_error("GPU Culler: Error compiling hiz_generator.glsl: " + hiz_err)
    hiz_shader_rid = rd.shader_create_from_spirv(hiz_spirv)
    if hiz_shader_rid.is_valid():
        hiz_pipeline_rid = rd.compute_pipeline_create(hiz_shader_rid)
    else:
        push_error("GPU Culler: Failed to create hiz_shader_rid")

    # Shader de rasterization par tuiles
    var raster_file: RDShaderFile = load("res://addons/foveacore/shaders/tile_rasterizer.glsl")
    var raster_spirv := raster_file.get_spirv()
    var raster_err: String = raster_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if not raster_err.is_empty():
        push_error("GPU Culler: Error compiling tile_rasterizer.glsl: " + raster_err)
    raster_shader_rid = rd.shader_create_from_spirv(raster_spirv)
    if raster_shader_rid.is_valid():
        raster_pipeline_rid = rd.compute_pipeline_create(raster_shader_rid)
    else:
        push_error("GPU Culler: Failed to create raster_shader_rid")

    # Shader de publication (GPU-Driven copy)
    var publish_file: RDShaderFile = load("res://addons/foveacore/shaders/publish_splats.glsl")
    var publish_spirv := publish_file.get_spirv()
    var publish_err: String = publish_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if not publish_err.is_empty():
        push_error("GPU Culler: Error compiling publish_splats.glsl: " + publish_err)
    publish_shader_rid = rd.shader_create_from_spirv(publish_spirv)
    if publish_shader_rid.is_valid():
        publish_pipeline_rid = rd.compute_pipeline_create(publish_shader_rid)
    else:
        push_error("GPU Culler: Failed to create publish_shader_rid")

    # Shader d'animation Delta
    var delta_file: RDShaderFile = load("res://addons/foveacore/shaders/delta_animation.glsl")
    var delta_spirv := delta_file.get_spirv()
    var delta_err: String = delta_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if not delta_err.is_empty():
        push_error("GPU Culler: Error compiling delta_animation.glsl: " + delta_err)
    delta_shader_rid = rd.shader_create_from_spirv(delta_spirv)
    if delta_shader_rid.is_valid():
        delta_pipeline_rid = rd.compute_pipeline_create(delta_shader_rid)
    else:
        push_error("GPU Culler: Failed to create delta_shader_rid")

    # Shader d'Instance Culling
    var inst_file: RDShaderFile = load("res://addons/foveacore/shaders/instance_culling.glsl")
    var inst_spirv := inst_file.get_spirv()
    var inst_err: String = inst_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if not inst_err.is_empty():
        push_error("GPU Culler: Error compiling instance_culling.glsl: " + inst_err)
    inst_cull_shader_rid = rd.shader_create_from_spirv(inst_spirv)
    if inst_cull_shader_rid.is_valid():
        inst_cull_pipeline_rid = rd.compute_pipeline_create(inst_cull_shader_rid)
    else:
        push_error("GPU Culler: Failed to create inst_cull_shader_rid")

    # Shader d'Indirect Command Generation
    var indir_file: RDShaderFile = load("res://addons/foveacore/shaders/indirect_draw_cmd.glsl")
    var indir_spirv := indir_file.get_spirv()
    var indir_err: String = indir_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
    if not indir_err.is_empty():
        push_error("GPU Culler: Error compiling indirect_draw_cmd.glsl: " + indir_err)
    indirect_shader_rid = rd.shader_create_from_spirv(indir_spirv)
    if indirect_shader_rid.is_valid():
        indirect_pipeline_rid = rd.compute_pipeline_create(indirect_shader_rid)
    else:
        push_error("GPU Culler: Failed to create indirect_shader_rid")

## Charge le fichier via Rust et exécute le Culling sur le GPU
func process_splats_from_file(fovea_path: String, camera: Camera3D, depth_texture: RID, cull_threshold: float = 0.0,
    aabb_min: Vector3 = Vector3(-5, -5, -5), aabb_max: Vector3 = Vector3(5, 5, 5),
    render_scene_data: Object = null, hlod_distances: Array = [8.0, 18.0, 30.0],
    covar_texture: RID = RID(), palette_texture: RID = RID(), use_palette: bool = false,
    palette_size: int = 16, model_transform: Transform3D = Transform3D.IDENTITY,
    delta_buffer: RID = RID(), delta_weight: float = 0.0,
    is_static: bool = true, camera_moved: bool = true) -> RID:
    if covar_texture.is_valid():
        last_covar_texture_rid = covar_texture
    if palette_texture.is_valid():
        last_palette_texture_rid = palette_texture
    last_use_palette = use_palette
    last_palette_size = palette_size
    last_aabb_min = aabb_min
    last_aabb_max = aabb_max
    if model_transform != Transform3D.IDENTITY:
        last_model_transform = model_transform

    if not rd:
        push_error("GPU Culler: RenderingDevice is not available. Skipping culling.")
        return RID()
    if not pipeline_rid.is_valid():
        push_error("GPU Culler: Compute pipeline is not initialized (shader compile failed). Skipping culling.")
        return RID()
    
    # 1. Enregistrement de l'asset auprès du FoveaStreamingManager
    var streaming_asset: FoveaStreamingManager.StreamingAsset = streaming_manager.register_asset(fovea_path, aabb_min, aabb_max)
    if streaming_asset == null:
        push_error("FoveaEngine: Échec de l'enregistrement de l'asset de streaming.")
        return RID()
        
    # 2. Mise à jour de l'état du streaming (calcul de priorité, chargement/éviction LRU)
    streaming_manager.update_streaming(camera, chunk_load_radius)
        
    var cam_pos: Vector3 = camera.global_position
    var gaze_dir := -camera.global_transform.basis.z.normalized()
    
    # 2.5. Culling de frustum CPU par bloc spatial chargé
    var frustum: FrustumUtils.Frustum = FrustumUtils.Frustum.new()
    frustum.from_matrix(camera.get_camera_projection(), camera.global_transform)
    
    var needed_chunks: Array = []
    var needed_keys_dict: Dictionary = {}
    
    # Identifier les chunks visibles dans le rayon
    for chunk in streaming_asset.chunks:
        var slices: Array = chunk.get_meta("file_slices")
        if slices.is_empty():
            continue
            
        var dist := _distance_to_aabb(cam_pos, chunk.aabb)
        if dist <= chunk_load_radius and frustum.contains_aabb(chunk.aabb):
            var key := fovea_path + "_" + str(chunk.index)
            needed_keys_dict[key] = true
            
            # Calcul de priorité (plus proche et dans l'axe du regard = priorité haute / valeur faible)
            var to_chunk: Vector3 = (chunk.aabb.position + chunk.aabb.size * 0.5 - cam_pos).normalized()
            var gaze_align: float = gaze_dir.dot(to_chunk)
            var priority: float = dist - 5.0 * gaze_align
            
            needed_chunks.append({
                "chunk": chunk,
                "key": key,
				"dist": dist,
                "priority": priority
            })
            
    # Trier par priorité
    needed_chunks.sort_custom(func(a, b):
        return a.priority < b.priority
    )
    
    var uploads_this_frame := 0
    var delta_time := 0.016
    if render_scene_data and render_scene_data.has_method("get_delta_time"):
        delta_time = render_scene_data.get_delta_time()
    elif camera.get_viewport():
        delta_time = camera.get_process_delta_time()

    # Gérer les allocations VRAM
    var active_chunks_metadata := PackedByteArray()
    var active_chunks_count := 0
    var current_loaded_indices: Array[int] = []
    var visible_bytes := PackedByteArray()
    var total_splats: int = 0
    
    if is_static:
        if not _baked_octrees.has(fovea_path):
            var bytes := _load_fovea_bytes(fovea_path)
            var loader: Object = streaming_manager.get("loader")
            if loader == null:
                if ClassDB.can_instantiate("FoveaAssetLoader"):
                    loader = ClassDB.instantiate("FoveaAssetLoader")
            var result = FoveaOctreeBakerClass.bake_octree_from_bytes(bytes, aabb_min, aabb_max, loader)
            _baked_octrees[fovea_path] = result["root"]
            
            var sorted_bytes: PackedByteArray = result["sorted_bytes"]
            var static_buffer = rd.storage_buffer_create(sorted_bytes.size(), sorted_bytes)
            _static_input_buffers[fovea_path] = static_buffer
            
        var root = _baked_octrees[fovea_path]
        var visible_leaves: Array = []
        _cull_octree(root, frustum, visible_leaves)
        
        var max_chunks_limit: int = 256
        for leaf in visible_leaves:
            if active_chunks_count >= max_chunks_limit:
                break
            _append_chunk_metadata(active_chunks_metadata, leaf.aabb, leaf.splat_start, 1.0, leaf.splat_count)
            active_chunks_count += 1
            
        if active_chunks_count == 0:
            return RID()
            
        total_splats = active_chunks_count * 4096
        rd.buffer_update(_vram_metadata_buffer, 0, active_chunks_metadata.size(), active_chunks_metadata)
        print("FoveaEngine Baked Octree: %d visible leaves, total %d splats." % [active_chunks_count, total_splats])
    else:
        for item in needed_chunks:
            var chunk = item.chunk
            var key = item.key
            var dist = item.dist
            
            # Choix du LOD
            var target_lod := 0
            if dist >= hlod_distances[2]:
                target_lod = 3
            elif dist >= hlod_distances[1]:
                target_lod = 2
            elif dist >= hlod_distances[0]:
                target_lod = 1
                
            var slot_id := -1
            
            if _vram_allocations.has(key):
                slot_id = _vram_allocations[key]
                _vram_lru.erase(key)
                _vram_lru.append(key)
                
                # Si LOD a changé, on ré-upload si la bande passante le permet
                var current_lod = _vram_loaded_lod.get(key, -1)
                if current_lod != target_lod and uploads_this_frame < max_uploads_per_frame:
                    _upload_chunk_to_vram(rd, fovea_path, chunk, slot_id, target_lod)
                    _vram_loaded_lod[key] = target_lod
                    uploads_this_frame += 1
            else:
                if uploads_this_frame < max_uploads_per_frame:
                    # Chercher un slot libre
                    for i in range(MAX_VRAM_SLOTS - 1): # Réserver le slot 511 pour le fallback global
                        if _vram_slots_occupied[i] == "":
                            slot_id = i
                            break
                            
                    # Si plein, éviction LRU des chunks non requis ce frame
                    if slot_id == -1:
                        var evict_idx := -1
                        for i in range(_vram_lru.size()):
                            var lru_key = _vram_lru[i]
                            if not needed_keys_dict.has(lru_key):
                                evict_idx = i
                                break
                        if evict_idx != -1:
                            var lru_key = _vram_lru[evict_idx]
                            slot_id = _vram_allocations[lru_key]
                            _vram_allocations.erase(lru_key)
                            _vram_lru.remove_at(evict_idx)
                            _vram_fade_opacities.erase(lru_key)
                            _vram_loaded_lod.erase(lru_key)
                            _vram_slots_occupied[slot_id] = ""
                            
                    # Éviction absolue en dernier recours
                    if slot_id == -1 and not _vram_lru.is_empty():
                        var lru_key = _vram_lru[0]
                        slot_id = _vram_allocations[lru_key]
                        _vram_allocations.erase(lru_key)
                        _vram_lru.remove_at(0)
                        _vram_fade_opacities.erase(lru_key)
                        _vram_loaded_lod.erase(lru_key)
                        _vram_slots_occupied[slot_id] = ""
                        
                    if slot_id != -1:
                        _vram_allocations[key] = slot_id
                        _vram_slots_occupied[slot_id] = key
                        _vram_lru.append(key)
                        _vram_fade_opacities[key] = 0.0 # start fade
                        _upload_chunk_to_vram(rd, fovea_path, chunk, slot_id, target_lod)
                        _vram_loaded_lod[key] = target_lod
                        uploads_this_frame += 1
                        
            if slot_id != -1:
                current_loaded_indices.append(chunk.index)
                var fade: float = _vram_fade_opacities.get(key, 0.0)
                fade = minf(fade + delta_time * 2.0, 1.0) # fade sur 0.5s
                _vram_fade_opacities[key] = fade
                
                var splat_count := 0
                var bytes := PackedByteArray()
                match target_lod:
                    0: 
                        splat_count = chunk.raw_bytes.size() / 16
                        bytes = chunk.raw_bytes
                    1: 
                        splat_count = chunk.raw_bytes_lod1.size() / 16 if not chunk.raw_bytes_lod1.is_empty() else chunk.raw_bytes.size() / 16
                        bytes = chunk.raw_bytes_lod1 if not chunk.raw_bytes_lod1.is_empty() else chunk.raw_bytes
                    2: 
                        splat_count = chunk.raw_bytes_lod2.size() / 16 if not chunk.raw_bytes_lod2.is_empty() else chunk.raw_bytes.size() / 16
                        bytes = chunk.raw_bytes_lod2 if not chunk.raw_bytes_lod2.is_empty() else chunk.raw_bytes
                    3: 
                        splat_count = chunk.raw_bytes_lod3.size() / 16 if not chunk.raw_bytes_lod3.is_empty() else chunk.raw_bytes.size() / 16
                        bytes = chunk.raw_bytes_lod3 if not chunk.raw_bytes_lod3.is_empty() else chunk.raw_bytes
                    
                var max_chunks_limit: int = 256
                if not is_static:
                    var max_allowed_dynamic_splats: int = int(minf(max_dynamic_splats, streaming_asset.total_splats * max_dynamic_splats_ratio))
                    max_chunks_limit = clampi(ceili(float(max_allowed_dynamic_splats) / 4096.0), 1, 256)

                if splat_count > 0 and active_chunks_count < max_chunks_limit:
                    _append_chunk_metadata(active_chunks_metadata, chunk.aabb, slot_id, fade, splat_count)
                    active_chunks_count += 1
                    visible_bytes.append_array(bytes)
            else:
                # Fallback global LOD (Tâche 261)
                var bytes: PackedByteArray = chunk.raw_bytes_lod3
                var splat_count: int = bytes.size() / 16
                if splat_count > 0:
                    var fallback_slot := 511
                    var gpu_offset = fallback_slot * BLOCK_SIZE * SPLAT_BYTE_SIZE
                    rd.buffer_update(_vram_pool_buffer, gpu_offset, bytes.size(), bytes)
                    
                    var max_chunks_limit: int = 256
                    if not is_static:
                        var max_allowed_dynamic_splats: int = int(minf(max_dynamic_splats, streaming_asset.total_splats * max_dynamic_splats_ratio))
                        max_chunks_limit = clampi(ceili(float(max_allowed_dynamic_splats) / 4096.0), 1, 256)
                        
                    if active_chunks_count < max_chunks_limit:
                        _append_chunk_metadata(active_chunks_metadata, chunk.aabb, fallback_slot, 1.0, splat_count)
                        active_chunks_count += 1
                        visible_bytes.append_array(bytes)

        # Émettre les signaux
        var prev_loaded_indices = _previously_loaded_chunks.get(fovea_path, [])
        for idx in current_loaded_indices:
            if not prev_loaded_indices.has(idx):
                emit_signal("chunk_loaded", idx)
        for idx in prev_loaded_indices:
            if not current_loaded_indices.has(idx):
                emit_signal("chunk_unloaded", idx)
        _previously_loaded_chunks[fovea_path] = current_loaded_indices
        
        if active_chunks_count == 0:
            return RID()
            
        total_splats = active_chunks_count * 4096
        rd.buffer_update(_vram_metadata_buffer, 0, active_chunks_metadata.size(), active_chunks_metadata)
        print("FoveaEngine VRAM Streaming: %d chunks actifs dans la vue, total %d splats." % [active_chunks_count, total_splats])

    # 3. Caching des Buffers GPU persistants
    var max_buffer_size: int = streaming_asset.total_splats * SPLAT_BYTE_SIZE
    var cache: Dictionary = _gpu_buffers.get(fovea_path, {})
    var needs_recreation: bool = cache.is_empty() or cache.get("size", 0) < max_buffer_size
    
    if needs_recreation:
        # Libérer l'ancien cache s'il existait
        if not cache.is_empty():
            if cache.get("input", RID()).is_valid(): rd.free_rid(cache["input"])
            if cache.get("animated", RID()).is_valid(): rd.free_rid(cache["animated"])
            if cache.get("output", RID()).is_valid(): rd.free_rid(cache["output"])
            if cache.get("counter", RID()).is_valid(): rd.free_rid(cache["counter"])
            if cache.get("camera_ubo", RID()).is_valid(): rd.free_rid(cache["camera_ubo"])
            if cache.get("uniform_set", RID()).is_valid(): rd.free_rid(cache["uniform_set"])
            if cache.get("depths", RID()).is_valid(): rd.free_rid(cache["depths"])
            if cache.get("asset_data", RID()).is_valid(): rd.free_rid(cache["asset_data"])
            if cache.get("depth_uniform_set", RID()).is_valid(): rd.free_rid(cache["depth_uniform_set"])
            if cache.get("sort_uniform_set", RID()).is_valid(): rd.free_rid(cache["sort_uniform_set"])
            if cache.get("output_texture", RID()).is_valid(): rd.free_rid(cache["output_texture"])
            if cache.get("counter_texture", RID()).is_valid(): rd.free_rid(cache["counter_texture"])
            if cache.get("publish_uniform_set", RID()).is_valid(): rd.free_rid(cache["publish_uniform_set"])
        
        # Créer les nouveaux buffers persistants à la taille maximale (Task 267)
        # On sépare le pool en deux zones de buffers distincts :
        # - static_buf : Buffer de lecture seule (non modifié après chargement initial si stable)
        # - dynamic_buf/animated_buf : Buffer dynamique réécrit à chaque image pour les déformations/anim
        var input_buf: RID = rd.storage_buffer_create(max_buffer_size)
        var animated_buf: RID = rd.storage_buffer_create(max_buffer_size) # Dynamic deform buffer
        var output_buf: RID = rd.storage_buffer_create(max_buffer_size) # Static readonly output base
        var dynamic_output_buf: RID = rd.storage_buffer_create(max_buffer_size) # Dynamic output buffer
        
        var zero_counter := PackedByteArray([0,0,0,0])
        var counter_buf: RID = rd.storage_buffer_create(4, zero_counter)
        var camera_ubo_buf: RID = rd.storage_buffer_create(320)
        
        var max_splats_count: int = max_buffer_size / SPLAT_BYTE_SIZE
        var max_padded: int = 1
        while max_padded < max_splats_count:
            max_padded <<= 1
        var depths_buf: RID = rd.storage_buffer_create(max_padded * 4)
        
        var asset_bytes: PackedByteArray = PackedByteArray()
        asset_bytes.resize(32)
        asset_bytes.encode_float(0, aabb_min.x)
        asset_bytes.encode_float(4, aabb_min.y)
        asset_bytes.encode_float(8, aabb_min.z)
        asset_bytes.encode_float(12, 0.0)
        asset_bytes.encode_float(16, aabb_max.x)
        asset_bytes.encode_float(20, aabb_max.y)
        asset_bytes.encode_float(24, aabb_max.z)
        asset_bytes.encode_float(28, 0.0)
        var asset_buf: RID = rd.storage_buffer_create(32, asset_bytes)
        
        # Créer les textures GPU de destination (VRAM-to-VRAM GPU-Driven publish target)
        var tex_w: int = 1024
        var tex_h: int = ceili(float(max_splats_count) / 1024.0)
        if tex_h <= 0: tex_h = 1
        
        var out_tex_format := RDTextureFormat.new()
        out_tex_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_UINT
        out_tex_format.width = tex_w
        out_tex_format.height = tex_h
        out_tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
        var out_tex_view := RDTextureView.new()
        var output_texture: RID = rd.texture_create(out_tex_format, out_tex_view, [])
        
        var cnt_tex_format := RDTextureFormat.new()
        cnt_tex_format.format = RenderingDevice.DATA_FORMAT_R32_UINT
        cnt_tex_format.width = 1
        cnt_tex_format.height = 1
        cnt_tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
        var cnt_tex_view := RDTextureView.new()
        var counter_texture: RID = rd.texture_create(cnt_tex_format, cnt_tex_view, [])
        
        # Créer le uniform set persistant 0 (culling)
        var uniform_input: RDUniform = RDUniform.new()
        uniform_input.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        uniform_input.binding = 0
        uniform_input.add_id(_static_input_buffers[fovea_path] if is_static else _vram_pool_buffer)
        
        var uniform_output: RDUniform = RDUniform.new()
        uniform_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        uniform_output.binding = 1
        uniform_output.add_id(output_buf)
        
        var uniform_counter: RDUniform = RDUniform.new()
        uniform_counter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        uniform_counter.binding = 2
        uniform_counter.add_id(counter_buf)
        
        var uniform_active_chunks: RDUniform = RDUniform.new()
        uniform_active_chunks.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        uniform_active_chunks.binding = 3
        uniform_active_chunks.add_id(_vram_metadata_buffer)
        
        var uniform_set_0: RID = rd.uniform_set_create([uniform_input, uniform_output, uniform_counter, uniform_active_chunks], shader_rid, 0)
        
        # Uniform set pour depth_precompute.glsl (binding 0: output_buf, binding 1: depths_buf, binding 2: asset_buf, binding 3: counter_buf)
        var u_depth_splats: RDUniform = RDUniform.new()
        u_depth_splats.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_depth_splats.binding = 0
        u_depth_splats.add_id(output_buf)
        
        var u_depth_depths: RDUniform = RDUniform.new()
        u_depth_depths.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_depth_depths.binding = 1
        u_depth_depths.add_id(depths_buf)
        
        var u_depth_assets: RDUniform = RDUniform.new()
        u_depth_assets.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_depth_assets.binding = 2
        u_depth_assets.add_id(asset_buf)
 
        var u_depth_counter: RDUniform = RDUniform.new()
        u_depth_counter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_depth_counter.binding = 3
        u_depth_counter.add_id(counter_buf)
        
        var depth_uniform_set: RID = rd.uniform_set_create([u_depth_splats, u_depth_depths, u_depth_assets, u_depth_counter], depth_shader_rid, 0)
        
        # Uniform set pour sort_bitonic_keyed.glsl (binding 0: output_buf, binding 1: depths_buf)
        var u_sort_splats: RDUniform = RDUniform.new()
        u_sort_splats.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_sort_splats.binding = 0
        u_sort_splats.add_id(output_buf)
        
        var u_sort_depths: RDUniform = RDUniform.new()
        u_sort_depths.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_sort_depths.binding = 1
        u_sort_depths.add_id(depths_buf)
        
        var sort_uniform_set: RID = rd.uniform_set_create([u_sort_splats, u_sort_depths], sort_shader_rid, 0)
        
        # Uniform set pour publish_splats.glsl (binding 0: output_buf, binding 1: counter_buf, binding 2: output_texture, binding 3: counter_texture)
        var u_pub_src := RDUniform.new()
        u_pub_src.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_pub_src.binding = 0
        u_pub_src.add_id(output_buf)
        
        var u_pub_cnt := RDUniform.new()
        u_pub_cnt.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_pub_cnt.binding = 1
        u_pub_cnt.add_id(counter_buf)
        
        var u_pub_dest_tex := RDUniform.new()
        u_pub_dest_tex.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        u_pub_dest_tex.binding = 2
        u_pub_dest_tex.add_id(output_texture)
        
        var u_pub_dest_cnt := RDUniform.new()
        u_pub_dest_cnt.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        u_pub_dest_cnt.binding = 3
        u_pub_dest_cnt.add_id(counter_texture)
        
        var publish_uniform_set: RID = rd.uniform_set_create(
            [u_pub_src, u_pub_cnt, u_pub_dest_tex, u_pub_dest_cnt], publish_shader_rid, 0
        )
        
        cache = {
            "input": input_buf,
            "animated": animated_buf,
            "output": output_buf,
            "dynamic_output": dynamic_output_buf,
            "counter": counter_buf,
            "camera_ubo": camera_ubo_buf,
            "uniform_set": uniform_set_0,
            "depths": depths_buf,
            "asset_data": asset_buf,
            "depth_uniform_set": depth_uniform_set,
            "sort_uniform_set": sort_uniform_set,
            "size": max_buffer_size,
            "output_texture": output_texture,
            "counter_texture": counter_texture,
            "publish_uniform_set": publish_uniform_set
        }
        _gpu_buffers[fovea_path] = cache

    var input_buffer: RID = cache["input"]
    var output_buffer: RID = cache["output"] if is_static else cache["dynamic_output"]
    var counter_buffer: RID = cache["counter"]
    var camera_ubo: RID = cache["camera_ubo"]
    var uniform_set: RID = cache["uniform_set"]
    last_counter_buffer_rid = counter_buffer

    # Mettre à jour les buffers persistants pour cette frame
    if not is_static:
        rd.buffer_update(input_buffer, 0, visible_bytes.size(), visible_bytes)
    
    var zero_bytes := PackedByteArray([0,0,0,0])
    rd.buffer_update(counter_buffer, 0, 4, zero_bytes)
    
    # 4. Set 1, binding 0: Depth texture
    var sampler_state: RDSamplerState = RDSamplerState.new()
    sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    var sampler_rid: RID = rd.sampler_create(sampler_state)
    
    # Génération du Hi-Z buffer (une frame sur deux)
    var hiz_tex: RID = RID()
    if _frame_counter % 2 == 0 or not _last_hiz_tex.is_valid():
        hiz_tex = _generate_hiz_pyramid(depth_texture)
        _last_hiz_tex = hiz_tex
    else:
        hiz_tex = _last_hiz_tex
        
    var active_depth_tex: RID = hiz_tex if hiz_tex.is_valid() else depth_texture
 
    var uniform_depth: RDUniform = RDUniform.new()
    uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    uniform_depth.binding = 0
    uniform_depth.add_id(sampler_rid)
    uniform_depth.add_id(active_depth_tex)
    
    # 4.5. Set 1, binding 1: CameraData UBO (stereo view-projection matrices and frustum planes)
    cam_pos = camera.global_position
    
    var view_proj_left: Projection
    var view_proj_right: Projection
    
    if render_scene_data and render_scene_data.has_method("get_view_count"):
        var view_count: int = render_scene_data.get_view_count()
        if view_count > 0:
            view_proj_left = render_scene_data.get_view_projection(0)
        if view_count > 1:
            view_proj_right = render_scene_data.get_view_projection(1)
        else:
            view_proj_right = view_proj_left
    else:
        var view_matrix: Transform3D = camera.get_camera_transform().affine_inverse()
        var proj_matrix: Projection = camera.get_camera_projection()
        view_proj_left = proj_matrix * Projection(view_matrix)
        view_proj_right = view_proj_left
        
    var camera_data_bytes: PackedByteArray = PackedByteArray()
    camera_data_bytes.resize(320) # 2 x mat4 (128 bytes) + 2 x 6 x vec4 (192 bytes) = 320 bytes
    
    for col_idx in 4:
        for row_idx in 4:
            camera_data_bytes.encode_float((col_idx * 16) + (row_idx * 4), view_proj_left[col_idx][row_idx])
            camera_data_bytes.encode_float(64 + (col_idx * 16) + (row_idx * 4), view_proj_right[col_idx][row_idx])
            
    _extract_planes_to_bytes(view_proj_left, camera_data_bytes, 128)
    _extract_planes_to_bytes(view_proj_right, camera_data_bytes, 224)
    
    rd.buffer_update(camera_ubo, 0, 320, camera_data_bytes)
    var uniform_camera: RDUniform = RDUniform.new()
    uniform_camera.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_camera.binding = 1
    uniform_camera.add_id(camera_ubo)
    
    var uniform_set_depth: RID = rd.uniform_set_create([uniform_depth, uniform_camera], shader_rid, 1)
    
    # 5. Push constants matching shader Params layout
    var push_bytes: PackedByteArray = PackedByteArray()
    push_bytes.resize(56) # vec3+uint+float+float+vec3+float+vec3+float = 56 bytes
    push_bytes.encode_float(0, cam_pos.x)
    push_bytes.encode_float(4, cam_pos.y)
    push_bytes.encode_float(8, cam_pos.z)
    push_bytes.encode_u32(12, total_splats)
    push_bytes.encode_float(16, cull_threshold)
    push_bytes.encode_u32(20, active_chunks_count)
    push_bytes.encode_float(24, aabb_min.x)
    push_bytes.encode_float(28, aabb_min.y)
    push_bytes.encode_float(32, aabb_min.z)
    push_bytes.encode_float(36, 0.0) # pad1
    push_bytes.encode_float(40, aabb_max.x)
    push_bytes.encode_float(44, aabb_max.y)
    push_bytes.encode_float(48, aabb_max.z)
    push_bytes.encode_float(52, 0.0) # pad2
    
    # --- RUN DELTA ANIMATION COMPUTE SHADER PASS (Task 244) ---
    var culler_uniform_set: RID = uniform_set
    if delta_buffer.is_valid() and delta_weight > 0.0 and delta_pipeline_rid.is_valid():
        var u_in := RDUniform.new()
        u_in.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_in.binding = 0
        u_in.add_id(input_buffer)
        
        var u_delta := RDUniform.new()
        u_delta.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_delta.binding = 1
        u_delta.add_id(delta_buffer)
        
        var u_anim := RDUniform.new()
        u_anim.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_anim.binding = 2
        u_anim.add_id(cache["animated"])
        
        var delta_set := rd.uniform_set_create([u_in, u_delta, u_anim], delta_shader_rid, 0)
        
        var push_delta := PackedByteArray()
        push_delta.resize(48)
        push_delta.encode_float(0, delta_weight)
        push_delta.encode_u32(4, total_splats)
        push_delta.encode_float(8, aabb_min.x)
        push_delta.encode_float(12, aabb_min.y)
        push_delta.encode_float(16, aabb_min.z)
        push_delta.encode_float(20, 0.0)
        push_delta.encode_float(24, aabb_max.x)
        push_delta.encode_float(28, aabb_max.y)
        push_delta.encode_float(32, aabb_max.z)
        push_delta.encode_float(36, 0.0)
        
        var delta_cl := rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(delta_cl, delta_pipeline_rid)
        rd.compute_list_bind_uniform_set(delta_cl, delta_set, 0)
        rd.compute_list_set_push_constant(delta_cl, push_delta, push_delta.size())
        
        var delta_workgroups := ceili(total_splats / 256.0)
        rd.compute_list_dispatch(delta_cl, delta_workgroups, 1, 1)
        rd.compute_list_end()
        
        # Point the culler input to the newly animated buffer
        var u_cull_in := RDUniform.new()
        u_cull_in.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_cull_in.binding = 0
        u_cull_in.add_id(cache["animated"])
        
        var u_cull_out := RDUniform.new()
        u_cull_out.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_cull_out.binding = 1
        u_cull_out.add_id(output_buffer)
        
        var u_cull_cnt := RDUniform.new()
        u_cull_cnt.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_cull_cnt.binding = 2
        u_cull_cnt.add_id(counter_buffer)
        
        var u_cull_chunks := RDUniform.new()
        u_cull_chunks.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_cull_chunks.binding = 3
        u_cull_chunks.add_id(_vram_metadata_buffer)
        
        culler_uniform_set = rd.uniform_set_create([u_cull_in, u_cull_out, u_cull_cnt, u_cull_chunks], shader_rid, 0)

    # 6. Exécution du Compute Shader
    var compute_list: int = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, culler_uniform_set, 0)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set_depth, 1)
    rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
    
    var workgroups: int = ceili(total_splats / 256.0)
    rd.compute_list_dispatch(compute_list, workgroups, 1, 1)
    rd.compute_list_end()
    
    # 7. Tri temporel GPU (Phase 3 : Temporal & Interleaved Sorting)
    var padded_total: int = 1
    while padded_total < total_splats:
        padded_total <<= 1

    if skip_sync:
        # GPU-Driven Asynchrone : pas de submit/sync bloquant sur le CPU
        if total_splats > 1:
            _temporal_sort_bitonic_keyed(
                output_buffer,
                cache["depths"],
                cache["depth_uniform_set"],
                cache["sort_uniform_set"],
                total_splats,
                padded_total,
                cam_pos,
                is_static,
                camera_moved
            )
        else:
            rd.submit()
            
        # Publication GPU-driven : Copie des splats triés et du compteur vers les textures RDs
        if publish_pipeline_rid.is_valid() and cache.get("publish_uniform_set", RID()).is_valid():
            var pub_list: int = rd.compute_list_begin()
            rd.compute_list_bind_compute_pipeline(pub_list, publish_pipeline_rid)
            rd.compute_list_bind_uniform_set(pub_list, cache["publish_uniform_set"], 0)
            var pub_workgroups: int = ceili(total_splats / 256.0)
            if pub_workgroups <= 0: pub_workgroups = 1
            rd.compute_list_dispatch(pub_list, pub_workgroups, 1, 1)
            rd.compute_list_end()
            rd.submit()
    else:
        # Mode classique : regroupe les soumissions et effectue une UNIQUE synchronisation à la fin
        if total_splats > 1:
            var prev_skip_sync := skip_sync
            skip_sync = true # Désactiver temporairement pour éviter les syncs intermédiaires
            _temporal_sort_bitonic_keyed(
                output_buffer,
                cache["depths"],
                cache["depth_uniform_set"],
                cache["sort_uniform_set"],
                total_splats, # Trier sur le total (les splats culled ont une distance infinie)
                padded_total,
                cam_pos,
                is_static,
                camera_moved
            )
            skip_sync = prev_skip_sync
        
        # Soumettre tous les dispatches chaînés (Culling + Precompute + Sort) et faire l'unique sync
        rd.submit()
        rd.sync()
        
        var result_counter_bytes: PackedByteArray = rd.buffer_get_data(counter_buffer)
        var valid_splat_count: int = result_counter_bytes.decode_u32(0)
        last_valid_splat_count = valid_splat_count
        
        var culled_percentage: float = 100.0 - ((float(valid_splat_count) / total_splats) * 100.0)
        print("FoveaEngine: Compute Culling & Sort terminé. Splats restants : %d (%.1f%% supprimés)" % [valid_splat_count, culled_percentage])

    _frame_counter += 1

    # Libération du sampler et du uniform set temporaires
    rd.free_rid(sampler_rid)
    if uniform_set_depth.is_valid():
        rd.free_rid(uniform_set_depth)

    last_output_buffer_rid = output_buffer
    return output_buffer

## Tri bitonique par clés (keyed) GPU en une seule compute list non-bloquante.
## 1. Passe de précalcul des profondeurs en O(N) via depth_precompute.glsl
## 2. Passes du tri bitonique par clés via sort_bitonic_keyed.glsl
func _temporal_sort_bitonic_keyed(
        output_buffer: RID,
        depths_buffer: RID,
        depth_uniform_set: RID,
        sort_uniform_set: RID,
        splat_count: int,
        padded_count: int,
        cam_pos: Vector3,
        is_static: bool = true,
        camera_moved: bool = true
) -> void:
    if not rd:
        return
        
    # Task 266: Optimisation du Tri Bitonique
    # Si l'objet est statique et stable, et que la caméra n'a pas bougé de manière significative,
    # on évite complètement de dispatcher les compute shaders de tri de profondeur et bitonique.
    if is_static and not camera_moved:
        # Soumettre uniquement pour exécuter le culling sans retrier
        rd.submit()
        return

    # 1. Étape de précalcul des profondeurs
    var depth_pc := PackedByteArray()
    depth_pc.resize(32)
    depth_pc.encode_u32(0, padded_count) # pc.padded_count
    depth_pc.encode_float(4, cam_pos.x)
    depth_pc.encode_float(8, cam_pos.y)
    depth_pc.encode_float(12, cam_pos.z)
    depth_pc.encode_u32(16, 1) # num_assets = 1
    depth_pc.encode_u32(20, 0)
    depth_pc.encode_u32(24, 0)
    depth_pc.encode_u32(28, 0)
    
    var depth_wg := int(ceil(float(padded_count) / 256.0))
    var depth_cl := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(depth_cl, depth_pipeline_rid)
    rd.compute_list_bind_uniform_set(depth_cl, depth_uniform_set, 0)
    rd.compute_list_set_push_constant(depth_cl, depth_pc, 32)
    rd.compute_list_dispatch(depth_cl, depth_wg, 1, 1)
    rd.compute_list_end()
    
    if not skip_sync:
        rd.submit()
        rd.sync()
    
    # 2. Étape du tri bitonique par clés (Optimisé via Task 266)
    # Si l'asset est statique et stable, et que la caméra n'a pas bougé de manière majeure,
    # on court-circuite le tri de splats pour économiser du temps GPU précieux.
    var sort_workgroups: int = int(ceil(float(padded_count) / 256.0))
    var frame_mask: int = interleave_factor - 1  # 0, 1, ou 3
    var frame_id: int = _frame_counter & frame_mask
    
    # Task 266 check: If sorting is static and camera hasn't moved, we skip sorting.
    # We will pass the is_static flag to process_splats_from_file and propagate it here.


    
    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, sort_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, sort_uniform_set, 0)
    
    var stage: int = 2
    while stage <= padded_count:
        var step_size: int = stage >> 1
        while step_size > 0:
            var pc_bytes := PackedByteArray()
            pc_bytes.resize(32)
            pc_bytes.encode_u32(0, splat_count)
            pc_bytes.encode_u32(4, padded_count)
            pc_bytes.encode_u32(8, step_size)
            pc_bytes.encode_u32(12, stage)
            pc_bytes.encode_u32(16, frame_mask)
            pc_bytes.encode_u32(20, frame_id)
            pc_bytes.encode_u32(24, 0)
            pc_bytes.encode_u32(28, 0)
            
            rd.compute_list_set_push_constant(compute_list, pc_bytes, 32)
            rd.compute_list_dispatch(compute_list, sort_workgroups, 1, 1)
            
            step_size >>= 1
        stage <<= 1
    rd.compute_list_end()
    rd.submit()
    if not skip_sync:
        rd.sync()

func _load_fovea_bytes(fovea_path: String) -> PackedByteArray:
    if _cached_bytes.has(fovea_path):
        return _cached_bytes[fovea_path]

    var bytes: PackedByteArray = PackedByteArray()
    if ClassDB.can_instantiate("FoveaAssetLoader"):
        var loader: Object = ClassDB.instantiate("FoveaAssetLoader")
        if loader:
            bytes = loader.load_fast_path(fovea_path)
    if bytes.is_empty():
        if not FileAccess.file_exists(fovea_path):
            push_error("GPU Culler: File not found: " + fovea_path)
            return PackedByteArray()
        var file: FileAccess = FileAccess.open(fovea_path, FileAccess.READ)
        if not file:
            return PackedByteArray()
        var all_bytes: PackedByteArray = file.get_buffer(file.get_length())
        file.close()
        
        if all_bytes.size() >= 8 and all_bytes.slice(0, 8).get_string_from_ascii() == "FOVEA_3D":
            var version: int = all_bytes.decode_u32(8)
            var header_size: int = 72 if version >= 2 else 48
            if all_bytes.size() >= header_size:
                var color_k: int = all_bytes.decode_u32(16)
                var covar_k: int = all_bytes.decode_u32(20)
                var palette_size: int = color_k * 12
                var covar_size: int = covar_k * 32
                var splats_start: int = header_size + palette_size + covar_size
                if all_bytes.size() >= splats_start:
                    bytes = all_bytes.slice(splats_start)
        elif all_bytes.size() >= 16:
            bytes = all_bytes.slice(16)
        else:
            bytes = all_bytes
        
    if not bytes.is_empty():
        var before_size: int = bytes.size() / SPLAT_BYTE_SIZE
        if enable_cleaning:
            bytes = FoveaSplatCleaner.filter_nan_inf(bytes)
            bytes = FoveaSplatCleaner.filter_floaters(bytes, floater_neighbor_radius, floater_min_neighbors)
            if enable_decimation and decimation_target > 0:
                bytes = FoveaSplatCleaner.decimate(bytes, decimation_target)
        if enable_coplanar_merge:
            bytes = FoveaSplatCleaner.merge_coplanar(bytes, coplanar_z_bucket, 24, 1024, coplanar_min_group)
        
        var after_size: int = bytes.size() / SPLAT_BYTE_SIZE
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
        
        if hiz_pipeline_rid.is_valid():
            rd.free_rid(hiz_pipeline_rid)
            hiz_pipeline_rid = RID()
        if hiz_shader_rid.is_valid():
            rd.free_rid(hiz_shader_rid)
            hiz_shader_rid = RID()
        if hiz_texture_rid.is_valid():
            rd.free_rid(hiz_texture_rid)
            hiz_texture_rid = RID()
        _last_hiz_tex = RID()
        
        if depth_pipeline_rid.is_valid():
            rd.free_rid(depth_pipeline_rid)
            depth_pipeline_rid = RID()
        if depth_shader_rid.is_valid():
            rd.free_rid(depth_shader_rid)
            depth_shader_rid = RID()

        if raster_pipeline_rid.is_valid():
            rd.free_rid(raster_pipeline_rid)
            raster_pipeline_rid = RID()
        if raster_shader_rid.is_valid():
            rd.free_rid(raster_shader_rid)
            raster_shader_rid = RID()

        if delta_pipeline_rid.is_valid():
            rd.free_rid(delta_pipeline_rid)
            delta_pipeline_rid = RID()
        if delta_shader_rid.is_valid():
            rd.free_rid(delta_shader_rid)
            delta_shader_rid = RID()

        if inst_cull_pipeline_rid.is_valid():
            rd.free_rid(inst_cull_pipeline_rid)
            inst_cull_pipeline_rid = RID()
        if inst_cull_shader_rid.is_valid():
            rd.free_rid(inst_cull_shader_rid)
            inst_cull_shader_rid = RID()

        if indirect_pipeline_rid.is_valid():
            rd.free_rid(indirect_pipeline_rid)
            indirect_pipeline_rid = RID()
        if indirect_shader_rid.is_valid():
            rd.free_rid(indirect_shader_rid)
            indirect_shader_rid = RID()
        
        # Libérer les buffers GPU persistants en cache
        for path in _gpu_buffers:
            var cache: Dictionary = _gpu_buffers[path]
            if cache.get("input", RID()).is_valid():
                rd.free_rid(cache["input"])
            if cache.get("output", RID()).is_valid():
                rd.free_rid(cache["output"])
            if cache.get("animated", RID()).is_valid():
                rd.free_rid(cache["animated"])
            if cache.get("counter", RID()).is_valid():
                rd.free_rid(cache["counter"])
            if cache.get("camera_ubo", RID()).is_valid():
                rd.free_rid(cache["camera_ubo"])
            if cache.get("uniform_set", RID()).is_valid():
                rd.free_rid(cache["uniform_set"])
            if cache.get("depths", RID()).is_valid():
                rd.free_rid(cache["depths"])
            if cache.get("asset_data", RID()).is_valid():
                rd.free_rid(cache["asset_data"])
            if cache.get("depth_uniform_set", RID()).is_valid():
                rd.free_rid(cache["depth_uniform_set"])
            if cache.get("sort_uniform_set", RID()).is_valid():
                rd.free_rid(cache["sort_uniform_set"])
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

const FoveaSpatialChunkScript = preload("res://addons/foveacore/scripts/advanced/fovea_spatial_chunk.gd")

func _precompute_spatial_chunks(fovea_path: String, raw_bytes: PackedByteArray, aabb_min: Vector3, aabb_max: Vector3) -> Array:
    if _cached_chunks.has(fovea_path):
        return _cached_chunks[fovea_path]

    var chunks: Array = []
    chunks.resize(4096)
    
    var size_cell := (aabb_max - aabb_min) / 16.0
    for i in range(4096):
        var chunk: FoveaSpatialChunk = FoveaSpatialChunkScript.new()
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
        var chunk: FoveaSpatialChunk = chunks[i]
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

func _extract_planes_to_bytes(vp: Projection, bytes: PackedByteArray, offset: int) -> void:
    # Extract the 6 frustum planes (Left, Right, Bottom, Top, Near, Far)
    # Each plane is a vec4(normal.xyz, distance)
    
    # Left Plane
    var n_left: Vector3 = Vector3(vp.x.w + vp.x.x, vp.y.w + vp.y.x, vp.z.w + vp.z.x)
    var len_left: float = n_left.length()
    n_left = n_left / len_left
    var d_left: float = (vp.w.w + vp.w.x) / len_left
    bytes.encode_float(offset + 0, n_left.x)
    bytes.encode_float(offset + 4, n_left.y)
    bytes.encode_float(offset + 8, n_left.z)
    bytes.encode_float(offset + 12, d_left)

    # Right Plane
    var n_right: Vector3 = Vector3(vp.x.w - vp.x.x, vp.y.w - vp.y.x, vp.z.w - vp.z.x)
    var len_right: float = n_right.length()
    n_right = n_right / len_right
    var d_right: float = (vp.w.w - vp.w.x) / len_right
    bytes.encode_float(offset + 16, n_right.x)
    bytes.encode_float(offset + 20, n_right.y)
    bytes.encode_float(offset + 24, n_right.z)
    bytes.encode_float(offset + 28, d_right)

    # Bottom Plane
    var n_bottom: Vector3 = Vector3(vp.x.w + vp.x.y, vp.y.w + vp.y.y, vp.z.w + vp.z.y)
    var len_bottom: float = n_bottom.length()
    n_bottom = n_bottom / len_bottom
    var d_bottom: float = (vp.w.w + vp.w.y) / len_bottom
    bytes.encode_float(offset + 32, n_bottom.x)
    bytes.encode_float(offset + 36, n_bottom.y)
    bytes.encode_float(offset + 40, n_bottom.z)
    bytes.encode_float(offset + 44, d_bottom)

    # Top Plane
    var n_top: Vector3 = Vector3(vp.x.w - vp.x.y, vp.y.w - vp.y.y, vp.z.w - vp.z.y)
    var len_top: float = n_top.length()
    n_top = n_top / len_top
    var d_top: float = (vp.w.w - vp.w.y) / len_top
    bytes.encode_float(offset + 48, n_top.x)
    bytes.encode_float(offset + 52, n_top.y)
    bytes.encode_float(offset + 56, n_top.z)
    bytes.encode_float(offset + 60, d_top)

    # Near Plane
    var n_near: Vector3 = Vector3(vp.x.w + vp.x.z, vp.y.w + vp.y.z, vp.z.w + vp.z.z)
    var len_near: float = n_near.length()
    n_near = n_near / len_near
    var d_near: float = (vp.w.w + vp.w.z) / len_near
    bytes.encode_float(offset + 64, n_near.x)
    bytes.encode_float(offset + 68, n_near.y)
    bytes.encode_float(offset + 72, n_near.z)
    bytes.encode_float(offset + 76, d_near)

    # Far Plane
    var n_far: Vector3 = Vector3(vp.x.w - vp.x.z, vp.y.w - vp.y.z, vp.z.w - vp.z.z)
    var len_far: float = n_far.length()
    n_far = n_far / len_far
    var d_far: float = (vp.w.w - vp.w.z) / len_far
    bytes.encode_float(offset + 80, n_far.x)
    bytes.encode_float(offset + 84, n_far.y)
    bytes.encode_float(offset + 88, n_far.z)
    bytes.encode_float(offset + 92, d_far)

func _generate_hiz_pyramid(depth_texture_rid: RID) -> RID:
    if not rd or not depth_texture_rid.is_valid():
        return RID()
        
    var src_w: int = rd.texture_get_width(depth_texture_rid)
    var src_h: int = rd.texture_get_height(depth_texture_rid)
    if src_w <= 0 or src_h <= 0:
        return RID()
        
    if not hiz_texture_rid.is_valid():
        var format := RDTextureFormat.new()
        format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
        format.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
        format.width = 512
        format.height = 512
        format.depth = 1
        format.array_layers = 1
        format.mipmaps = 8
        format.usage_flags = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
        hiz_texture_rid = rd.texture_create(format, RDTextureView.new())
        if not hiz_texture_rid.is_valid():
            push_error("GPU Culler: Failed to create Hi-Z texture.")
            return RID()

    var sampler_state: RDSamplerState = RDSamplerState.new()
    sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    var sampler_rid: RID = rd.sampler_create(sampler_state)

    # --- Passe 0 : Résolution source -> Hi-Z Mip 0 (512x512) ---
    var view_dest_0 := RDTextureView.new()
    var dest_slice_0: RID = rd.texture_create_shared_from_slice(view_dest_0, hiz_texture_rid, 0, 0)
    
    var uniform_src_0: RDUniform = RDUniform.new()
    uniform_src_0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    uniform_src_0.binding = 0
    uniform_src_0.add_id(sampler_rid)
    uniform_src_0.add_id(depth_texture_rid)
    
    var uniform_dest_0: RDUniform = RDUniform.new()
    uniform_dest_0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    uniform_dest_0.binding = 1
    uniform_dest_0.add_id(dest_slice_0)
    
    var uniform_set_0: RID = rd.uniform_set_create([uniform_src_0, uniform_dest_0], hiz_shader_rid, 0)
    
    var pc_0: PackedByteArray = PackedByteArray()
    pc_0.resize(8)
    pc_0.encode_float(0, 1.0 / float(src_w))
    pc_0.encode_float(4, 1.0 / float(src_h))
    
    var compute_list: int = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, hiz_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set_0, 0)
    rd.compute_list_set_push_constant(compute_list, pc_0, pc_0.size())
    rd.compute_list_dispatch(compute_list, 32, 32, 1) # 512/16 = 32
    rd.compute_list_end()
    
    rd.free_rid(dest_slice_0)
    
    # --- Passes 1 à 7 : Downsampling successif de Mip L-1 -> Mip L ---
    for L in range(1, 8):
        var mip_src_w: int = 512 >> (L - 1)
        var mip_src_h: int = 512 >> (L - 1)
        var mip_dest_w: int = max(512 >> L, 1)
        var mip_dest_h: int = max(512 >> L, 1)
        
        var view_src_L := RDTextureView.new()
        var src_slice_L: RID = rd.texture_create_shared_from_slice(view_src_L, hiz_texture_rid, 0, L - 1)
        
        var view_dest_L := RDTextureView.new()
        var dest_slice_L: RID = rd.texture_create_shared_from_slice(view_dest_L, hiz_texture_rid, 0, L)
        
        var uniform_src_L: RDUniform = RDUniform.new()
        uniform_src_L.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        uniform_src_L.binding = 0
        uniform_src_L.add_id(sampler_rid)
        uniform_src_L.add_id(src_slice_L)
        
        var uniform_dest_L: RDUniform = RDUniform.new()
        uniform_dest_L.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        uniform_dest_L.binding = 1
        uniform_dest_L.add_id(dest_slice_L)
        
        var uniform_set_L: RID = rd.uniform_set_create([uniform_src_L, uniform_dest_L], hiz_shader_rid, 0)
        
        var pc_L: PackedByteArray = PackedByteArray()
        pc_L.resize(8)
        pc_L.encode_float(0, 1.0 / float(mip_src_w))
        pc_L.encode_float(4, 1.0 / float(mip_src_h))
        
        var compute_list_L: int = rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(compute_list_L, hiz_pipeline_rid)
        rd.compute_list_bind_uniform_set(compute_list_L, uniform_set_L, 0)
        rd.compute_list_set_push_constant(compute_list_L, pc_L, pc_L.size())
        
        var workgroups_x: int = int(ceil(float(mip_dest_w) / 16.0))
        var workgroups_y: int = int(ceil(float(mip_dest_h) / 16.0))
        rd.compute_list_dispatch(compute_list_L, workgroups_x, workgroups_y, 1)
        rd.compute_list_end()
        
        rd.free_rid(src_slice_L)
        rd.free_rid(dest_slice_L)
        
    rd.free_rid(sampler_rid)
    return hiz_texture_rid

func dispatch_tile_based_rasterization(
        output_buffer_rid: RID,
        camera: Camera3D,
        color_texture_rid: RID,
        use_palette: bool,
        palette_size: int,
        aabb_min: Vector3,
        aabb_max: Vector3,
        covar_texture_rid: RID,
        palette_texture_rid: RID,
        model_transform: Transform3D = Transform3D.IDENTITY
) -> void:
    if not rd or not output_buffer_rid.is_valid() or not color_texture_rid.is_valid() or not covar_texture_rid.is_valid():
        return
    if not raster_pipeline_rid.is_valid():
        return
        
    var viewport_w: int = rd.texture_get_width(color_texture_rid)
    var viewport_h: int = rd.texture_get_height(color_texture_rid)
    if viewport_w <= 0 or viewport_h <= 0:
        return
        
    var sampler_state := RDSamplerState.new()
    sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    var sampler_rid := rd.sampler_create(sampler_state)
    
    var u_splats := RDUniform.new()
    u_splats.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u_splats.binding = 0
    u_splats.add_id(output_buffer_rid)
    
    var u_covar := RDUniform.new()
    u_covar.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    u_covar.binding = 1
    u_covar.add_id(sampler_rid)
    u_covar.add_id(covar_texture_rid)
    
    var u_palette := RDUniform.new()
    u_palette.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    u_palette.binding = 2
    u_palette.add_id(sampler_rid)
    var final_palette_rid := palette_texture_rid if palette_texture_rid.is_valid() else covar_texture_rid
    u_palette.add_id(final_palette_rid)
    
    var u_dest := RDUniform.new()
    u_dest.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    u_dest.binding = 3
    u_dest.add_id(color_texture_rid)
    
    var u_counter := RDUniform.new()
    u_counter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u_counter.binding = 4
    u_counter.add_id(last_counter_buffer_rid)
    
    var uniform_set := rd.uniform_set_create([u_splats, u_covar, u_palette, u_dest, u_counter], raster_shader_rid, 0)
    
    var view_matrix := camera.global_transform.affine_inverse()
    var model_view_matrix := view_matrix * model_transform
    var projection_matrix := camera.get_camera_projection()
    
    var push_bytes := PackedByteArray()
    push_bytes.resize(184)
    
    for col_idx in 4:
        for row_idx in 4:
            push_bytes.encode_float((col_idx * 16) + (row_idx * 4), model_view_matrix[col_idx][row_idx])
            
    for col_idx in 4:
        for row_idx in 4:
            push_bytes.encode_float(64 + (col_idx * 16) + (row_idx * 4), projection_matrix[col_idx][row_idx])
            
    var cam_pos := camera.global_position
    push_bytes.encode_float(128, cam_pos.x)
    push_bytes.encode_float(132, cam_pos.y)
    push_bytes.encode_float(136, cam_pos.z)
    push_bytes.encode_u32(140, last_valid_splat_count)
    
    push_bytes.encode_float(144, aabb_min.x)
    push_bytes.encode_float(148, aabb_min.y)
    push_bytes.encode_float(152, aabb_min.z)
    push_bytes.encode_float(156, 0.0)
    
    push_bytes.encode_float(160, aabb_max.x)
    push_bytes.encode_float(164, aabb_max.y)
    push_bytes.encode_float(168, aabb_max.z)
    push_bytes.encode_float(172, 0.0)
    
    push_bytes.encode_u32(176, 1 if use_palette else 0)
    push_bytes.encode_u32(180, palette_size)
    
    var workgroups_x := int(ceil(float(viewport_w) / 16.0))
    var workgroups_y := int(ceil(float(viewport_h) / 16.0))
    
    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, raster_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
    rd.compute_list_dispatch(compute_list, workgroups_x, workgroups_y, 1)
    rd.compute_list_end()
    
    rd.submit()
    if not skip_sync:
        rd.sync()
        
    rd.free_rid(sampler_rid)

func dispatch_tile_based_rasterization_cached(
        camera: Camera3D,
        color_texture_rid: RID
) -> void:
    dispatch_tile_based_rasterization(
        last_output_buffer_rid,
        camera,
        color_texture_rid,
        last_use_palette,
        last_palette_size,
        last_aabb_min,
        last_aabb_max,
        last_covar_texture_rid,
        last_palette_texture_rid,
        last_model_transform
    )

func unload_asset_buffers(fovea_path: String) -> void:
    if not rd:
        return
    if _gpu_buffers.has(fovea_path):
        var cache: Dictionary = _gpu_buffers[fovea_path]
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
        if cache.get("depths", RID()).is_valid():
            rd.free_rid(cache["depths"])
        if cache.get("asset_data", RID()).is_valid():
            rd.free_rid(cache["asset_data"])
        if cache.get("depth_uniform_set", RID()).is_valid():
            rd.free_rid(cache["depth_uniform_set"])
        if cache.get("sort_uniform_set", RID()).is_valid():
            rd.free_rid(cache["sort_uniform_set"])
        if cache.get("output_texture", RID()).is_valid():
            rd.free_rid(cache["output_texture"])
        if cache.get("counter_texture", RID()).is_valid():
            rd.free_rid(cache["counter_texture"])
        if cache.get("publish_uniform_set", RID()).is_valid():
            rd.free_rid(cache["publish_uniform_set"])
        _gpu_buffers.erase(fovea_path)
        print("FoveaEngine: Unloaded GPU culler buffers for asset: %s" % fovea_path)

func _upload_chunk_to_vram(rendering_device: RenderingDevice, fovea_path: String, chunk: Object, slot_id: int, lod_level: int) -> void:
    var bytes := PackedByteArray()
    match lod_level:
        0: bytes = chunk.raw_bytes
        1: bytes = chunk.raw_bytes_lod1 if not chunk.raw_bytes_lod1.is_empty() else chunk.raw_bytes
        2: bytes = chunk.raw_bytes_lod2 if not chunk.raw_bytes_lod2.is_empty() else chunk.raw_bytes
        3: bytes = chunk.raw_bytes_lod3 if not chunk.raw_bytes_lod3.is_empty() else chunk.raw_bytes
        
    if bytes.is_empty() and not chunk.is_loaded:
        var slices: Array = chunk.get_meta("file_slices")
        if not slices.is_empty():
            var file_offset = slices[0].offset
            var file_size = slices[0].size
            var gpu_offset = slot_id * BLOCK_SIZE * SPLAT_BYTE_SIZE
            # Charger directement du disque en VRAM via le loader GDExtension Rust (Asynchrone / DirectStorage)
            streaming_manager.loader.upload_file_slice_to_gpu_buffer_async(
                rendering_device, fovea_path, file_offset, file_size, _vram_pool_buffer, gpu_offset
            )
            return
            
    if not bytes.is_empty():
        var gpu_offset = slot_id * BLOCK_SIZE * SPLAT_BYTE_SIZE
        rendering_device.buffer_update(_vram_pool_buffer, gpu_offset, bytes.size(), bytes)

func _append_chunk_metadata(metadata: PackedByteArray, aabb: AABB, slot_id: int, fade: float, splat_count: int) -> void:
    var base_offset = metadata.size()
    metadata.resize(base_offset + 48)
    metadata.encode_float(base_offset, aabb.position.x)
    metadata.encode_float(base_offset + 4, aabb.position.y)
    metadata.encode_float(base_offset + 8, aabb.position.z)
    metadata.encode_float(base_offset + 12, float(slot_id))
    
    metadata.encode_float(base_offset + 16, aabb.end.x)
    metadata.encode_float(base_offset + 20, aabb.end.y)
    metadata.encode_float(base_offset + 24, aabb.end.z)
    metadata.encode_float(base_offset + 28, fade)
    
    metadata.encode_u32(base_offset + 32, splat_count)
    metadata.encode_u32(base_offset + 36, 0)
    metadata.encode_u32(base_offset + 40, 0)
    metadata.encode_u32(base_offset + 44, 0)

func process_gpu_instance_culling(transforms_buffer: RID, aabb_min: Vector3, aabb_max: Vector3, camera: Camera3D, total_instances: int) -> Dictionary:
    if not rd or not inst_cull_pipeline_rid.is_valid():
        return {}
        
    var visible_indices_buffer := rd.storage_buffer_create(total_instances * 4)
    var visible_counter_bytes := PackedByteArray([0,0,0,0])
    var visible_counter_buffer := rd.storage_buffer_create(4, visible_counter_bytes)
    
    var u_trans := RDUniform.new()
    u_trans.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u_trans.binding = 0
    u_trans.add_id(transforms_buffer)
    
    var u_vis_idx := RDUniform.new()
    u_vis_idx.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u_vis_idx.binding = 1
    u_vis_idx.add_id(visible_indices_buffer)
    
    var u_vis_cnt := RDUniform.new()
    u_vis_cnt.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u_vis_cnt.binding = 2
    u_vis_cnt.add_id(visible_counter_buffer)
    
    var uniform_set := rd.uniform_set_create([u_trans, u_vis_idx, u_vis_cnt], inst_cull_shader_rid, 0)
    
    # Extract frustum planes
    var view_proj: Projection
    var view_matrix: Transform3D = camera.get_camera_transform().affine_inverse()
    var proj_matrix: Projection = camera.get_camera_projection()
    view_proj = proj_matrix * Projection(view_matrix)
    
    var push_bytes := PackedByteArray()
    push_bytes.resize(128)
    _extract_planes_to_bytes(view_proj, push_bytes, 0)
    
    push_bytes.encode_float(96, aabb_min.x)
    push_bytes.encode_float(100, aabb_min.y)
    push_bytes.encode_float(104, aabb_min.z)
    push_bytes.encode_u32(108, total_instances)
    
    push_bytes.encode_float(112, aabb_max.x)
    push_bytes.encode_float(116, aabb_max.y)
    push_bytes.encode_float(120, aabb_max.z)
    push_bytes.encode_u32(124, 0)
    
    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, inst_cull_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
    
    var workgroups := ceili(float(total_instances) / 256.0)
    rd.compute_list_dispatch(compute_list, workgroups, 1, 1)
    rd.compute_list_end()
    
    return {
        "indices_buffer": visible_indices_buffer,
        "counter_buffer": visible_counter_buffer,
        "uniform_set": uniform_set
    }

func generate_indirect_draw_command(counter_buffer: RID, count_per_splat: int, is_indexed: bool) -> RID:
    if not rd or not indirect_pipeline_rid.is_valid():
        return RID()
        
    var size := 20 if is_indexed else 16
    var draw_indirect_buffer := rd.storage_buffer_create(size)
    
    var u_cnt := RDUniform.new()
    u_cnt.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u_cnt.binding = 0
    u_cnt.add_id(counter_buffer)
    
    var u_args := RDUniform.new()
    u_args.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    u_args.binding = 1
    u_args.add_id(draw_indirect_buffer)
    
    var uniform_set := rd.uniform_set_create([u_cnt, u_args], indirect_shader_rid, 0)
    
    var push_bytes := PackedByteArray()
    push_bytes.resize(8)
    push_bytes.encode_u32(0, count_per_splat)
    push_bytes.encode_u32(4, 1 if is_indexed else 0)
    
    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, indirect_pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
    rd.compute_list_dispatch(compute_list, 1, 1, 1)
    rd.compute_list_end()
    
    # Transition buffer via GPU barrier for safe draw reading
    rd.barrier()
    
    # Free temporary uniform set
    rd.free_rid(uniform_set)
    
    return draw_indirect_buffer

func _cull_octree(node: RefCounted, frustum: Object, visible_leaves: Array) -> void:
    if node == null:
        return
    if not frustum.contains_aabb(node.aabb):
        return
    if node.is_leaf:
        if node.splat_count > 0:
            visible_leaves.append(node)
    else:
        for child in node.children:
            _cull_octree(child, frustum, visible_leaves)