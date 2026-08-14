extends SceneTree

## Structural validation tests for the canonical .fovea v2 container.
## These are non-GPU tests and intentionally exercise malformed headers.

const FoveaAssetScript := preload("res://addons/foveacore/scripts/fovea_asset.gd")
const FoveaAssetFormatLoaderScript := preload("res://addons/foveacore/scripts/fovea_asset_loader.gd")
const FoveaAssetFormatSaverScript := preload("res://addons/foveacore/scripts/fovea_asset_saver.gd")
const FoveaAssetWriterScript := preload("res://addons/foveacore/scripts/fovea_asset_writer.gd")
const FoveaBinaryFormatScript := preload("res://addons/foveacore/scripts/fovea_binary_format.gd")
const FoveaColorPaletteScript := preload("res://addons/foveacore/scripts/materials/fovea_color_palette.gd")
const GaussianSplatScript := preload("res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd")

const VALID_PATH := "user://fovea_format_validation_valid.fovea"
const RUST_FIXTURE_PATH := "res://test/fixtures/rust_v2_fixture.fovea"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	await create_timer(0.1).timeout
	var valid_bytes: PackedByteArray = _write_canonical_asset()
	if valid_bytes.is_empty():
		_summarize()
		return

	_test_canonical_header(valid_bytes)
	_test_packed_splat_record_semantics(valid_bytes)
	_test_rejects_truncated_header(valid_bytes)
	_test_rejects_invalid_magic(valid_bytes)
	_test_rejects_unsupported_version(valid_bytes)
	_test_rejects_oversized_payload(valid_bytes)
	_test_rejects_optional_section_inside_payload(valid_bytes)
	_test_saver_rejects_misaligned_raw_splats()
	_test_rust_generated_fixture()
	_summarize()


func _write_canonical_asset() -> PackedByteArray:
	var splat: GaussianSplat = GaussianSplatScript.new(Vector3(1.0, 2.0, 3.0))
	splat.normal = Vector3(1.0, 0.0, -1.0)
	splat.color = Color(0.2, 0.4, 0.6, 1.0)
	splat.opacity = 0.8
	splat.scale = Vector3(0.2, 0.3, 0.4)
	splat.layer_type = GaussianSplat.LayerType.LEAVES
	splat.dither_seed = 173
	splat.brush_type = GaussianSplat.BrushType.STIPPLE
	var splats: Array[GaussianSplat] = [splat]
	var written: bool = FoveaAssetWriterScript.write_fovea_asset(VALID_PATH, splats)
	_assert("writer creates canonical asset", written, "path=%s" % VALID_PATH)
	if not written:
		return PackedByteArray()
	return _read_bytes(VALID_PATH)


func _test_canonical_header(bytes: PackedByteArray) -> void:
	_assert("canonical header has expected size", bytes.size() >= FoveaBinaryFormatScript.HEADER_SIZE, "size=%d" % bytes.size())
	var file := FileAccess.open(VALID_PATH, FileAccess.READ)
	if file == null:
		_assert("canonical header can be opened", false, VALID_PATH)
		return
	var magic: String = file.get_buffer(8).get_string_from_utf8()
	var version: int = file.get_32()
	file.close()
	_assert("canonical magic", magic == FoveaBinaryFormatScript.MAGIC, magic)
	_assert("canonical version", version == FoveaBinaryFormatScript.VERSION, "version=%d" % version)
	_assert_load_result("canonical asset loads", VALID_PATH, true)


func _test_packed_splat_record_semantics(bytes: PackedByteArray) -> void:
	var record_offset: int = FoveaBinaryFormatScript.fixed_payload_end(1, 1, 1) - FoveaBinaryFormatScript.SPLAT_RECORD_SIZE
	_assert("packed record fits canonical payload", record_offset + FoveaBinaryFormatScript.SPLAT_RECORD_SIZE <= bytes.size(), "offset=%d" % record_offset)
	if record_offset + FoveaBinaryFormatScript.SPLAT_RECORD_SIZE > bytes.size():
		return

	_assert("packed position x", bytes.decode_u16(record_offset) == 32767, "value=%d" % bytes.decode_u16(record_offset))
	_assert("packed position y", bytes.decode_u16(record_offset + 2) == 32767, "value=%d" % bytes.decode_u16(record_offset + 2))
	_assert("packed position z", bytes.decode_u16(record_offset + 4) == 32767, "value=%d" % bytes.decode_u16(record_offset + 4))
	_assert("packed normal u", _decode_i8(bytes[record_offset + 6]) == 127, "value=%d" % _decode_i8(bytes[record_offset + 6]))
	_assert("packed normal v", _decode_i8(bytes[record_offset + 7]) == -127, "value=%d" % _decode_i8(bytes[record_offset + 7]))
	_assert("packed palette index", bytes[record_offset + 8] == 0, "value=%d" % bytes[record_offset + 8])
	_assert("packed covariance index", bytes.decode_u16(record_offset + 10) == 0, "value=%d" % bytes.decode_u16(record_offset + 10))
	_assert("packed opacity", bytes[record_offset + 12] == 204, "value=%d" % bytes[record_offset + 12])
	_assert("packed layer", bytes[record_offset + 13] == GaussianSplat.LayerType.LEAVES, "value=%d" % bytes[record_offset + 13])
	_assert("packed dither seed", bytes[record_offset + 14] == 173, "value=%d" % bytes[record_offset + 14])
	_assert("packed brush type", bytes[record_offset + 15] == GaussianSplat.BrushType.STIPPLE, "value=%d" % bytes[record_offset + 15])


