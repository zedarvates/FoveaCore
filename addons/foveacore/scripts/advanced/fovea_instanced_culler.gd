class_name FoveaInstancedCuller
extends RefCounted

const FoveaDeltaManager := preload("res://addons/foveacore/scripts/advanced/fovea_delta_manager.gd")

# FoveaEngine : Pipeline de Compute Shader pour le Culling d'Instances de Splats
# Phase 3 : Global Splat Instancing

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID

var inst_cull_shader_rid: RID
var inst_cull_pipeline_rid: RID
var indirect_shader_rid: RID
var indirect_pipeline_rid: RID
var publish_shader_rid: RID
var publish_pipeline_rid: RID

# Persistent VRAM Cache for GPU-driven rendering
var cached_output_texture: RID
var cached_counter_texture: RID
var cached_max_splat_count: int = 0

const SPLAT_BYTE_SIZE: int = 16
const OUTPUT_SPLAT_BYTE_SIZE: int = 20

func _init() -> void:
    rd = RenderingServer.create_local_rendering_device()
    if rd:
        _load_compute_shader()
    else:
        push_warning("FoveaInstancedCuller: local rendering device not available.")

func _load_compute_shader() -> void:
    if not rd:
        return
    var shader_file: RDShaderFile = preload("res://addons/foveacore/shaders/gpu_culling_instanced.glsl")
    var spirv: RDShaderSPIRV = shader_file.get_spirv()
    shader_rid    = rd.shader_create_from_spirv(spirv)
    if shader_rid.is_valid():
        pipeline_rid  = rd.compute_pipeline_create(shader_rid)

    # 1. Compile instance_culling.glsl
    var inst_file: RDShaderFile = load("res://addons/foveacore/shaders/instance_culling.glsl")
    var inst_spirv := inst_file.get_spirv()
    inst_cull_shader_rid = rd.shader_create_from_spirv(inst_spirv)
    if inst_cull_shader_rid.is_valid():
        inst_cull_pipeline_rid = rd.compute_pipeline_create(inst_cull_shader_rid)

    # 2. Compile indirect_draw_cmd.glsl
    var indir_file: RDShaderFile = load("res://addons/foveacore/shaders/indirect_draw_cmd.glsl")
    var indir_spirv := indir_file.get_spirv()
    indirect_shader_rid = rd.shader_create_from_spirv(indir_spirv)
    if indirect_shader_rid.is_valid():
        indirect_pipeline_rid = rd.compute_pipeline_create(indirect_shader_rid)

    # 3. Compile publish_splats.glsl
    var pub_file: RDShaderFile = load("res://addons/foveacore/shaders/publish_splats.glsl")
    var pub_spirv := pub_file.get_spirv()
    publish_shader_rid = rd.shader_create_from_spirv(pub_spirv)
    if publish_shader_rid.is_valid():
        publish_pipeline_rid = rd.compute_pipeline_create(publish_shader_rid)

## Culls instances of a splat asset on the GPU
## Returns Dictionary { "buffer_rid": RID, "count": int, "active_instance_indices": Array }
func process_instanced_splats(
    raw_bytes: PackedByteArray,
    instance_transforms: Array[Transform3D],
    camera: Camera3D,
    depth_texture: RID,
    cull_threshold: float = 0.0,
    aabb_min: Vector3 = Vector3(-5, -5, -5),
    aabb_max: Vector3 = Vector3(5, 5, 5),
    active_delta_positions: Array[Dictionary] = [],
    active_delta_colors: Array[Dictionary] = [],
    active_morph_types: Array[int] = [],
    active_morph_weights: Array[float] = [],
    active_morph_frequencies: Array[float] = [],
    active_morph_amplitudes: Array[float] = []
) -> Dictionary:
    return process_instanced_splats_ext(
        raw_bytes,
        instance_transforms,
        camera,
        depth_texture,
        cull_threshold,
        aabb_min,
        aabb_max,
        active_delta_positions,
        active_delta_colors,
        active_morph_types,
        active_morph_weights,
        active_morph_frequencies,
        active_morph_amplitudes,
        false,
        false
    )

