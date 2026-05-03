extends Node
class_name GPUNoiseGenerator

## GPUNoiseGenerator — Pre-computes procedural FBM + Worley noise into a 3D texture
## Usage: Initialize once, then sample from the texture in shaders.
## Replaces per-splat GDScript noise calls with a single texture sample.

signal noise_ready(noise_rid: RID, resolution: int)
signal error_occurred(message: String)

@export var resolution: int = 64
@export var noise_scale: float = 10.0
@export var lacunarity: float = 2.0
@export var gain: float = 0.5
@export var octaves: int = 4
@export var seed: int = 42

var _rd: RenderingDevice = null
var _shader: RID = RID()
var _pipeline: RID = RID()
var _noise_texture: RID = RID()
var _initialized: bool = false


func _ready() -> void:
	_generate_noise()


func _generate_noise() -> void:
	_rd = RenderingServer.create_local_rendering_device()
	if not _rd:
		error_occurred.emit("RenderingDevice unavailable")
		return

	var shader_file = load("res://addons/foveacore/shaders/procedural_noise.glsl")
	if not shader_file:
		error_occurred.emit("procedural_noise.glsl not found")
		return

	var spirv = shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(spirv)
	_pipeline = _rd.compute_pipeline_create(_shader)

	# Create 3D noise texture
	var fmt = RDTextureFormat.new()
	fmt.width = resolution
	fmt.height = resolution
	fmt.depth = resolution
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

	_noise_texture = _rd.texture_create(fmt, RDTextureView.new(), [])

	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(_noise_texture)
	var uniform_set = _rd.uniform_set_create([uniform], _shader, 0)

	var push_bytes = PackedByteArray()
	push_bytes.resize(24)
	push_bytes.encode_u32(0, resolution)
	push_bytes.encode_float(4, noise_scale)
	push_bytes.encode_float(8, lacunarity)
	push_bytes.encode_float(12, gain)
	push_bytes.encode_u32(16, octaves)
	push_bytes.encode_u32(20, seed)

	var compute_list = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	_rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())

	var groups = ceil(float(resolution) / 8.0)
	_rd.compute_list_dispatch(compute_list, groups, groups, groups)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()

	_initialized = true
	print("GPUNoiseGenerator: %d³ 3D noise texture ready" % resolution)
	noise_ready.emit(_noise_texture, resolution)


func get_noise_rid() -> RID:
	return _noise_texture


func is_ready() -> bool:
	return _initialized


func sample_noise(position: Vector3) -> Vector3:
	"""CPU-side sample (slow — prefer shader-side via noise_texture uniform)."""
	if not _initialized:
		return Vector3.ZERO
	var uvw = (position / noise_scale + Vector3(0.5, 0.5, 0.5)).clamp(Vector3.ZERO, Vector3.ONE)
	var x = int(uvw.x * float(resolution - 1))
	var y = int(uvw.y * float(resolution - 1))
	var z = int(uvw.z * float(resolution - 1))
	var data = _rd.texture_get_data(_noise_texture, 0)
	# texture_get_data returns PackedByteArray — decode at offset
	var offset = (z * resolution * resolution + y * resolution + x) * 16
	var fbm_val = data.decode_float(offset)
	var worley_dist = data.decode_float(offset + 4)
	return Vector3(fbm_val, worley_dist, 0.0)


func cleanup() -> void:
	if _rd:
		if _noise_texture.is_valid():
			_rd.free_rid(_noise_texture)
		_rd.free()
	_initialized = false
