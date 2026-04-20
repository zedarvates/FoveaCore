extends RefCounted
class_name SplatSorter
## SplatSorter — GPU-accelerated depth sorting for Gaussian Splats
## Implements Bitonic Sort using a Compute Shader (RenderingDevice)

# GaussianSplat is a global class_name

signal sort_completed(sorted_indices: Array[int], elapsed_ms: float)

@export var debug_verbose: bool = false

var _rd: RenderingDevice = null
var _shader: RID = RID()
var _pipeline: RID = RID()

# Buffers GPU
var _depth_buffer: RID = RID()
var _index_buffer: RID = RID()
var _uniform_set: RID = RID()

var _max_splats: int = 65536
var _initialized: bool = false
var _debug_verbose: bool = false

func _init():
	_init_gpu()

func _init_gpu() -> void:
	if _initialized:
		return

	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		push_error("SplatSorter: RenderingDevice unavailable")
		return

	var shader_file = load("res://addons/foveacore/shaders/sort_compute.glsl")
	if shader_file == null:
		push_error("SplatSorter: Shader not found at res://addons/foveacore/shaders/sort_compute.glsl")
		return

	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)

	_initialized = true
	print("SplatSorter: GPU sorting initialized")

func sort_splats_back_to_front(splats: Array[GaussianSplat], camera: Camera3D) -> Array[int]:
	"""Retourne les indices des splats triés de lointain -> proche."""
	if not _initialized or splats.is_empty():
		return _cpu_sort_fallback(splats, camera)

	var n = splats.size()
	if n > _max_splats:
		push_warning("SplatSorter: Too many splats (%d), falling back to CPU sort" % n)
		return _cpu_sort_fallback(splats, camera)

	# Pad to power of 2 for bitonic sort
	var n_pow2 = 1
	while n_pow2 < n:
		n_pow2 <<= 1

	# 1. Extraire les depths par rapport à la caméra
	var depths: PackedFloat32Array = PackedFloat32Array()
	depths.resize(n_pow2)

	for i in range(n):
		var dist = splats[i].position.distance_to(camera.global_position)
		depths[i] = dist

	# Padding avec +inf (loin) pour les éléments supplémentaires
	for i in range(n, n_pow2):
		depths[i] = 1e30  # Très loin

	# 2. Créer les buffers GPU (pad)
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(n_pow2)
	for i in range(n_pow2):
		indices[i] = i

	var success = _create_buffers_padded(n_pow2, depths, indices)
	if not success:
		return _cpu_sort_fallback(splats, camera)

	# 3. Lancer le bitonic sort sur GPU
	var start_time = Time.get_ticks_msec()
	_dispatch_bitonic_sort(n_pow2)
	_rd.sync()
	var elapsed = Time.get_ticks_msec() - start_time

	# 4. Lire back les indices (ordres : near-to-far après tri ascendant)
	var sorted_indices_all = _read_index_buffer(n_pow2)

	# 5. Filtrer les indices >= n (padding) et inverser pour far-to-near
	var sorted_indices: Array[int] = []
	for idx in sorted_indices_all:
		if idx < n:
			sorted_indices.append(idx)

	# Inverser : le GPU a trié en near-to-far (ascendant), on veut far-to-near
	sorted_indices.reverse()

	_free_buffers()

	print("SplatSorter: Sorted %d splats (padded to %d) in %d ms (GPU)" % [n, n_pow2, elapsed])
	sort_completed.emit(sorted_indices, elapsed)

	return sorted_indices

func _create_buffers_padded(count: int, depths: PackedFloat32Array, indices: PackedInt32Array) -> bool:
	var fmt = RDTextureFormat.new()
	fmt.width = count
	fmt.height = 1
	fmt.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	var depth_bytes = depths.to_byte_array()
	_depth_buffer = _rd.texture_create(fmt, RDTextureView.new(), [depth_bytes])

	var idx_fmt = RDTextureFormat.new()
	idx_fmt.width = count
	idx_fmt.height = 1
	idx_fmt.format = RenderingDevice.DATA_FORMAT_R32_UINT
	idx_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	var idx_bytes = indices.to_byte_array()
	_index_buffer = _rd.texture_create(idx_fmt, RDTextureView.new(), [idx_bytes])

	var uniform_depth = RDUniform.new()
	uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_depth.binding = 0
	uniform_depth.add_id(_depth_buffer)

	var uniform_idx = RDUniform.new()
	uniform_idx.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_idx.binding = 1
	uniform_idx.add_id(_index_buffer)

	_uniform_set = _rd.uniform_set_create([uniform_depth, uniform_idx], _shader, 0)

	return true