## Extended method supporting skip_sync and GPU-driven instance culling
func process_instanced_splats_ext(
    raw_bytes: PackedByteArray,
    instance_transforms: Array[Transform3D],
    camera: Camera3D,
    depth_texture: RID,
    cull_threshold: float = 0.0,
    aabb_min: Vector3 = Vector3(-5, -5, -5),
    aabb_max: Vector3 = Vector3(5, 5, 5),
    active_delta_positions: Array[Dictionary] = [],
    active_delta_colors: Array[Dictionary] = [],
    active_morph_types: Array[int] = [],
    active_morph_weights: Array[float] = [],
    active_morph_frequencies: Array[float] = [],
    active_morph_amplitudes: Array[float] = [],
    skip_sync: bool = false,
    use_gpu_instance_culling: bool = false
) -> Dictionary:
    if raw_bytes.is_empty() or instance_transforms.is_empty() or not rd:
        return { "buffer_rid": RID(), "count": 0, "active_instance_indices": [], "indirect_draw_buffer": RID() }

    var asset_splat_count: int = raw_bytes.size() / SPLAT_BYTE_SIZE
    var active_instances_count: int = instance_transforms.size()
    var active_instance_indices: Array = []
    
    var transforms_bytes: PackedByteArray
    var visible_indices_buffer: RID
    var visible_counter_buffer: RID
    var inst_cull_uniform_set: RID
    
    if use_gpu_instance_culling and inst_cull_pipeline_rid.is_valid():
        # GPU Instance Frustum Culling Pass
        transforms_bytes = serialize_transforms(instance_transforms)
        var transforms_buffer := rd.storage_buffer_create(transforms_bytes.size(), transforms_bytes)
        
        visible_indices_buffer = rd.storage_buffer_create(active_instances_count * 4)
        var zero_cnt := PackedByteArray([0,0,0,0])
        visible_counter_buffer = rd.storage_buffer_create(4, zero_cnt)
        
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
        
        inst_cull_uniform_set = rd.uniform_set_create([u_trans, u_vis_idx, u_vis_cnt], inst_cull_shader_rid, 0)
        
        var view_proj: Projection
        var view_matrix: Transform3D = camera.get_camera_transform().affine_inverse()
        var proj_matrix: Projection = camera.get_camera_projection()
        view_proj = proj_matrix * Projection(view_matrix)
        
        var push_bytes_ic := PackedByteArray()
        push_bytes_ic.resize(128)
        _extract_planes_to_bytes(view_proj, push_bytes_ic, 0)
        
        push_bytes_ic.encode_float(96, aabb_min.x)
        push_bytes_ic.encode_float(100, aabb_min.y)
        push_bytes_ic.encode_float(104, aabb_min.z)
        push_bytes_ic.encode_u32(108, active_instances_count)
        
        push_bytes_ic.encode_float(112, aabb_max.x)
        push_bytes_ic.encode_float(116, aabb_max.y)
        push_bytes_ic.encode_float(120, aabb_max.z)
        push_bytes_ic.encode_u32(124, 0)
        
        var ic_compute_list := rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(ic_compute_list, inst_cull_pipeline_rid)
        rd.compute_list_bind_uniform_set(ic_compute_list, inst_cull_uniform_set, 0)
        rd.compute_list_set_push_constant(ic_compute_list, push_bytes_ic, push_bytes_ic.size())
        
        var ic_workgroups := ceili(float(active_instances_count) / 256.0)
        rd.compute_list_dispatch(ic_compute_list, ic_workgroups, 1, 1)
        rd.compute_list_end()
        
        # Safe memory barrier transition for follow-up compute shader reads
        rd.barrier()
        
        # Cleanup inst_cull intermediate RIDs
        rd.free_rid(transforms_buffer)
        rd.free_rid(inst_cull_uniform_set)
    else:
        # Fallback to CPU-based instance culling
        var frustum: FrustumUtils.Frustum = FrustumUtils.Frustum.new()
        frustum.from_matrix(camera.get_camera_projection(), camera.global_transform)
        var local_aabb: AABB = AABB(aabb_min, aabb_max - aabb_min).grow(0.1)
        var active_transforms: Array[Transform3D] = []
        for i in range(instance_transforms.size()):
            var xf: Transform3D = instance_transforms[i]
            var world_aabb: AABB = xf * local_aabb
            if frustum.contains_aabb(world_aabb):
                active_transforms.append(xf)
                active_instance_indices.append(i)
        
        if active_transforms.is_empty():
            return { "buffer_rid": RID(), "count": 0, "active_instance_indices": [], "indirect_draw_buffer": RID() }
            
        active_instances_count = active_transforms.size()
        transforms_bytes = serialize_transforms(active_transforms)

    # Pack overrides (Sparse Delta Splats)
    var filtered_delta_positions: Array[Dictionary] = []
    var filtered_delta_colors: Array[Dictionary] = []
    var filtered_morph_types: Array[int] = []
    var filtered_morph_weights: Array[float] = []
    var filtered_morph_frequencies: Array[float] = []
    var filtered_morph_amplitudes: Array[float] = []
    
    for i in range(instance_transforms.size()):
        if not use_gpu_instance_culling and not active_instance_indices.has(i):
            continue
        filtered_delta_positions.append(active_delta_positions[i] if i < active_delta_positions.size() else {})
        filtered_delta_colors.append(active_delta_colors[i] if i < active_delta_colors.size() else {})
        filtered_morph_types.append(active_morph_types[i] if i < active_morph_types.size() else 0)
        filtered_morph_weights.append(active_morph_weights[i] if i < active_morph_weights.size() else 0.0)
        filtered_morph_frequencies.append(active_morph_frequencies[i] if i < active_morph_frequencies.size() else 1.0)
        filtered_morph_amplitudes.append(active_morph_amplitudes[i] if i < active_morph_amplitudes.size() else 0.5)

    var params_bytes := PackedByteArray()
    params_bytes.resize(filtered_morph_types.size() * 16)
    for i in range(filtered_morph_types.size()):
        var base := i * 16
        params_bytes.encode_u32(base, filtered_morph_types[i])
        params_bytes.encode_float(base + 4, filtered_morph_weights[i])
        params_bytes.encode_float(base + 8, filtered_morph_frequencies[i])
        params_bytes.encode_float(base + 12, filtered_morph_amplitudes[i])

    var packed_deltas := FoveaDeltaManager.pack_gpu_deltas(filtered_delta_positions, filtered_delta_colors)
    var offsets_bytes: PackedByteArray = packed_deltas.offsets_bytes
    var deltas_bytes: PackedByteArray = packed_deltas.deltas_bytes

    # Create Buffers for the primary compute pass
    var input_buffer := rd.storage_buffer_create(raw_bytes.size(), raw_bytes)
    var transforms_buffer := rd.storage_buffer_create(transforms_bytes.size(), transforms_bytes)
    var params_buffer := rd.storage_buffer_create(params_bytes.size(), params_bytes)
    var offsets_buffer := rd.storage_buffer_create(offsets_bytes.size(), offsets_bytes)
    var deltas_buffer := rd.storage_buffer_create(deltas_bytes.size(), deltas_bytes)
    
    var max_output_splat_count := instance_transforms.size() * asset_splat_count if use_gpu_instance_culling else active_instances_count * asset_splat_count
    var output_buffer := rd.storage_buffer_create(max_output_splat_count * OUTPUT_SPLAT_BYTE_SIZE)
    
    var zero_counter := PackedByteArray([0,0,0,0])
    var counter_buffer := rd.storage_buffer_create(4, zero_counter)

    # Setup uniforms
    var uniform_input := RDUniform.new()
    uniform_input.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_input.binding = 0
    uniform_input.add_id(input_buffer)

    var uniform_transforms := RDUniform.new()
    uniform_transforms.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_transforms.binding = 1
    uniform_transforms.add_id(transforms_buffer)

    var uniform_output := RDUniform.new()
    uniform_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_output.binding = 2
    uniform_output.add_id(output_buffer)

    var uniform_counter := RDUniform.new()
    uniform_counter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_counter.binding = 3
    uniform_counter.add_id(counter_buffer)

    var uniform_deltas := RDUniform.new()
    uniform_deltas.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_deltas.binding = 4
    uniform_deltas.add_id(deltas_buffer)

    var uniform_delta_offsets := RDUniform.new()
    uniform_delta_offsets.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_delta_offsets.binding = 5
    uniform_delta_offsets.add_id(offsets_buffer)

    var uniform_params := RDUniform.new()
    uniform_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_params.binding = 6
    uniform_params.add_id(params_buffer)

    # Bindings 7 & 8 for GPU instance culling
    var u_vis_idx_dummy: RID
    var u_vis_cnt_dummy: RID
    
    if use_gpu_instance_culling:
        u_vis_idx_dummy = visible_indices_buffer
        u_vis_cnt_dummy = visible_counter_buffer
    else:
        var dummy_data := PackedByteArray([0,0,0,0])
        u_vis_idx_dummy = rd.storage_buffer_create(4, dummy_data)
        u_vis_cnt_dummy = rd.storage_buffer_create(4, dummy_data)
        
    var uniform_vis_idx := RDUniform.new()
    uniform_vis_idx.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_vis_idx.binding = 7
    uniform_vis_idx.add_id(u_vis_idx_dummy)
    
    var uniform_vis_cnt := RDUniform.new()
    uniform_vis_cnt.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_vis_cnt.binding = 8
    uniform_vis_cnt.add_id(u_vis_cnt_dummy)

    var uniform_set := rd.uniform_set_create(
        [
            uniform_input, uniform_transforms, uniform_output, uniform_counter,
            uniform_deltas, uniform_delta_offsets, uniform_params,
            uniform_vis_idx, uniform_vis_cnt
        ],
        shader_rid, 0
    )

    # Depth map + Camera Uniforms
    var sampler_state := RDSamplerState.new()
    sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    var sampler_rid := rd.sampler_create(sampler_state)

    var actual_depth_tex := depth_texture
    var dummy_tex: RID
    if not actual_depth_tex.is_valid():
        dummy_tex = _create_dummy_depth_texture()
        actual_depth_tex = dummy_tex

    var uniform_depth := RDUniform.new()
    uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    uniform_depth.binding = 0
    uniform_depth.add_id(sampler_rid)
    uniform_depth.add_id(actual_depth_tex)

    var cam_pos := camera.global_position
    var view_matrix := camera.get_camera_transform().affine_inverse()
    var proj_matrix := camera.get_camera_projection()
    var view_proj := proj_matrix * Projection(view_matrix)

    var camera_data_bytes := PackedByteArray()
    camera_data_bytes.resize(128)
    for col_idx in 4:
        for row_idx in 4:
            camera_data_bytes.encode_float((col_idx * 16) + (row_idx * 4), view_proj[col_idx][row_idx])
            camera_data_bytes.encode_float(64 + (col_idx * 16) + (row_idx * 4), view_proj[col_idx][row_idx])

    var camera_ubo := rd.storage_buffer_create(128, camera_data_bytes)
    var uniform_camera := RDUniform.new()
    uniform_camera.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_camera.binding = 1
    uniform_camera.add_id(camera_ubo)

    var uniform_set_depth := rd.uniform_set_create([uniform_depth, uniform_camera], shader_rid, 1)

    # Push constants: 56 bytes
    var push_bytes := PackedByteArray()
    push_bytes.resize(56)
    push_bytes.encode_float(0, cam_pos.x)
    push_bytes.encode_float(4, cam_pos.y)
    push_bytes.encode_float(8, cam_pos.z)
    push_bytes.encode_u32(12, asset_splat_count)
    push_bytes.encode_u32(16, active_instances_count)
    push_bytes.encode_float(20, cull_threshold)
    push_bytes.encode_float(24, aabb_min.x)
    push_bytes.encode_float(28, aabb_min.y)
    push_bytes.encode_float(32, aabb_min.z)
    push_bytes.encode_u32(36, 1 if use_gpu_instance_culling else 0)
    push_bytes.encode_float(40, aabb_max.x)
    push_bytes.encode_float(44, aabb_max.y)
    push_bytes.encode_float(48, aabb_max.z)
    push_bytes.encode_float(52, 0.0)

    var total_threads := asset_splat_count * active_instances_count
    var workgroups := ceili(float(total_threads) / 256.0)

    var compute_list := rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set_depth, 1)
    rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
    rd.compute_list_dispatch(compute_list, workgroups, 1, 1)
    rd.compute_list_end()

    # Memory transition barrier for subsequent reads/publishes
    rd.barrier()

    var indirect_draw_buffer: RID = RID()
    var valid_splat_count := 0

    if skip_sync:
        # GPU-Driven Asynchronous Pipeline (No rd.sync() stalls)
        var total_splats := max_output_splat_count
        if cached_max_splat_count != total_splats or not cached_output_texture.is_valid():
            _recreate_gpu_driven_textures(total_splats)
            
        var u_pub_src := RDUniform.new()
        u_pub_src.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_pub_src.binding = 0
        u_pub_src.add_id(output_buffer)
        
        var u_pub_cnt := RDUniform.new()
        u_pub_cnt.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
        u_pub_cnt.binding = 1
        u_pub_cnt.add_id(counter_buffer)
        
        var u_pub_dest_tex := RDUniform.new()
        u_pub_dest_tex.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        u_pub_dest_tex.binding = 2
        u_pub_dest_tex.add_id(cached_output_texture)
        
        var u_pub_dest_cnt := RDUniform.new()
        u_pub_dest_cnt.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        u_pub_dest_cnt.binding = 3
        u_pub_dest_cnt.add_id(cached_counter_texture)
        
        var pub_set := rd.uniform_set_create([u_pub_src, u_pub_cnt, u_pub_dest_tex, u_pub_dest_cnt], publish_shader_rid, 0)
        
        var pub_cl := rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(pub_cl, publish_pipeline_rid)
        rd.compute_list_bind_uniform_set(pub_cl, pub_set, 0)
        var pub_workgroups := ceili(float(total_splats) / 256.0)
        if pub_workgroups <= 0: pub_workgroups = 1
        rd.compute_list_dispatch(pub_cl, pub_workgroups, 1, 1)
        rd.compute_list_end()
        
        # Synced write-to-read barrier
        rd.barrier()
        
        # Generate indirect draw command arguments
        indirect_draw_buffer = generate_indirect_draw_command(counter_buffer, 3, false)
        
        rd.submit()
        
        # Async cleanup
        rd.free_rid(pub_set)
    else:
        # Standard synchronous pipeline
        rd.submit()
        rd.sync()
        
        var result_counter_bytes := rd.buffer_get_data(counter_buffer)
        valid_splat_count = result_counter_bytes.decode_u32(0)

    # Clean intermediate resources
    rd.free_rid(input_buffer)
    rd.free_rid(transforms_buffer)
    rd.free_rid(params_buffer)
    rd.free_rid(offsets_buffer)
    rd.free_rid(deltas_buffer)
    rd.free_rid(counter_buffer)
    rd.free_rid(camera_ubo)
    rd.free_rid(sampler_rid)
    if uniform_set.is_valid():
        rd.free_rid(uniform_set)
    if uniform_set_depth.is_valid():
        rd.free_rid(uniform_set_depth)
    if dummy_tex.is_valid():
        rd.free_rid(dummy_tex)
    if not use_gpu_instance_culling:
        rd.free_rid(u_vis_idx_dummy)
        rd.free_rid(u_vis_cnt_dummy)
    else:
        rd.free_rid(visible_indices_buffer)
        rd.free_rid(visible_counter_buffer)

    return {
        "buffer_rid": output_buffer,
        "count": valid_splat_count,
        "active_instance_indices": active_instance_indices if not use_gpu_instance_culling else range(instance_transforms.size()),
        "output_texture": cached_output_texture,
        "counter_texture": cached_counter_texture,
        "indirect_draw_buffer": indirect_draw_buffer
    }

