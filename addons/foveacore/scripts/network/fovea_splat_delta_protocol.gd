extends RefCounted
class_name FoveaSplatDeltaProtocol

## Versioned, compressed wire contract for client-owned sparse splat deltas.
##
## One immutable asset SHA-256 is stored per batch. Individual splats are
## addressed collision-free by `(asset_id, splat_index)` and encoded as fixed
## 28-byte FP16 records before the complete batch is compressed with ZSTD.

const FoveaDeltaDataScript := preload(
	"res://addons/foveacore/scripts/advanced/fovea_delta_data.gd"
)

const OUTER_MAGIC: String = "FVZ1"
const INNER_MAGIC: String = "FVND"
const PROTOCOL_VERSION: int = 1
const AUTHORITY_MODEL: String = "client_owned"
const OUTER_HEADER_SIZE: int = 8
const RAW_HEADER_SIZE: int = 64
const RECORD_SIZE: int = 28
const MAX_CHANGES: int = 4096
const MAX_RAW_BYTES: int = RAW_HEADER_SIZE + RECORD_SIZE * MAX_CHANGES

const FIELD_POSITION: int = 1
const FIELD_COLOR: int = 2
const FIELD_NORMAL: int = 4
const FIELD_ALL: int = FIELD_POSITION | FIELD_COLOR | FIELD_NORMAL


## Returns a stable human-readable splat ID without hashing the tuple again.
static func make_splat_id(asset_id: String, splat_index: int, splat_count: int) -> Dictionary:
	var asset_error: String = _validate_asset_id(asset_id)
	if not asset_error.is_empty():
		return _failure(asset_error, "splat_id", "")
	if splat_count <= 0:
		return _failure("splat_count must be greater than zero", "splat_id", "")
	if splat_index < 0 or splat_index >= splat_count:
		return _failure("splat_index is outside the immutable asset", "splat_id", "")
	return {
		"ok": true,
		"error": "",
		"splat_id": "%s/%d" % [asset_id, splat_index],
	}


## Encodes a validated client revision transition into a ZSTD packet.
static func encode_batch(
	asset_id: String,
	splat_count: int,
	base_revision: int,
	revision: int,
	changes: Array
) -> Dictionary:
	var asset_error: String = _validate_asset_id(asset_id)
	if not asset_error.is_empty():
		return _failure(asset_error, "packet", PackedByteArray())
	if splat_count <= 0 or splat_count > 0x7FFFFFFF:
		return _failure("splat_count is outside 1..2147483647", "packet", PackedByteArray())
	if base_revision < 0 or revision <= base_revision:
		return _failure("revision must be greater than base_revision", "packet", PackedByteArray())
	if changes.is_empty() or changes.size() > MAX_CHANGES:
		return _failure(
			"change count is outside 1..%d" % MAX_CHANGES,
			"packet",
			PackedByteArray()
		)

	var normalized_changes: Array[Dictionary] = []
	var seen_indices: Dictionary = {}
	for change_value: Variant in changes:
		if not change_value is Dictionary:
			return _failure("each change must be an object", "packet", PackedByteArray())
		var change: Dictionary = change_value
		var normalized_result: Dictionary = _normalize_change(change, splat_count)
		if not bool(normalized_result.get("ok", false)):
			return _failure(
				str(normalized_result.get("error", "invalid change")),
				"packet",
				PackedByteArray()
			)
		var normalized: Dictionary = normalized_result["change"]
		var splat_index: int = int(normalized["index"])
		if seen_indices.has(splat_index):
			return _failure(
				"duplicate splat index: %d" % splat_index,
				"packet",
				PackedByteArray()
			)
		seen_indices[splat_index] = true
		normalized_changes.append(normalized)

	var raw_size: int = RAW_HEADER_SIZE + normalized_changes.size() * RECORD_SIZE
	var raw := PackedByteArray()
	raw.resize(raw_size)
	_write_ascii(raw, 0, INNER_MAGIC)
	raw.encode_u16(4, PROTOCOL_VERSION)
	raw.encode_u16(6, 0)
	raw.encode_u64(8, base_revision)
	raw.encode_u64(16, revision)
	raw.encode_u32(24, splat_count)
	raw.encode_u32(28, normalized_changes.size())
	var digest_bytes: PackedByteArray = asset_id.trim_prefix("sha256:").hex_decode()
	for digest_index: int in range(digest_bytes.size()):
		raw[32 + digest_index] = digest_bytes[digest_index]

	for change_index: int in range(normalized_changes.size()):
		_encode_change(raw, RAW_HEADER_SIZE + change_index * RECORD_SIZE, normalized_changes[change_index])

	var compressed: PackedByteArray = raw.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty():
		return _failure("ZSTD compression failed", "packet", PackedByteArray())
	var packet := PackedByteArray()
	packet.resize(OUTER_HEADER_SIZE)
	_write_ascii(packet, 0, OUTER_MAGIC)
	packet.encode_u32(4, raw_size)
	packet.append_array(compressed)
	return {"ok": true, "error": "", "packet": packet}