func _dispatch_bitonic_sort(count: int) -> void:
	var stages = ceil(log(count) / log(2.0))
	if _debug_verbose:
		print("SplatSorter: Starting bitonic sort, stages=%d, count=%d" % [int(stages), count])

	for stage in range(int(stages)):
		var push_constants = PackedByteArray()
		push_constants.resize(16)
		push_constants.encode_u32(0, count)
		push_constants.encode_u32(4, stage)
		push_constants.encode_u32(8, 0)
		push_constants.encode_u32(12, 0)

		var compute_list = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
		_rd.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
		_rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
		_rd.compute_list_dispatch(compute_list, ceil(count / 256.0), 1, 1)
		_rd.compute_list_end()

		_rd.submit()
		_rd.sync()

		if _debug_verbose:
			print("SplatSorter: Stage %d/%d complete" % [stage+1, int(stages)])

func _read_index_buffer(count: int) -> Array[int]:
	var data = _rd.texture_get_data(_index_buffer, 0)
	var indices: Array[int] = []
	for i in range(count):
		var val = data.decode_u32(i * 4)  # R32_UINT = 4 bytes
		indices.append(val)
	return indices

func _free_buffers() -> void:
	if _depth_buffer != RID():
		_rd.free_rid(_depth_buffer)
		_depth_buffer = RID()
	if _index_buffer != RID():
		_rd.free_rid(_index_buffer)
		_index_buffer = RID()
	if _uniform_set != RID():
		_rd.free_rid(_uniform_set)
		_uniform_set = RID()

func _cpu_sort_fallback(splats: Array[GaussianSplat], camera: Camera3D) -> Array[int]:
	"""Tri CPU simple par distance décroissante (back to front)."""
	var start = Time.get_ticks_msec()
	var indexed: Array[Dictionary] = []
	for i in range(splats.size()):
		var dist = splats[i].position.distance_to(camera.global_position)
		indexed.append({"idx": i, "dist": dist})

	indexed.sort_custom(func(a, b):
		return a["dist"] > b["dist"]
	)

	var sorted: Array[int] = []
	for item in indexed:
		sorted.append(item["idx"])

	var elapsed = Time.get_ticks_msec() - start
	print("SplatSorter: CPU sorted %d splats in %d ms" % [splats.size(), elapsed])
	return sorted

func sort_indices_by_depth(splats: Array[GaussianSplat], depths: Array[float]) -> Array[int]:
	"""Alternative: sort from precomputed depths (no camera needed)."""
	if splats.size() != depths.size():
		push_error("SplatSorter: Size mismatch")
		return []

	var indexed: Array[Dictionary] = []
	for i in range(splats.size()):
		indexed.append({"idx": i, "depth": depths[i]})

	indexed.sort_custom(func(a, b):
		return a["depth"] > b["depth"]
	)

	var sorted: Array[int] = []
	for item in indexed:
		sorted.append(item["idx"])
	return sorted

func is_gpu_available() -> bool:
	return _initialized and _rd != null

func get_max_supported_splats() -> int:
	return _max_splats

static func sort_by_depth(splats: Array[GaussianSplat], camera_pos: Vector3) -> Array[GaussianSplat]:
	var indexed: Array[Dictionary] = []
	for i in range(splats.size()):
		var dist = splats[i].position.distance_to(camera_pos)
		indexed.append({"splat": splats[i], "dist": dist})

	indexed.sort_custom(func(a, b):
		return a["dist"] > b["dist"]
	)

	var sorted: Array[GaussianSplat] = []
	for item in indexed:
		sorted.append(item["splat"])
	return sorted

static func minimize_overdraw(splats: Array[GaussianSplat]) -> Array[GaussianSplat]:
	var optimized: Array[GaussianSplat] = []
	var last_pos: Vector3 = Vector3.INF

	for splat in splats:
		if splat.position.distance_to(last_pos) > 0.005:
			optimized.append(splat)
			last_pos = splat.position
	return optimized
