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
var _gpu_sort_healthy: bool = true
var _last_sort_backend: StringName = &"none"
var _last_gpu_error: String = ""

func _init():
	_init_gpu()

func _init_gpu() -> void:
	if _initialized:
		return

	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		# Expected in headless / Compatibility mode: fall back gracefully to the
		# CPU sort path instead of erroring (null-safety rule, see CLAUDE.md).
		push_warning("SplatSorter: RenderingDevice unavailable — using CPU fallback")
		return

	var shader_file = preload("res://addons/foveacore/shaders/sort_compute.glsl")
	if shader_file == null:
		push_error("SplatSorter: Shader not found at res://addons/foveacore/shaders/sort_compute.glsl")
		return

	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	var compile_error: String = shader_spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not compile_error.is_empty():
		_last_gpu_error = compile_error
		push_error("SplatSorter: sort_compute.glsl failed to compile: " + compile_error)
		return
	_shader = _rd.shader_create_from_spirv(shader_spirv)
	if not _shader.is_valid():
		_last_gpu_error = "Unable to create the compute shader RID."
		push_error("SplatSorter: " + _last_gpu_error)
		return
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		_last_gpu_error = "Unable to create the compute pipeline RID."
		push_error("SplatSorter: " + _last_gpu_error)
		return

	_initialized = true
	_last_gpu_error = ""
	print("SplatSorter: GPU sorting initialized")

func sort_splats_back_to_front(splats: Array[GaussianSplat], camera: Camera3D) -> Array[int]:
	"""Retourne les indices des splats triés de lointain -> proche."""
	if camera == null:
		_last_sort_backend = &"identity"
		var indices: Array[int] = []
		indices.resize(splats.size())
		for i in range(splats.size()):
			indices[i] = i
		return indices

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
	var world_to_camera: Transform3D = camera.global_transform.affine_inverse()

	for i in range(n):
		depths[i] = -(world_to_camera * splats[i].position).z

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
	_rd.submit()
	_rd.sync()
	var elapsed = Time.get_ticks_msec() - start_time

	# 4. Lire back les indices (ordres : near-to-far après tri ascendant)
	var sorted_indices_all = _read_index_buffer(n_pow2)

	# 5. Filtrer les indices >= n (padding) et inverser pour far-to-near
	var sorted_indices: Array[int] = []
	var seen_indices: PackedByteArray = PackedByteArray()
	seen_indices.resize(n)
	for idx: int in sorted_indices_all:
		if idx >= 0 and idx < n and seen_indices[idx] == 0:
			seen_indices[idx] = 1
			sorted_indices.append(idx)
	if sorted_indices.size() != n:
		_last_gpu_error = "GPU sort returned %d unique indices for %d splats." % [sorted_indices.size(), n]
		push_warning("SplatSorter: %s Falling back to CPU sort." % _last_gpu_error)
		_gpu_sort_healthy = false
		_free_buffers()
		return _cpu_sort_fallback(splats, camera)

	# Inverser : le GPU a trié en near-to-far (ascendant), on veut far-to-near
	sorted_indices.reverse()

	_free_buffers()

	_last_sort_backend = &"gpu"
	_last_gpu_error = ""
	if debug_verbose:
		print("SplatSorter: Sorted %d splats (padded to %d) in %d ms (GPU)" % [n, n_pow2, elapsed])
	sort_completed.emit(sorted_indices, elapsed)

	return sorted_indices

func _create_buffers_padded(count: int, depths: PackedFloat32Array, indices: PackedInt32Array) -> bool:
	var depth_bytes = depths.to_byte_array()
	_depth_buffer = _rd.storage_buffer_create(depth_bytes.size(), depth_bytes)

	var idx_bytes = indices.to_byte_array()
	_index_buffer = _rd.storage_buffer_create(idx_bytes.size(), idx_bytes)

	var uniform_depth = RDUniform.new()
	uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_depth.binding = 0
	uniform_depth.add_id(_depth_buffer)

	var uniform_idx = RDUniform.new()
	uniform_idx.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_idx.binding = 1
	uniform_idx.add_id(_index_buffer)

	_uniform_set = _rd.uniform_set_create([uniform_depth, uniform_idx], _shader, 0)

	return true

func _dispatch_bitonic_sort(count: int) -> void:
	var stages: int = ceili(log(float(count)) / log(2.0))
	if debug_verbose:
		print("SplatSorter: Starting bitonic sort, stages=%d, count=%d" % [stages, count])

	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
	var workgroups: int = ceili(float(count) / 256.0)
	var sequence_length: int = 2
	while sequence_length <= count:
		var compare_distance: int = sequence_length >> 1
		while compare_distance > 0:
			var push_constants: PackedByteArray = PackedByteArray()
			push_constants.resize(16)
			push_constants.encode_u32(0, count)
			push_constants.encode_u32(4, sequence_length)
			push_constants.encode_u32(8, compare_distance)
			push_constants.encode_u32(12, 0)
			_rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
			_rd.compute_list_dispatch(compute_list, workgroups, 1, 1)
			_rd.compute_list_add_barrier(compute_list)
			compare_distance >>= 1
		sequence_length <<= 1
	_rd.compute_list_end()

	if debug_verbose:
		print("SplatSorter: Recorded all %d bitonic stages" % stages)

