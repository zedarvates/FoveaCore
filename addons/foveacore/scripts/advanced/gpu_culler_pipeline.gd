class_name GPUCullerPipeline
extends RefCounted

## FoveaEngine : Pipeline de Compute Shader pour le Backface Culling + Tri Bitonique
## VERSION TRIANGLE - Optimise pour le rendu par maillage triangulaire
## Phase 3 : Temporal & Interleaved Sorting - tri non-bloquant sur plusieurs frames

class BlockData:
    var start_index: int
    var end_index: int
    var aabb: AABB

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var sort_shader_rid: RID
var sort_pipeline_rid: RID

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
    # 1. Chargement des octets bruts (via GDExtension si disponible, sinon fallback GDScript)
    var raw_bytes: PackedByteArray = _load_fovea_bytes(fovea_path)
    if raw_bytes.is_empty():
        push_error("FoveaEngine: Échec du chargement du fichier Fast-Path.")
        return RID()
        
    # 1.5. Culling de frustum CPU par bloc spatial (Phase 3: Spatial Chunking)
    # Puisque les splats sont ordonnés par code de Morton, les blocs consécutifs de 4096
    # splats sont très compacts spatialement. On peut éliminer les blocs hors frustum
    # sur le CPU pour éviter d'uploader et de traiter des millions de points sur le GPU.
    var blocks := _precompute_blocks(fovea_path, raw_bytes, aabb_min, aabb_max)
    var frustum = FrustumUtils.Frustum.new()
    frustum.from_matrix(camera.get_camera_projection(), camera.global_transform)
    
    var visible_blocks: Array[BlockData] = []
    for block in blocks:
        if frustum.contains_aabb(block.aabb):
            visible_blocks.append(block)
            
    var culled_blocks_count := blocks.size() - visible_blocks.size()
    if culled_blocks_count > 0:
        print("FoveaEngine: CPU Frustum Culling: %d/%d blocs rejetes." % [culled_blocks_count, blocks.size()])
        
    if visible_blocks.is_empty():
        print("FoveaEngine: Aucun bloc visible sur le CPU, skip complet GPU.")
        return RID()
        
    var visible_bytes := PackedByteArray()
    for block in visible_blocks:
        var size := (block.end_index - block.start_index) * SPLAT_BYTE_SIZE
        var src_offset := block.start_index * SPLAT_BYTE_SIZE
        var block_slice = raw_bytes.slice(src_offset, src_offset + size)
        visible_bytes.append_array(block_slice)
        
    var total_splats = visible_bytes.size() / SPLAT_BYTE_SIZE
    print("FoveaEngine: Dispatching Compute Shader pour %d splats visibles..." % total_splats)

    # 2. Création des Buffers GPU
    var input_buffer = rd.storage_buffer_create(visible_bytes.size(), visible_bytes)
    var output_buffer = rd.storage_buffer_create(visible_bytes.size())
    
    var counter_bytes = PackedByteArray()
    counter_bytes.resize(4) 
    var counter_buffer = rd.storage_buffer_create(4, counter_bytes)

    # 3. Set 0: Buffers (input, output, counter)
    var uniform_input = RDUniform.new()
    uniform_input.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_input.binding = 0
    uniform_input.add_id(input_buffer)
    
    var uniform_output = RDUniform.new()
    uniform_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_output.binding = 1
    uniform_output.add_id(output_buffer)
    
    var uniform_counter = RDUniform.new()
    uniform_counter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_counter.binding = 2
    uniform_counter.add_id(counter_buffer)
    
    var uniform_set = rd.uniform_set_create([uniform_input, uniform_output, uniform_counter], shader_rid, 0)
    
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
    var cam_pos = camera.global_position
    var view_matrix = camera.get_camera_transform().affine_inverse()
    var proj_matrix = camera.get_camera_projection()
    var view_proj = proj_matrix * view_matrix
    
    var camera_data_bytes = PackedByteArray()
    camera_data_bytes.resize(128) # 2 x mat4 (std140)
    var vp_data = view_proj
    for row in 4:
        for col in 4:
            camera_data_bytes.encode_float((row * 16) + (col * 4), vp_data[row][col])
    # Copy same matrix for right eye (single-view fallback)
    for row in 4:
        for col in 4:
            camera_data_bytes.encode_float(64 + (row * 16) + (col * 4), vp_data[row][col])
    
    var camera_ubo = rd.storage_buffer_create(128, camera_data_bytes)
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

    # Liberation (input et counter, output_buffer reste valide pour le renderer)
    rd.free_rid(input_buffer)
    rd.free_rid(counter_buffer)

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
        bytes = file.get_buffer(file.get_length())
        file.close()
        
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

func cleanup():
    if rd:
        rd.free()