extends SceneTree

const FormatScript := preload("res://addons/foveacore/scripts/fovea_4d_format.gd")

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	var valid: PackedByteArray = _build_valid_fixture()
	_assert("magic constant", FormatScript.MAGIC == "FOVEA_4D", FormatScript.MAGIC)
	_assert("header size constant", FormatScript.HEADER_SIZE == 128, str(FormatScript.HEADER_SIZE))
	_assert("payload formula", FormatScript.expected_payload_size(Vector3i(2, 2, 2), 2) == 96, "")
	_assert("invalid grid formula", FormatScript.expected_payload_size(Vector3i(1, 2, 2), 2) == -1, "")
	var parsed: Dictionary = FormatScript.parse_bytes(valid)
	_assert("valid fixture parses", bool(parsed.get("ok", false)), str(parsed))
	var header: Dictionary = parsed.get("header", {})
	_assert("grid round-trip", header.get("grid_dims", Vector3i.ZERO) == Vector3i(2, 2, 2), str(header))
	_assert("payload exact", (parsed.get("payload", PackedByteArray()) as PackedByteArray).size() == 96, str(parsed))
	_assert("digest hex", str(header.get("base_sha256", "")) == "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f", str(header))
	_expect_rejected("invalid magic", _mutate_byte(valid, 0, 0x58))
	_expect_rejected("unsupported version", _mutate_u32(valid, 8, 2))
	_expect_rejected("wrong header size", _mutate_u32(valid, 12, 64))
	_expect_rejected("unknown flags", _mutate_u32(valid, 16, 2))
	_expect_rejected("unknown codec", _mutate_u32(valid, 20, 2))
	_expect_rejected("grid below minimum", _mutate_u16(valid, 56, 1))
	_expect_rejected("grid above maximum", _mutate_u16(valid, 58, 33))
	_expect_rejected("too few keyframes", _mutate_u16(valid, 62, 1))
	_expect_rejected("non-finite sample rate", _mutate_float(valid, 64, NAN))
	_expect_rejected("inverted bounds", _mutate_float(valid, 68, 2.0))
	_expect_rejected("zero displacement scale", _mutate_float(valid, 92, 0.0))
	_expect_rejected("wrong payload offset", _mutate_u64(valid, 104, 129))
	_expect_rejected("wrong payload size", _mutate_u64(valid, 112, 95))
	_expect_rejected("non-zero reserved", _mutate_byte(valid, 120, 1))
	var truncated: PackedByteArray = valid.duplicate()
	truncated.resize(valid.size() - 1)
	_expect_rejected("truncated payload", truncated)
	var trailing: PackedByteArray = valid.duplicate()
	trailing.resize(valid.size() + 1)
	_expect_rejected("trailing bytes", trailing)
	print("Fovea4D format tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _build_valid_fixture() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(224)
	var magic: PackedByteArray = "FOVEA_4D".to_ascii_buffer()
	for index: int in range(magic.size()):
		bytes[index] = magic[index]
	bytes.encode_u32(8, 1)
	bytes.encode_u32(12, 128)
	bytes.encode_u32(16, 1)
	bytes.encode_u32(20, 1)
	for index: int in range(32):
		bytes[24 + index] = index
	bytes.encode_u16(56, 2)
	bytes.encode_u16(58, 2)
	bytes.encode_u16(60, 2)
	bytes.encode_u16(62, 2)
	bytes.encode_float(64, 4.0)
	bytes.encode_float(68, 0.0)
	bytes.encode_float(72, 0.0)
	bytes.encode_float(76, 0.0)
	bytes.encode_float(80, 1.0)
	bytes.encode_float(84, 1.0)
	bytes.encode_float(88, 1.0)
	bytes.encode_float(92, 0.01)
	bytes.encode_float(96, 0.02)
	bytes.encode_float(100, 0.03)
	bytes.encode_u64(104, 128)
	bytes.encode_u64(112, 96)
	return bytes


func _mutate_byte(source: PackedByteArray, offset: int, value: int) -> PackedByteArray:
	var result: PackedByteArray = source.duplicate()
	result[offset] = value
	return result


func _mutate_u16(source: PackedByteArray, offset: int, value: int) -> PackedByteArray:
	var result: PackedByteArray = source.duplicate()
	result.encode_u16(offset, value)
	return result


func _mutate_u32(source: PackedByteArray, offset: int, value: int) -> PackedByteArray:
	var result: PackedByteArray = source.duplicate()
	result.encode_u32(offset, value)
	return result


func _mutate_u64(source: PackedByteArray, offset: int, value: int) -> PackedByteArray:
	var result: PackedByteArray = source.duplicate()
	result.encode_u64(offset, value)
	return result


func _mutate_float(source: PackedByteArray, offset: int, value: float) -> PackedByteArray:
	var result: PackedByteArray = source.duplicate()
	result.encode_float(offset, value)
	return result


func _expect_rejected(test_name: String, bytes: PackedByteArray) -> void:
	var result: Dictionary = FormatScript.parse_bytes(bytes)
	_assert(test_name, not bool(result.get("ok", true)) and not str(result.get("error", "")).is_empty(), str(result))


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
