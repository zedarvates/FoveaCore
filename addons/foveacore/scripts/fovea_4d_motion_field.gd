class_name Fovea4DMotionField
extends Resource

const FormatScript := preload("res://addons/foveacore/scripts/fovea_4d_format.gd")

var base_sha256: String = ""
var grid_dims: Vector3i = Vector3i.ZERO
var keyframe_count: int = 0
var sample_rate_hz: float = 0.0
var loop: bool = false
var bounds_min: Vector3 = Vector3.ZERO
var bounds_max: Vector3 = Vector3.ZERO
var displacement_scale: Vector3 = Vector3.ZERO
var payload: PackedByteArray = PackedByteArray()
var displacement_min: Vector3 = Vector3.ZERO
var displacement_max: Vector3 = Vector3.ZERO


func configure(header: Dictionary, source_payload: PackedByteArray) -> String:
	var new_grid_dims: Vector3i = header.get("grid_dims", Vector3i.ZERO)
	var new_keyframe_count: int = int(header.get("keyframe_count", 0))
	var expected_size: int = FormatScript.expected_payload_size(new_grid_dims, new_keyframe_count)
	if expected_size < 0 or source_payload.size() != expected_size:
		return "motion payload size does not match dimensions and keyframes"
	var new_rate: float = float(header.get("sample_rate_hz", 0.0))
	if not is_finite(new_rate) or new_rate < 0.1 or new_rate > 240.0:
		return "sample rate is outside 0.1..240.0 Hz"
	var new_bounds_min: Vector3 = header.get("bounds_min", Vector3.ZERO)
	var new_bounds_max: Vector3 = header.get("bounds_max", Vector3.ZERO)
	if not _valid_bounds(new_bounds_min, new_bounds_max):
		return "motion bounds are non-finite or inverted"
	var new_scale: Vector3 = header.get("displacement_scale", Vector3.ZERO)
	if not _positive_finite_vector(new_scale):
		return "displacement scales must be finite and positive"
	var new_digest: String = str(header.get("base_sha256", ""))
	if new_digest.length() != 64 or not new_digest.is_valid_hex_number(false):
		return "base SHA-256 must be 64 hexadecimal characters"

	base_sha256 = new_digest.to_lower()
	grid_dims = new_grid_dims
	keyframe_count = new_keyframe_count
	sample_rate_hz = new_rate
	loop = bool(header.get("loop", int(header.get("flags", 0)) & FormatScript.LOOP_FLAG))
	bounds_min = new_bounds_min
	bounds_max = new_bounds_max
	displacement_scale = new_scale
	payload = source_payload.duplicate()
	_cache_displacement_extrema()
	return validate()


func validate() -> String:
	var expected_size: int = FormatScript.expected_payload_size(grid_dims, keyframe_count)
	if expected_size < 0 or payload.size() != expected_size:
		return "motion payload is not configured"
	if not is_finite(sample_rate_hz) or sample_rate_hz < 0.1 or sample_rate_hz > 240.0:
		return "sample rate is invalid"
	if not _valid_bounds(bounds_min, bounds_max):
		return "motion bounds are invalid"
	if not _positive_finite_vector(displacement_scale):
		return "displacement scale is invalid"
	if not _finite_vector(displacement_min) or not _finite_vector(displacement_max):
		return "displacement extrema are invalid"
	return ""


func sample(local_position: Vector3, time_seconds: float) -> Vector3:
	if not validate().is_empty() or not _finite_vector(local_position) or not is_finite(time_seconds):
		return Vector3.ZERO
	var extent: Vector3 = bounds_max - bounds_min
	var normalized := Vector3(
		0.0 if extent.x <= 0.000001 else (local_position.x - bounds_min.x) / extent.x,
		0.0 if extent.y <= 0.000001 else (local_position.y - bounds_min.y) / extent.y,
		0.0 if extent.z <= 0.000001 else (local_position.z - bounds_min.z) / extent.z
	)
	normalized = normalized.clamp(Vector3.ZERO, Vector3.ONE)
	var coordinate := Vector3(
		normalized.x * float(grid_dims.x - 1),
		normalized.y * float(grid_dims.y - 1),
		normalized.z * float(grid_dims.z - 1)
	)
	var lower := Vector3i(
		mini(int(floor(coordinate.x)), grid_dims.x - 2),
		mini(int(floor(coordinate.y)), grid_dims.y - 2),
		mini(int(floor(coordinate.z)), grid_dims.z - 2)
	)
	var spatial_weight := coordinate - Vector3(lower)

	var frame_coordinate: float = time_seconds * sample_rate_hz
	if loop:
		frame_coordinate = fposmod(frame_coordinate, float(keyframe_count))
	else:
		frame_coordinate = clampf(frame_coordinate, 0.0, float(keyframe_count - 1))
	var first_frame: int = int(floor(frame_coordinate))
	var second_frame: int = (first_frame + 1) % keyframe_count if loop else mini(first_frame + 1, keyframe_count - 1)
	var temporal_weight: float = frame_coordinate - float(first_frame)
	var first_sample: Vector3 = _sample_keyframe(lower, spatial_weight, first_frame)
	var second_sample: Vector3 = _sample_keyframe(lower, spatial_weight, second_frame)
	return first_sample.lerp(second_sample, temporal_weight)


