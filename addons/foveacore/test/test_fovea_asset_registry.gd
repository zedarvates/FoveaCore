extends SceneTree

## CPU-only contract tests for the content-addressed MMO asset registry.

const RegistryScript := preload(
	"res://addons/foveacore/scripts/network/fovea_asset_registry.gd"
)
const EXPECTED_FIXTURE_SHA256: String = (
	"f34c116064852afe6509ceb1653ea10e8d9acf20647aa243f150a60b52ca9b6d"
)
const ASSET_PATH: String = "user://registry_hash_fixture.fovea"
const INVALID_ASSET_PATH: String = "user://registry_invalid_fixture.fovea"
const REGISTRY_PATH: String = "user://fovea_mmo_registry_test.json"
const RUST_FIXTURE_PATH: String = "res://test/fixtures/rust_v2_fixture.fovea"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\nFovea MMO Asset Registry Tests")
	_write_fixture(INVALID_ASSET_PATH, PackedByteArray([97, 98, 99]))
	var invalid_binary_result: Dictionary = RegistryScript.build_entry(
		INVALID_ASSET_PATH,
		{
			"owner_id": "realm:ultimate-odycer",
			"biome_id": "velorath",
			"physics_profile": "static",
			"permissions": ["view"],
		}
	)
	_assert(
		"extension-only fake .fovea bytes fail closed",
		not bool(invalid_binary_result.get("ok", true))
			and str(invalid_binary_result.get("error", "")).contains("canonical header"),
		str(invalid_binary_result)
	)
	var canonical_bytes: PackedByteArray = FileAccess.get_file_as_bytes(RUST_FIXTURE_PATH)
	_write_fixture(ASSET_PATH, canonical_bytes)

	var metadata: Dictionary = {
		"owner_id": "realm:ultimate-odycer",
		"biome_id": "velorath",
		"physics_profile": "static",
		"permissions": ["stream", "view", "interact"],
	}
	var build_result: Dictionary = RegistryScript.build_entry(ASSET_PATH, metadata)
	_assert("valid metadata builds an entry", bool(build_result.get("ok", false)), str(build_result))

	var entry: Dictionary = build_result.get("entry", {})
	_assert(
		"content hash matches the exact file bytes",
		str(entry.get("content", {}).get("sha256", "")) == EXPECTED_FIXTURE_SHA256,
		str(entry)
	)
	_assert(
		"network ID is content-addressed",
		str(entry.get("asset_id", "")) == "sha256:%s" % EXPECTED_FIXTURE_SHA256,
		str(entry.get("asset_id", ""))
	)
	_assert(
		"entry publishes the canonical binary format version",
		int(entry.get("content", {}).get("format_version", -1)) == 2,
		str(entry.get("content", {}))
	)
	_assert(
		"entry defaults to server authority",
		str(entry.get("mmo", {}).get("authority_model", "")) == "server_authoritative",
		str(entry.get("mmo", {}))
	)
	_assert(
		"permissions are normalized deterministically",
		entry.get("mmo", {}).get("permissions", []) == ["interact", "stream", "view"],
		str(entry.get("mmo", {}).get("permissions", []))
	)

	var invalid_metadata: Dictionary = metadata.duplicate(true)
	invalid_metadata["permissions"] = ["view", "spawn_admin_shell"]
	var invalid_result: Dictionary = RegistryScript.build_entry(ASSET_PATH, invalid_metadata)
	_assert(
		"unknown permissions fail closed",
		not bool(invalid_result.get("ok", true))
			and str(invalid_result.get("error", "")).contains("spawn_admin_shell"),
		str(invalid_result)
	)

	var registry_result: Dictionary = RegistryScript.build_registry([entry])
	_assert("one valid entry builds a registry", bool(registry_result.get("ok", false)), str(registry_result))
	var registry: Dictionary = registry_result.get("registry", {})
	_assert(
		"registry publishes semantic schema version",
		str(registry.get("schema_version", "")) == "1.0.0",
		str(registry)
	)

	var duplicate_result: Dictionary = RegistryScript.build_registry([entry, entry.duplicate(true)])
	_assert(
		"duplicate content IDs are rejected",
		not bool(duplicate_result.get("ok", true))
			and str(duplicate_result.get("error", "")).contains("duplicate"),
		str(duplicate_result)
	)

	var save_error: Error = RegistryScript.save_registry(REGISTRY_PATH, registry)
	_assert("valid registry saves as JSON", save_error == OK, error_string(save_error))
	var load_result: Dictionary = RegistryScript.load_registry(REGISTRY_PATH)
	_assert("saved registry loads and validates", bool(load_result.get("ok", false)), str(load_result))
	_assert(
		"loaded registry preserves the stable asset ID",
		str(load_result.get("registry", {}).get("assets", [{}])[0].get("asset_id", ""))
			== "sha256:%s" % EXPECTED_FIXTURE_SHA256,
		str(load_result)
	)

	_assert(
		"untouched file verifies against the registry entry",
		RegistryScript.verify_asset_file(entry, ASSET_PATH).is_empty(),
		RegistryScript.verify_asset_file(entry, ASSET_PATH)
	)
	canonical_bytes[canonical_bytes.size() - 1] ^= 1
	_write_fixture(ASSET_PATH, canonical_bytes)
	var tamper_error: String = RegistryScript.verify_asset_file(entry, ASSET_PATH)
	_assert(
		"same-size file tampering is detected by SHA-256",
		tamper_error.contains("SHA-256 mismatch"),
		tamper_error
	)

	_cleanup()
	print("Fovea MMO Asset Registry Tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _write_fixture(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("fixture creation", FileAccess.get_open_error())
		return
	file.store_buffer(bytes)
	file.close()


func _cleanup() -> void:
	var user_dir: DirAccess = DirAccess.open("user://")
	if user_dir == null:
		return
	for path: String in [ASSET_PATH, INVALID_ASSET_PATH, REGISTRY_PATH]:
		if FileAccess.file_exists(path):
			user_dir.remove(path.get_file())


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])


func _fail(test_name: String, error: Variant) -> void:
	_failed += 1
	print("  FAIL: %s -- %s" % [test_name, str(error)])
