class_name Fovea4DWriter
extends RefCounted

const FormatScript := preload("res://addons/foveacore/scripts/fovea_4d_format.gd")
const LoaderScript := preload("res://addons/foveacore/scripts/fovea_4d_loader.gd")


static func write_sidecar(
	path: String,
	base_path: String,
	grid_dims: Vector3i,
	keyframes: Array[PackedVector3Array],
	sample_rate_hz: float,
	loop: bool,
	bounds: AABB
) -> Error:
	if not _is_local_path(path) or path.get_extension().to_lower() != "fovea4d":
		return ERR_INVALID_PARAMETER
	if not _is_local_path(base_path) or base_path.get_extension().to_lower() != "fovea":
		return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(base_path):
		return ERR_FILE_NOT_FOUND
	if not is_finite(sample_rate_hz) or sample_rate_hz < 0.1 or sample_rate_hz > 240.0:
		return ERR_INVALID_PARAMETER
	if not _valid_bounds(bounds):
		return ERR_INVALID_PARAMETER
	var payload_size: int = FormatScript.expected_payload_size(grid_dims, keyframes.size())
	if payload_size < 0:
		return ERR_INVALID_PARAMETER
	var cells_per_frame: int = grid_dims.x * grid_dims.y * grid_dims.z
	var maximum := Vector3.ZERO
	for frame: PackedVector3Array in keyframes:
		if frame.size() != cells_per_frame:
			return ERR_INVALID_PARAMETER
		for offset: Vector3 in frame:
			if not _finite_vector(offset):
				return ERR_INVALID_DATA
			maximum = maximum.max(offset.abs())
	var scale := Vector3(
		maximum.x / 32767.0 if maximum.x > 0.0 else 1.0,
		maximum.y / 32767.0 if maximum.y > 0.0 else 1.0,
		maximum.z / 32767.0 if maximum.z > 0.0 else 1.0
	)

	var payload := PackedByteArray()
	payload.resize(payload_size)
	var cursor: int = 0
	for frame: PackedVector3Array in keyframes:
		for offset: Vector3 in frame:
			payload.encode_u16(cursor, _quantize(offset.x, scale.x) & 0xffff)
			payload.encode_u16(cursor + 2, _quantize(offset.y, scale.y) & 0xffff)
			payload.encode_u16(cursor + 4, _quantize(offset.z, scale.z) & 0xffff)
			cursor += 6

	var base_digest: String = FileAccess.get_sha256(base_path).to_lower()
	if base_digest.length() != 64:
		return ERR_INVALID_DATA
	var header := PackedByteArray()
	header.resize(FormatScript.HEADER_SIZE)
	var magic: PackedByteArray = FormatScript.MAGIC.to_ascii_buffer()
	for index: int in range(magic.size()):
		header[index] = magic[index]
	header.encode_u32(8, FormatScript.VERSION)
	header.encode_u32(12, FormatScript.HEADER_SIZE)
	header.encode_u32(16, FormatScript.LOOP_FLAG if loop else 0)
	header.encode_u32(20, FormatScript.CODEC_GRID_INT16)
	for index: int in range(32):
		header[24 + index] = base_digest.substr(index * 2, 2).hex_to_int()
	header.encode_u16(56, grid_dims.x)
	header.encode_u16(58, grid_dims.y)
	header.encode_u16(60, grid_dims.z)
	header.encode_u16(62, keyframes.size())
	header.encode_float(64, sample_rate_hz)
	header.encode_float(68, bounds.position.x)
	header.encode_float(72, bounds.position.y)
	header.encode_float(76, bounds.position.z)
	header.encode_float(80, bounds.end.x)
	header.encode_float(84, bounds.end.y)
	header.encode_float(88, bounds.end.z)
	header.encode_float(92, scale.x)
	header.encode_float(96, scale.y)
	header.encode_float(100, scale.z)
	header.encode_u64(104, FormatScript.HEADER_SIZE)
	header.encode_u64(112, payload_size)
	header.append_array(payload)

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(header)
	file.close()
	var reload: Dictionary = LoaderScript.load_sidecar(path, base_path)
	if not bool(reload.get("ok", false)):
		_remove_file(path)
		return ERR_FILE_CORRUPT
	return OK


static func _quantize(value: float, scale: float) -> int:
	return clampi(roundi(value / scale), -32767, 32767)


static func _is_local_path(path: String) -> bool:
	return path.begins_with("res://") or path.begins_with("user://")


static func _valid_bounds(bounds: AABB) -> bool:
	return (
		_finite_vector(bounds.position)
		and _finite_vector(bounds.end)
		and bounds.size.x >= 0.0
		and bounds.size.y >= 0.0
		and bounds.size.z >= 0.0
	)


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _remove_file(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path.get_base_dir())
	if directory != null and FileAccess.file_exists(path):
		directory.remove(path.get_file())