## Decodes and validates an untrusted packet before exposing any delta values.
static func decode_batch(packet: PackedByteArray) -> Dictionary:
	if packet.size() <= OUTER_HEADER_SIZE:
		return _failure("packet is shorter than the compressed envelope", "batch", {})
	if packet.slice(0, 4).get_string_from_ascii() != OUTER_MAGIC:
		return _failure("invalid compressed envelope magic", "batch", {})
	var raw_size: int = packet.decode_u32(4)
	if raw_size < RAW_HEADER_SIZE or raw_size > MAX_RAW_BYTES:
		return _failure("declared raw size is outside protocol bounds", "batch", {})

	var compressed: PackedByteArray = packet.slice(OUTER_HEADER_SIZE)
	var raw: PackedByteArray = compressed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return _failure("ZSTD decompression failed or returned the wrong size", "batch", {})
	if raw.slice(0, 4).get_string_from_ascii() != INNER_MAGIC:
		return _failure("invalid delta batch magic", "batch", {})
	if raw.decode_u16(4) != PROTOCOL_VERSION:
		return _failure("unsupported delta protocol version", "batch", {})
	if raw.decode_u16(6) != 0:
		return _failure("unsupported delta protocol flags", "batch", {})

	var base_revision: int = raw.decode_u64(8)
	var revision: int = raw.decode_u64(16)
	var splat_count: int = raw.decode_u32(24)
	var change_count: int = raw.decode_u32(28)
	if splat_count <= 0 or splat_count > 0x7FFFFFFF:
		return _failure("decoded splat_count is outside protocol bounds", "batch", {})
	if revision <= base_revision:
		return _failure("decoded revision is not monotone", "batch", {})
	if change_count <= 0 or change_count > MAX_CHANGES:
		return _failure("decoded change count is outside protocol bounds", "batch", {})
	if raw_size != RAW_HEADER_SIZE + change_count * RECORD_SIZE:
		return _failure("decoded batch size does not match its change count", "batch", {})

	var asset_id: String = "sha256:%s" % raw.slice(32, 64).hex_encode()
	var asset_error: String = _validate_asset_id(asset_id)
	if not asset_error.is_empty():
		return _failure(asset_error, "batch", {})

	var changes: Array[Dictionary] = []
	var seen_indices: Dictionary = {}
	for change_index: int in range(change_count):
		var decoded_result: Dictionary = _decode_change(
			raw,
			RAW_HEADER_SIZE + change_index * RECORD_SIZE,
			asset_id,
			splat_count
		)
		if not bool(decoded_result.get("ok", false)):
			return _failure(str(decoded_result.get("error", "invalid change")), "batch", {})
		var change: Dictionary = decoded_result["change"]
		var splat_index: int = int(change["index"])
		if seen_indices.has(splat_index):
			return _failure("duplicate decoded splat index: %d" % splat_index, "batch", {})
		seen_indices[splat_index] = true
		changes.append(change)

	return {
		"ok": true,
		"error": "",
		"batch": {
			"protocol_version": PROTOCOL_VERSION,
			"authority_model": AUTHORITY_MODEL,
			"asset_id": asset_id,
			"splat_count": splat_count,
			"base_revision": base_revision,
			"revision": revision,
			"changes": changes,
		},
	}


static func _normalize_change(change: Dictionary, splat_count: int) -> Dictionary:
	if not change.has("index") or not change["index"] is int:
		return _change_failure("change index must be an integer")
	var splat_index: int = int(change["index"])
	if splat_index < 0 or splat_index >= splat_count:
		return _change_failure("change index is outside the immutable asset")

	var mask: int = 0
	var normalized: Dictionary = {"index": splat_index}
	if change.has("position"):
		if not change["position"] is Vector3:
			return _change_failure("position delta must be a Vector3")
		var position: Vector3 = change["position"]
		if not _is_finite_vector3(position):
			return _change_failure("position delta must contain finite values")
		normalized["position"] = position
		mask |= FIELD_POSITION
	if change.has("color"):
		if not change["color"] is Color:
			return _change_failure("color delta must be a Color")
		var color: Color = change["color"]
		if not _is_finite_color(color):
			return _change_failure("color delta must contain finite values")
		normalized["color"] = color
		mask |= FIELD_COLOR
	if change.has("normal"):
		if not change["normal"] is Vector2:
			return _change_failure("normal delta must be a Vector2")
		var normal: Vector2 = change["normal"]
		if not is_finite(normal.x) or not is_finite(normal.y):
			return _change_failure("normal delta must contain finite values")
		normalized["normal"] = normal
		mask |= FIELD_NORMAL
	if mask == 0:
		return _change_failure("change must contain position, color, or normal")
	normalized["field_mask"] = mask
	return {"ok": true, "error": "", "change": normalized}


