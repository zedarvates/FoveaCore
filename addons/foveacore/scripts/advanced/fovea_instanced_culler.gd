class_name FoveaInstancedCuller
extends RefCounted

# FoveaEngine : Pipeline de Compute Shader pour le Culling d'Instances de Splats
# Phase 3 : Global Splat Instancing

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID

const SPLAT_BYTE_SIZE: int = 16

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
    pipeline_rid  = rd.compute_pipeline_create(shader_rid)

## Culls instances of a splat asset on the GPU
## Returns Dictionary { "buffer_rid": RID, "count": int, "active_instance_indices": Array }
func process_instanced_splats(
    raw_bytes: PackedByteArray,
    instance_transforms: Array[Transform3D],
    camera: Camera3D,
    depth_texture: RID,
    cull_threshold: float = 0.0,
    aabb_min: Vector3 = Vector3(-5, -5, -5),
    aabb_max: Vector3 = Vector3(5, 5, 5)
) -> Dictionary:
    if raw_bytes.is_empty() or instance_transforms.is_empty() or not rd:
        return { "buffer_rid": RID(), "count": 0, "active_instance_indices": [] }

    # 1. CPU Frustum Culling on Instances (Instance-Level)
    var frustum = FrustumUtils.Frustum.new()
    frustum.from_matrix(camera.get_camera_projection(), camera.global_transform)

    var active_transforms: Array[Transform3D] = []
    var active_instance_indices: Array[int] = []
    var local_aabb = AABB(aabb_min, aabb_max - aabb_min).grow(0.1)

    for i in range(instance_transforms.size()):
        var xf = instance_transforms[i]
        var world_aabb = xf * local_aabb
        if frustum.contains_aabb(world_aabb):
            active_transforms.append(xf)
            active_instance_indices.append(i)

    if active_transforms.is_empty():
        return { "buffer_rid": RID(), "count": 0, "active_instance_indices": [] }

    var asset_splat_count = raw_bytes.size() / SPLAT_BYTE_SIZE
    var active_instances_count = active_transforms.size()

    # 2. Serialize Active Instance Matrices
    var transforms_bytes = serialize_transforms(active_transforms)

    # 3. Create GPU Buffers
    var input_buffer = rd.storage_buffer_create(raw_bytes.size(), raw_bytes)
    var transforms_buffer = rd.storage_buffer_create(transforms_bytes.size(), transforms_bytes)
    var output_buffer = rd.storage_buffer_create(active_instances_count * raw_bytes.size())
    
    var counter_bytes = PackedByteArray()
    counter_bytes.resize(4)
    var counter_buffer = rd.storage_buffer_create(4, counter_bytes)

    # Set 0: Buffers (input, transforms, output, counter)
    var uniform_input = RDUniform.new()
    uniform_input.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_input.binding = 0
    uniform_input.add_id(input_buffer)

    var uniform_transforms = RDUniform.new()
    uniform_transforms.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_transforms.binding = 1
    uniform_transforms.add_id(transforms_buffer)

    var uniform_output = RDUniform.new()
    uniform_output.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_output.binding = 2
    uniform_output.add_id(output_buffer)

    var uniform_counter = RDUniform.new()
    uniform_counter.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_counter.binding = 3
    uniform_counter.add_id(counter_buffer)

    var uniform_set = rd.uniform_set_create(
        [uniform_input, uniform_transforms, uniform_output, uniform_counter],
        shader_rid, 0
    )

    # Set 1: Depth map + Camera UBO
    var sampler_state = RDSamplerState.new()
    sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    var sampler_rid = rd.sampler_create(sampler_state)

    # Setup fallback 1x1 depth texture if invalid
    var actual_depth_tex = depth_texture
    var dummy_tex = RID()
    if not actual_depth_tex.is_valid():
        dummy_tex = _create_dummy_depth_texture()
        actual_depth_tex = dummy_tex

    var uniform_depth = RDUniform.new()
    uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    uniform_depth.binding = 0
    uniform_depth.add_id(sampler_rid)
    uniform_depth.add_id(actual_depth_tex)

    # Camera Data UBO
    var cam_pos = camera.global_position
    var view_matrix = camera.get_camera_transform().affine_inverse()
    var proj_matrix = camera.get_camera_projection()
    var view_proj = proj_matrix * view_matrix

    var camera_data_bytes = PackedByteArray()
    camera_data_bytes.resize(128)
    for col_idx in 4:
        for row_idx in 4:
            camera_data_bytes.encode_float((col_idx * 16) + (row_idx * 4), view_proj[col_idx][row_idx])
            # Right eye (fallback)
            camera_data_bytes.encode_float(64 + (col_idx * 16) + (row_idx * 4), view_proj[col_idx][row_idx])

    var camera_ubo = rd.storage_buffer_create(128, camera_data_bytes)
    var uniform_camera = RDUniform.new()
    uniform_camera.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    uniform_camera.binding = 1
    uniform_camera.add_id(camera_ubo)

    var uniform_set_depth = rd.uniform_set_create([uniform_depth, uniform_camera], shader_rid, 1)

    # Push Constants: 56 bytes
    var push_bytes = PackedByteArray()
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
    push_bytes.encode_float(36, 0.0) # pad0
    push_bytes.encode_float(40, aabb_max.x)
    push_bytes.encode_float(44, aabb_max.y)
    push_bytes.encode_float(48, aabb_max.z)
    push_bytes.encode_float(52, 0.0) # pad1

    # Dispatch Compute Shader
    var total_threads = asset_splat_count * active_instances_count
    var workgroups = ceili(float(total_threads) / 256.0)

    var compute_list = rd.compute_list_begin()
    rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    rd.compute_list_bind_uniform_set(compute_list, uniform_set_depth, 1)
    rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
    rd.compute_list_dispatch(compute_list, workgroups, 1, 1)
    rd.compute_list_end()

    rd.submit()
    rd.sync()

    # Read Counter
    var result_counter_bytes = rd.buffer_get_data(counter_buffer)
    var valid_splat_count = result_counter_bytes.decode_u32(0)

    # Cleanup intermediate buffers (keep output_buffer)
    rd.free_rid(input_buffer)
    rd.free_rid(transforms_buffer)
    rd.free_rid(counter_buffer)
    rd.free_rid(camera_ubo)
    rd.free_rid(sampler_rid)
    if dummy_tex.is_valid():
        rd.free_rid(dummy_tex)

    return {
        "buffer_rid": output_buffer,
        "count": valid_splat_count,
        "active_instance_indices": active_instance_indices
    }

static func serialize_transforms(transforms: Array[Transform3D]) -> PackedByteArray:
    var bytes = PackedByteArray()
    bytes.resize(transforms.size() * 64)
    for i in range(transforms.size()):
        var xf = transforms[i]
        var base = i * 64
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
        rd.free()
        rd = null
