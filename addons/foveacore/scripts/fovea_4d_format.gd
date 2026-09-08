class_name Fovea4DFormat
extends RefCounted

## Canonical structural contract for the little-endian FOVEA_4D v1 sidecar.

const MAGIC: String = "FOVEA_4D"
const VERSION: int = 1
const HEADER_SIZE: int = 128
const CODEC_GRID_INT16: int = 1
const LOOP_FLAG: int = 1
const MAX_PAYLOAD_BYTES: int = 256 * 1024 * 1024


static func expected_payload_size(grid_dims: Vector3i, keyframe_count: int) -> int:
	if grid_dims.x < 2 or grid_dims.x > 32:
		return -1
	if grid_dims.y < 2 or grid_dims.y > 32:
		return -1
	if grid_dims.z < 2 or grid_dims.z > 32:
		return -1
	if keyframe_count < 2 or keyframe_count > 256:
		return -1
	var size: int = keyframe_count * grid_dims.x * grid_dims.y * grid_dims.z * 6
	if size <= 0 or size > MAX_PAYLOAD_BYTES:
		return -1
	return size


static func parse_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE:
		return _failure("file is shorter than the 128-byte header")
	var magic: String = bytes.slice(0, 8).get_string_from_ascii()
	if magic != MAGIC:
		return _failure("invalid FOVEA_4D magic")
	var version: int = bytes.decode_u32(8)
	if version != VERSION:
		return _failure("unsupported version %d" % version)
	var header_size: int = bytes.decode_u32(12)
	if header_size != HEADER_SIZE:
		return _failure("header size must be 128")
	var flags: int = bytes.decode_u32(16)
	if flags & ~LOOP_FLAG:
		return _failure("unknown flags are set")
	var codec: int = bytes.decode_u32(20)
	if codec != CODEC_GRID_INT16:
		return _failure("unsupported codec %d" % codec)

	var digest_bytes: PackedByteArray = bytes.slice(24, 56)
	var digest_hex: String = ""
	for value: int in digest_bytes:
		digest_hex += "%02x" % value

	var grid_dims := Vector3i(
		bytes.decode_u16(56),
		bytes.decode_u16(58),
		bytes.decode_u16(60)
	)
	var keyframe_count: int = bytes.decode_u16(62)
	var expected_size: int = expected_payload_size(grid_dims, keyframe_count)
	if expected_size < 0:
		return _failure("grid dimensions or keyframe count are outside v1 limits")

	var sample_rate_hz: float = bytes.decode_float(64)
	if not is_finite(sample_rate_hz) or sample_rate_hz < 0.1 or sample_rate_hz > 240.0:
		return _failure("sample rate is outside 0.1..240.0 Hz")
	var bounds_min := Vector3(
		bytes.decode_float(68), bytes.decode_float(72), bytes.decode_float(76)
	)
	var bounds_max := Vector3(
		bytes.decode_float(80), bytes.decode_float(84), bytes.decode_float(88)
	)
	if not _valid_bounds(bounds_min, bounds_max):
		return _failure("bounds are non-finite or inverted")
	var displacement_scale := Vector3(
		bytes.decode_float(92), bytes.decode_float(96), bytes.decode_float(100)
	)
	if not _positive_finite_vector(displacement_scale):
		return _failure("displacement scales must be finite and positive")

	var payload_offset: int = bytes.decode_u64(104)
	var payload_size: int = bytes.decode_u64(112)
	if payload_offset != HEADER_SIZE:
		return _failure("payload offset must be 128")
	if payload_size != expected_size:
		return _failure("payload size does not match grid dimensions and keyframes")
	if payload_size > MAX_PAYLOAD_BYTES:
		return _failure("payload exceeds the 256 MiB limit")
	var total_size: int = payload_offset + payload_size
	if total_size < payload_offset or total_size != bytes.size():
		return _failure("file size does not exactly match header plus payload")
	for index: int in range(120, 128):
		if bytes[index] != 0:
			return _failure("reserved header bytes must be zero")

	return {
		"ok": true,
		"error": "",
		"header": {
			"version": version,
			"flags": flags,
			"loop": bool(flags & LOOP_FLAG),
			"codec": codec,
			"base_sha256": digest_hex,
			"grid_dims": grid_dims,
			"keyframe_count": keyframe_count,
			"sample_rate_hz": sample_rate_hz,
			"bounds_min": bounds_min,
			"bounds_max": bounds_max,
			"displacement_scale": displacement_scale,
			"payload_offset": payload_offset,
			"payload_size": payload_size,
		},
		"payload": bytes.slice(payload_offset, total_size),
	}


static func _valid_bounds(minimum: Vector3, maximum: Vector3) -> bool:
	return (
		_finite_vector(minimum)
		and _finite_vector(maximum)
		and minimum.x <= maximum.x
		and minimum.y <= maximum.y
		and minimum.z <= maximum.z
	)


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _positive_finite_vector(value: Vector3) -> bool:
	return _finite_vector(value) and value.x > 0.0 and value.y > 0.0 and value.z > 0.0


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "header": {}, "payload": PackedByteArray()}