func _recreate_gpu_driven_textures(total_splats: int) -> void:
    if cached_output_texture.is_valid():
        rd.free_rid(cached_output_texture)
    if cached_counter_texture.is_valid():
        rd.free_rid(cached_counter_texture)
        
    cached_max_splat_count = total_splats
    
    var tex_w: int = 1024
    var tex_h: int = ceili(float(total_splats) / 1024.0)
    if tex_h <= 0: tex_h = 1
    
    var out_tex_format := RDTextureFormat.new()
    out_tex_format.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_UINT
    out_tex_format.width = tex_w
    out_tex_format.height = tex_h
    out_tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
    cached_output_texture = rd.texture_create(out_tex_format, RDTextureView.new(), [])
    
    var cnt_tex_format := RDTextureFormat.new()
    cnt_tex_format.format = RenderingDevice.DATA_FORMAT_R32_UINT
    cnt_tex_format.width = 1
    cnt_tex_format.height = 1
    cnt_tex_format.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
    cached_counter_texture = rd.texture_create(cnt_tex_format, RDTextureView.new(), [])

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
    
    rd.barrier()
    rd.free_rid(uniform_set)
    return draw_indirect_buffer

func _extract_planes_to_bytes(vp: Projection, bytes: PackedByteArray, offset: int) -> void:
    # Extract Left Plane
    var n_left := Vector3(vp.x.w + vp.x.x, vp.y.w + vp.y.x, vp.z.w + vp.z.x)
    var len_left := n_left.length()
    n_left = n_left / len_left
    var d_left := (vp.w.w + vp.w.x) / len_left
    bytes.encode_float(offset + 0, n_left.x)
    bytes.encode_float(offset + 4, n_left.y)
    bytes.encode_float(offset + 8, n_left.z)
    bytes.encode_float(offset + 12, d_left)

    # Right Plane
    var n_right := Vector3(vp.x.w - vp.x.x, vp.y.w - vp.y.x, vp.z.w - vp.z.x)
    var len_right := n_right.length()
    n_right = n_right / len_right
    var d_right := (vp.w.w - vp.w.x) / len_right
    bytes.encode_float(offset + 16, n_right.x)
    bytes.encode_float(offset + 20, n_right.y)
    bytes.encode_float(offset + 24, n_right.z)
    bytes.encode_float(offset + 28, d_right)

    # Bottom Plane
    var n_bottom := Vector3(vp.x.w + vp.x.y, vp.y.w + vp.y.y, vp.z.w + vp.z.y)
    var len_bottom := n_bottom.length()
    n_bottom = n_bottom / len_bottom
    var d_bottom := (vp.w.w + vp.w.y) / len_bottom
    bytes.encode_float(offset + 32, n_bottom.x)
    bytes.encode_float(offset + 36, n_bottom.y)
    bytes.encode_float(offset + 40, n_bottom.z)
    bytes.encode_float(offset + 44, d_bottom)

    # Top Plane
    var n_top := Vector3(vp.x.w - vp.x.y, vp.y.w - vp.y.y, vp.z.w - vp.z.y)
    var len_top := n_top.length()
    n_top = n_top / len_top
    var d_top := (vp.w.w - vp.w.y) / len_top
    bytes.encode_float(offset + 48, n_top.x)
    bytes.encode_float(offset + 52, n_top.y)
    bytes.encode_float(offset + 56, n_top.z)
    bytes.encode_float(offset + 60, d_top)

    # Near Plane
    var n_near := Vector3(vp.x.w + vp.x.z, vp.y.w + vp.y.z, vp.z.w + vp.z.z)
    var len_near := n_near.length()
    n_near = n_near / len_near
    var d_near := (vp.w.w + vp.w.z) / len_near
    bytes.encode_float(offset + 64, n_near.x)
    bytes.encode_float(offset + 68, n_near.y)
    bytes.encode_float(offset + 72, n_near.z)
    bytes.encode_float(offset + 76, d_near)

    # Far Plane
    var n_far := Vector3(vp.x.w - vp.x.z, vp.y.w - vp.y.z, vp.z.w - vp.z.z)
    var len_far := n_far.length()
    n_far = n_far / len_far
    var d_far := (vp.w.w - vp.w.z) / len_far
    bytes.encode_float(offset + 80, n_far.x)
    bytes.encode_float(offset + 84, n_far.y)
    bytes.encode_float(offset + 88, n_far.z)
    bytes.encode_float(offset + 92, d_far)