func _read_index_buffer(count: int) -> Array[int]:
	var data = _rd.buffer_get_data(_index_buffer)
	var indices: Array[int] = []
	for i in range(count):
		var val = data.decode_u32(i * 4)  # R32_UINT = 4 bytes
		indices.append(val)
	return indices

func _free_buffers() -> void:
	# Free the uniform set BEFORE its buffers: freeing a storage buffer first
	# auto-invalidates the dependent uniform set, so freeing it afterwards hits
	# an invalid ID ("Attempted to free invalid ID").
	if _uniform_set != RID():
		_rd.free_rid(_uniform_set)
		_uniform_set = RID()
	if _depth_buffer != RID():
		_rd.free_rid(_depth_buffer)
		_depth_buffer = RID()
	if _index_buffer != RID():
		_rd.free_rid(_index_buffer)
		_index_buffer = RID()

func _cpu_sort_fallback(splats: Array[GaussianSplat], camera: Camera3D) -> Array[int]:
	"""Tri CPU simple par distance décroissante (back to front)."""
	_last_sort_backend = &"cpu"
	if camera == null:
		var indices: Array[int] = []
		indices.resize(splats.size())
		for i in range(splats.size()):
			indices[i] = i
		return indices

	var start = Time.get_ticks_msec()
	var world_to_camera: Transform3D = camera.global_transform.affine_inverse()
	var indexed: Array[Dictionary] = []
	for i in range(splats.size()):
		var view_z: float = (world_to_camera * splats[i].position).z
		indexed.append({"idx": i, "view_z": view_z})

	indexed.sort_custom(func(a, b):
		return a["view_z"] < b["view_z"]
	)

	var sorted: Array[int] = []
	for item in indexed:
		sorted.append(item["idx"])

	var elapsed = Time.get_ticks_msec() - start
	if debug_verbose:
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
	return _initialized and _rd != null and _gpu_sort_healthy

func get_max_supported_splats() -> int:
	return _max_splats

func get_last_sort_backend() -> StringName:
	return _last_sort_backend

func get_last_gpu_error() -> String:
	return _last_gpu_error

func _cleanup_gpu() -> void:
	if not _rd:
		return
	_free_buffers()
	if _pipeline.is_valid():
		_rd.free_rid(_pipeline)
		_pipeline = RID()
	if _shader.is_valid():
		_rd.free_rid(_shader)
		_shader = RID()
	_rd.free()
	_rd = null
	_initialized = false

static func sort_by_depth(splats: Array[GaussianSplat], camera: Camera3D) -> Array[GaussianSplat]:
	if camera == null:
		return splats
	var world_to_camera: Transform3D = camera.global_transform.affine_inverse()
	var indexed: Array[Dictionary] = []
	for i in range(splats.size()):
		var view_z: float = (world_to_camera * splats[i].position).z
		indexed.append({"splat": splats[i], "view_z": view_z})

	indexed.sort_custom(func(a, b):
		return a["view_z"] < b["view_z"]
	)

	var sorted: Array[GaussianSplat] = []
	for item in indexed:
		sorted.append(item["splat"])
	return sorted

static func minimize_overdraw(splats: Array[GaussianSplat]) -> Array[GaussianSplat]:
	if splats.is_empty():
		return splats

	var grid: Dictionary = {}
	var grid_size := 0.02 # 2cm grid size for spatial clustering

	# Pass 1: Find the dominant (highest opacity) splat for each 3D cell
	for splat in splats:
		var cell = Vector3i(
			int(floor(splat.position.x / grid_size)),
			int(floor(splat.position.y / grid_size)),
			int(floor(splat.position.z / grid_size))
		)
		if not grid.has(cell):
			grid[cell] = splat
		else:
			if splat.opacity > grid[cell].opacity:
				grid[cell] = splat

	# Pass 2: Rebuild the array in original sorted order, keeping only the dominant splats
	var optimized: Array[GaussianSplat] = []
	for splat in splats:
		var cell = Vector3i(
			int(floor(splat.position.x / grid_size)),
			int(floor(splat.position.y / grid_size)),
			int(floor(splat.position.z / grid_size))
		)
		if grid.has(cell) and grid[cell] == splat:
			optimized.append(splat)
			grid.erase(cell) # Prevent duplicate check

	return optimized