func animated_bounds(base_bounds: AABB) -> AABB:
	var minimum: Vector3 = base_bounds.position + displacement_min
	var maximum: Vector3 = base_bounds.end + displacement_max
	return AABB(minimum, maximum - minimum)


func to_gpu_bytes() -> PackedByteArray:
	if not validate().is_empty():
		return PackedByteArray()
	var record_count: int = payload.size() / 6
	var result := PackedByteArray()
	result.resize(record_count * 8)
	for index: int in range(record_count):
		var source_offset: int = index * 6
		var target_offset: int = index * 8
		var packed_xy: int = payload.decode_u16(source_offset) | (payload.decode_u16(source_offset + 2) << 16)
		result.encode_u32(target_offset, packed_xy)
		result.encode_u32(target_offset + 4, payload.decode_u16(source_offset + 4))
	return result


func _sample_keyframe(lower: Vector3i, weight: Vector3, keyframe: int) -> Vector3:
	var c000: Vector3 = _decode_cell(lower.x, lower.y, lower.z, keyframe)
	var c100: Vector3 = _decode_cell(lower.x + 1, lower.y, lower.z, keyframe)
	var c010: Vector3 = _decode_cell(lower.x, lower.y + 1, lower.z, keyframe)
	var c110: Vector3 = _decode_cell(lower.x + 1, lower.y + 1, lower.z, keyframe)
	var c001: Vector3 = _decode_cell(lower.x, lower.y, lower.z + 1, keyframe)
	var c101: Vector3 = _decode_cell(lower.x + 1, lower.y, lower.z + 1, keyframe)
	var c011: Vector3 = _decode_cell(lower.x, lower.y + 1, lower.z + 1, keyframe)
	var c111: Vector3 = _decode_cell(lower.x + 1, lower.y + 1, lower.z + 1, keyframe)
	var c00: Vector3 = c000.lerp(c100, weight.x)
	var c10: Vector3 = c010.lerp(c110, weight.x)
	var c01: Vector3 = c001.lerp(c101, weight.x)
	var c11: Vector3 = c011.lerp(c111, weight.x)
	return c00.lerp(c10, weight.y).lerp(c01.lerp(c11, weight.y), weight.z)


func _cell_index(x: int, y: int, z: int, keyframe: int) -> int:
	return keyframe * grid_dims.x * grid_dims.y * grid_dims.z + (z * grid_dims.y + y) * grid_dims.x + x


func _decode_cell(x: int, y: int, z: int, keyframe: int) -> Vector3:
	var byte_offset: int = _cell_index(x, y, z, keyframe) * 6
	return Vector3(
		float(_decode_i16(payload, byte_offset)) * displacement_scale.x,
		float(_decode_i16(payload, byte_offset + 2)) * displacement_scale.y,
		float(_decode_i16(payload, byte_offset + 4)) * displacement_scale.z
	)


func _cache_displacement_extrema() -> void:
	displacement_min = Vector3(INF, INF, INF)
	displacement_max = Vector3(-INF, -INF, -INF)
	for byte_offset: int in range(0, payload.size(), 6):
		var value := Vector3(
			float(_decode_i16(payload, byte_offset)) * displacement_scale.x,
			float(_decode_i16(payload, byte_offset + 2)) * displacement_scale.y,
			float(_decode_i16(payload, byte_offset + 4)) * displacement_scale.z
		)
		displacement_min = displacement_min.min(value)
		displacement_max = displacement_max.max(value)


static func _decode_i16(bytes: PackedByteArray, offset: int) -> int:
	var value: int = bytes.decode_u16(offset)
	return value - 65536 if value >= 32768 else value


static func _valid_bounds(minimum: Vector3, maximum: Vector3) -> bool:
	return _finite_vector(minimum) and _finite_vector(maximum) and minimum.x <= maximum.x and minimum.y <= maximum.y and minimum.z <= maximum.z


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _positive_finite_vector(value: Vector3) -> bool:
	return _finite_vector(value) and value.x > 0.0 and value.y > 0.0 and value.z > 0.0