static func _encode_change(raw: PackedByteArray, offset: int, change: Dictionary) -> void:
	raw.encode_u32(offset, int(change["index"]))
	raw.encode_u32(offset + 4, int(change["field_mask"]))
	var position: Vector3 = change.get("position", Vector3.ZERO)
	raw.encode_u32(offset + 8, FoveaDeltaDataScript.pack_half_2x16(position.x, position.y))
	raw.encode_u16(offset + 12, FoveaDeltaDataScript.float_to_half(position.z))
	raw.encode_u16(offset + 14, 0)
	var color: Color = change.get("color", Color(0.0, 0.0, 0.0, 0.0))
	raw.encode_u32(offset + 16, FoveaDeltaDataScript.pack_half_2x16(color.r, color.g))
	raw.encode_u32(offset + 20, FoveaDeltaDataScript.pack_half_2x16(color.b, color.a))
	var normal: Vector2 = change.get("normal", Vector2.ZERO)
	raw.encode_u32(offset + 24, FoveaDeltaDataScript.pack_half_2x16(normal.x, normal.y))


static func _decode_change(
	raw: PackedByteArray,
	offset: int,
	asset_id: String,
	splat_count: int
) -> Dictionary:
	var splat_index: int = raw.decode_u32(offset)
	if splat_index < 0 or splat_index >= splat_count:
		return _change_failure("decoded change index is outside the immutable asset")
	var mask: int = raw.decode_u32(offset + 4)
	if mask <= 0 or (mask & ~FIELD_ALL) != 0:
		return _change_failure("decoded field mask contains unsupported bits")

	var change: Dictionary = {
		"index": splat_index,
		"splat_id": "%s/%d" % [asset_id, splat_index],
	}
	if (mask & FIELD_POSITION) != 0:
		var position_xy: Vector2 = FoveaDeltaDataScript.unpack_half_2x16(
			raw.decode_u32(offset + 8)
		)
		var position := Vector3(
			position_xy.x,
			position_xy.y,
			FoveaDeltaDataScript.half_to_float(raw.decode_u16(offset + 12))
		)
		if not _is_finite_vector3(position):
			return _change_failure("decoded position delta is non-finite")
		change["position"] = position
	if (mask & FIELD_COLOR) != 0:
		var color_rg: Vector2 = FoveaDeltaDataScript.unpack_half_2x16(raw.decode_u32(offset + 16))
		var color_ba: Vector2 = FoveaDeltaDataScript.unpack_half_2x16(raw.decode_u32(offset + 20))
		var color := Color(color_rg.x, color_rg.y, color_ba.x, color_ba.y)
		if not _is_finite_color(color):
			return _change_failure("decoded color delta is non-finite")
		change["color"] = color
	if (mask & FIELD_NORMAL) != 0:
		var normal: Vector2 = FoveaDeltaDataScript.unpack_half_2x16(raw.decode_u32(offset + 24))
		if not is_finite(normal.x) or not is_finite(normal.y):
			return _change_failure("decoded normal delta is non-finite")
		change["normal"] = normal
	return {"ok": true, "error": "", "change": change}


static func _validate_asset_id(asset_id: String) -> String:
	if not asset_id.begins_with("sha256:"):
		return "asset_id must use the sha256 scheme"
	var digest: String = asset_id.trim_prefix("sha256:")
	if digest.length() != 64:
		return "asset_id digest must contain 64 lowercase hexadecimal characters"
	for index: int in range(digest.length()):
		if not "0123456789abcdef".contains(digest.substr(index, 1)):
			return "asset_id digest must contain 64 lowercase hexadecimal characters"
	return ""


static func _is_finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _is_finite_color(value: Color) -> bool:
	return (
		is_finite(value.r)
		and is_finite(value.g)
		and is_finite(value.b)
		and is_finite(value.a)
	)


static func _write_ascii(target: PackedByteArray, offset: int, value: String) -> void:
	var bytes: PackedByteArray = value.to_ascii_buffer()
	for index: int in range(bytes.size()):
		target[offset + index] = bytes[index]


static func _change_failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "change": {}}


static func _failure(message: String, payload_key: String, payload: Variant) -> Dictionary:
	return {"ok": false, "error": message, payload_key: payload}
