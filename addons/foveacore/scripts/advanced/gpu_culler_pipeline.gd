class_name GPUCullerPipeline
extends RefCounted

## FoveaEngine : Pipeline de Compute Shader pour le Backface Culling
## VERSION TRIANGLE - Optimisé pour le rendu par maillage triangulaire
## Les splats sont maintenant des triangles réels, plus de quad avec discard par fragment

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var sort_shader_rid: RID
var sort_pipeline_rid: RID

const SPLAT_BYTE_SIZE = 16 # Format Fast-Path (FoveaPackedSplat)

func _init():
    rd = RenderingServer.create_local_rendering_device()
    _load_compute_shader()

func _load_compute_shader():
    var shader_file = load("res://addons/foveacore/shaders/gpu_culling_compute.glsl")
    var spirv = shader_file.get_spirv()
    shader_rid = rd.shader_create_from_spirv(spirv)
    pipeline_rid = rd.compute_pipeline_create(shader_rid)
    
    var sort_file = load("res://addons/foveacore/shaders/sort_compute.glsl")
    sort_shader_rid = rd.shader_create_from_spirv(sort_file.get_spirv())
    sort_pipeline_rid = rd.compute_pipeline_create(sort_shader_rid)

## Charge le fichier via Rust et exécute le Culling sur le GPU
func process_splats_from_file(fovea_path: String, camera: Camera3D, depth_texture: RID, cull_threshold: float = 0.0,
    aabb_min: Vector3 = Vector3(-5, -5, -5), aabb_max: Vector3 = Vector3(5, 5, 5)) -> RID:
    # 1. Chargement des octets bruts (via GDExtension si disponible, sinon fallback GDScript)
    var raw_bytes: PackedByteArray = _load_fovea_bytes(fovea_path)
    if raw_bytes.is_empty():
        push_error("FoveaEngine: Échec du chargement du fichier Fast-Path.")
        return RID()
        
    var total_splats = raw_bytes.size() / SPLAT_BYTE_SIZE
    print("FoveaEngine: Dispatching Compute Shader pour %d splats..." % total_splats)

    # 2. Création des Buffers GPU
    var input_buffer = rd.storage_buffer_create(raw_bytes.size(), raw_bytes)
    var output_buffer = rd.storage_buffer_create(raw_bytes.size())
    
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
    
    # 7. TRI BITONIQUE SUR LE GPU
    if valid_splat_count > 1:
        var next_power_of_two = 1
        while next_power_of_two < valid_splat_count:
            next_power_of_two <<= 1
            
        var sort_uniform = RDUniform.new()
        sort_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        sort_uniform.binding = 0
        sort_uniform.add_id(output_buffer)
        var sort_uniform_set = rd.uniform_set_create([sort_uniform], sort_shader_rid, 0)
        
        var sort_workgroups = ceil(float(next_power_of_two) / 256.0)
        
        var stage = 2
        while stage <= next_power_of_two:
            var step_size = stage >> 1
            while step_size > 0:
                var pc_bytes = PackedByteArray()
                pc_bytes.resize(28)
                pc_bytes.encode_u32(0, step_size)
                pc_bytes.encode_u32(4, stage)
                pc_bytes.encode_u32(8, valid_splat_count)
                pc_bytes.encode_float(12, 0.0)
                pc_bytes.encode_float(16, cam_pos.x)
                pc_bytes.encode_float(20, cam_pos.y)
                pc_bytes.encode_float(24, cam_pos.z)
                
                var sort_list = rd.compute_list_begin()
                rd.compute_list_bind_compute_pipeline(sort_list, sort_pipeline_rid)
                rd.compute_list_bind_uniform_set(sort_list, sort_uniform_set, 0)
                rd.compute_list_set_push_constant(sort_list, pc_bytes, 28)
                rd.compute_list_dispatch(sort_list, sort_workgroups, 1, 1)
                rd.compute_list_end()
                rd.submit()
                
                step_size >>= 1
            stage <<= 1
        
        rd.sync()
        print("FoveaEngine: GPU Bitonic Sort terminé.")
    
    # Libération
    rd.free_rid(input_buffer)
    rd.free_rid(counter_buffer)
    
    return output_buffer

func _load_fovea_bytes(fovea_path: String) -> PackedByteArray:
    if ClassDB.can_instantiate("FoveaAssetLoader"):
        var loader = ClassDB.instantiate("FoveaAssetLoader")
        if loader:
            return loader.load_fast_path(fovea_path)
    if not FileAccess.file_exists(fovea_path):
        push_error("GPU Culler: File not found: " + fovea_path)
        return PackedByteArray()
    var file = FileAccess.open(fovea_path, FileAccess.READ)
    if not file:
        return PackedByteArray()
    var bytes = file.get_buffer(file.get_length())
    file.close()
    return bytes

func cleanup():
    if rd:
        rd.free()