static func serialize_transforms(transforms: Array[Transform3D]) -> PackedByteArray:
    var bytes: PackedByteArray = PackedByteArray()
    bytes.resize(transforms.size() * 64)
    for i in range(transforms.size()):
        var xf: Transform3D = transforms[i]
        var base: int = i * 64
        # Column 0
        bytes.encode_float(base + 0, xf.basis.x.x)
        bytes.encode_float(base + 4, xf.basis.x.y)
        bytes.encode_float(base + 8, xf.basis.x.z)
        bytes.encode_float(base + 12, 0.0)
        # Column 1
        bytes.encode_float(base + 16, xf.basis.y.x)
        bytes.encode_float(base + 20, xf.basis.y.y)
        bytes.encode_float(base + 24, xf.basis.y.z)
        bytes.encode_float(base + 28, 0.0)
        # Column 2
        bytes.encode_float(base + 32, xf.basis.z.x)
        bytes.encode_float(base + 36, xf.basis.z.y)
        bytes.encode_float(base + 40, xf.basis.z.z)
        bytes.encode_float(base + 44, 0.0)
        # Column 3
        bytes.encode_float(base + 48, xf.origin.x)
        bytes.encode_float(base + 52, xf.origin.y)
        bytes.encode_float(base + 56, xf.origin.z)
        bytes.encode_float(base + 60, 1.0)
    return bytes

func _create_dummy_depth_texture() -> RID:
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

func cleanup() -> void:
    if rd:
        if pipeline_rid.is_valid():
            rd.free_rid(pipeline_rid)
            pipeline_rid = RID()
        if shader_rid.is_valid():
            rd.free_rid(shader_rid)
            shader_rid = RID()
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
        if publish_pipeline_rid.is_valid():
            rd.free_rid(publish_pipeline_rid)
            publish_pipeline_rid = RID()
        if publish_shader_rid.is_valid():
            rd.free_rid(publish_shader_rid)
            publish_shader_rid = RID()
        if cached_output_texture.is_valid():
            rd.free_rid(cached_output_texture)
            cached_output_texture = RID()
        if cached_counter_texture.is_valid():
            rd.free_rid(cached_counter_texture)
            cached_counter_texture = RID()
        rd.free()
        rd = null