func _test_rejects_truncated_header(bytes: PackedByteArray) -> void:
	var truncated: PackedByteArray = bytes.slice(0, FoveaBinaryFormatScript.HEADER_SIZE - 1)
	var path := "user://fovea_format_validation_truncated.fovea"
	_write_bytes(path, truncated)
	_assert_load_result("truncated header is rejected", path, false)


func _test_rejects_invalid_magic(bytes: PackedByteArray) -> void:
	var corrupt: PackedByteArray = bytes.duplicate()
	corrupt[0] = 0x58
	var path := "user://fovea_format_validation_magic.fovea"
	_write_bytes(path, corrupt)
	_assert_load_result("invalid magic is rejected", path, false)


func _test_rejects_unsupported_version(bytes: PackedByteArray) -> void:
	var corrupt: PackedByteArray = bytes.duplicate()
	corrupt.encode_u32(8, FoveaBinaryFormatScript.VERSION + 1)
	var path := "user://fovea_format_validation_version.fovea"
	_write_bytes(path, corrupt)
	_assert_load_result("unsupported version is rejected", path, false)


func _test_rejects_oversized_payload(bytes: PackedByteArray) -> void:
	var corrupt: PackedByteArray = bytes.duplicate()
	corrupt.encode_u32(12, 1_000_000)
	var path := "user://fovea_format_validation_payload.fovea"
	_write_bytes(path, corrupt)
	_assert_load_result("oversized splat payload is rejected", path, false)


func _test_rejects_optional_section_inside_payload(bytes: PackedByteArray) -> void:
	var corrupt: PackedByteArray = bytes.duplicate()
	corrupt.encode_u32(48, FoveaBinaryFormatScript.HEADER_SIZE)
	corrupt.encode_u32(52, 1)
	var path := "user://fovea_format_validation_section.fovea"
	_write_bytes(path, corrupt)
	_assert_load_result("optional section inside payload is rejected", path, false)


func _test_saver_rejects_misaligned_raw_splats() -> void:
	var asset: FoveaAsset = FoveaAssetScript.new()
	asset.splat_count = 1
	asset.aabb_min = Vector3.ZERO
	asset.aabb_max = Vector3.ONE
	asset.color_palette = FoveaColorPaletteScript.new()
	var palette_colors: Array[Color] = [Color.WHITE]
	asset.color_palette.colors = palette_colors
	asset.covariance_codebook.resize(FoveaBinaryFormatScript.COVARIANCE_ENTRY_SIZE)
	asset.splats_raw_bytes.resize(FoveaBinaryFormatScript.SPLAT_RECORD_SIZE - 1)
	var saver := FoveaAssetFormatSaverScript.new()
	var err: Error = saver._save(asset, "user://fovea_format_validation_invalid_save.fovea", 0)
	_assert("saver rejects invalid splat byte count", err == ERR_INVALID_DATA, "error=%d" % err)


func _test_rust_generated_fixture() -> void:
	_assert("Rust fixture is versioned", FileAccess.file_exists(RUST_FIXTURE_PATH), RUST_FIXTURE_PATH)
	if not FileAccess.file_exists(RUST_FIXTURE_PATH):
		return
	var loader := FoveaAssetFormatLoaderScript.new()
	var result: Variant = loader._load(RUST_FIXTURE_PATH, RUST_FIXTURE_PATH, false, 0)
	if not (result is FoveaAsset):
		_assert("Rust fixture loads in Godot", false, str(result))
		return
	var asset: FoveaAsset = result as FoveaAsset
	_assert("Rust fixture splat count", asset.splat_count == 1, "count=%d" % asset.splat_count)
	_assert("Rust fixture metadata", asset.metadata.get("fixture", "") == "rust_v2", str(asset.metadata))
	_assert("Rust fixture raw splat bytes", asset.splats_raw_bytes.size() == FoveaBinaryFormatScript.SPLAT_RECORD_SIZE, "bytes=%d" % asset.splats_raw_bytes.size())
	_assert("Rust fixture Gaussian brush type", asset.splats_raw_bytes[15] == GaussianSplat.BrushType.GAUSSIAN, "value=%d" % asset.splats_raw_bytes[15])


func _assert_load_result(name: String, path: String, should_succeed: bool) -> void:
	var loader := FoveaAssetFormatLoaderScript.new()
	var result: Variant = loader._load(path, path, false, 0)
	if should_succeed:
		_assert(name, result is FoveaAsset, str(result))
	else:
		_assert(name, result == ERR_FILE_CORRUPT, "result=%s" % str(result))


func _read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return bytes


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_assert("can write corrupt fixture", false, path)
		return
	file.store_buffer(bytes)
	file.close()


func _decode_i8(value: int) -> int:
	return value - 256 if value > 127 else value


func _assert(name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  ✓ %s — %s" % [name, detail])
	else:
		_failed += 1
		print("  ✗ %s — %s" % [name, detail])


func _summarize() -> void:
	print("Fovea format validation: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
