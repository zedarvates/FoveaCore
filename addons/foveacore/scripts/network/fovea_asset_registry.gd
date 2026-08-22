extends RefCounted
class_name FoveaAssetRegistry

## Content-addressed JSON registry contract for authoritative MMO asset delivery.
##
## The registry intentionally remains a sidecar to the binary `.fovea` format:
## existing v2 assets stay readable while servers gain stable IDs, ownership,
## permissions, and download-integrity checks.

const FoveaBinaryFormatScript := preload(
	"res://addons/foveacore/scripts/fovea_binary_format.gd"
)

const SCHEMA_VERSION: String = "1.0.0"
const ENTRY_SCHEMA_VERSION: String = "1.0.0"
const REGISTRY_KIND: String = "fovea.mmo_asset_registry"
const HASH_ALGORITHM: String = "sha256"
const AUTHORITY_MODEL: String = "server_authoritative"
const PHYSICS_PROFILES: Array[String] = [
	"none", "static", "kinematic", "dynamic", "soft_body",
]
const PERMISSIONS: Array[String] = [
	"view", "stream", "interact", "modify", "admin",
]


## Builds one registry entry from the exact bytes of a local `.fovea` file.
## Returns `{ok, error, entry}` so callers can reject invalid input without
## depending on log parsing.
static func build_entry(path: String, mmo_metadata: Dictionary) -> Dictionary:
	if path.get_extension().to_lower() != "fovea":
		return _failure("asset path must use the .fovea extension", "entry")
	if not FileAccess.file_exists(path):
		return _failure("asset file does not exist: %s" % path, "entry")
	var inspection: Dictionary = _inspect_fovea_file(path)
	if not bool(inspection.get("ok", false)):
		return _failure(
			"invalid .fovea asset: %s" % str(inspection.get("error", "invalid header")),
			"entry"
		)

	var metadata_result: Dictionary = _normalize_mmo_metadata(mmo_metadata)
	if not bool(metadata_result.get("ok", false)):
		return _failure(str(metadata_result.get("error", "invalid MMO metadata")), "entry")

	var byte_size: int = int(inspection.get("bytes", 0))

	var digest: String = FileAccess.get_sha256(path).to_lower()
	if not _is_lower_hex_sha256(digest):
		return _failure("asset SHA-256 could not be computed", "entry")

	var entry: Dictionary = {
		"schema_version": ENTRY_SCHEMA_VERSION,
		"asset_id": "%s:%s" % [HASH_ALGORITHM, digest],
		"content": {
			"format": "fovea",
			"format_version": FoveaBinaryFormatScript.VERSION,
			"hash_algorithm": HASH_ALGORITHM,
			"sha256": digest,
			"bytes": byte_size,
		},
		"mmo": metadata_result["metadata"],
		"source": {
			"uri": str(mmo_metadata.get("source_uri", path.get_file())),
		},
	}
	return {"ok": true, "error": "", "entry": entry}


## Builds a registry and rejects invalid or duplicate content-addressed IDs.
static func build_registry(entries: Array[Dictionary]) -> Dictionary:
	var registry: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"kind": REGISTRY_KIND,
		"assets": entries.duplicate(true),
	}
	var validation_error: String = validate_registry(registry)
	if not validation_error.is_empty():
		return _failure(validation_error, "registry")
	return {"ok": true, "error": "", "registry": registry}


## Returns an empty string for a valid entry, otherwise a fail-closed reason.
static func validate_entry(entry: Dictionary) -> String:
	if str(entry.get("schema_version", "")) != ENTRY_SCHEMA_VERSION:
		return "unsupported entry schema_version"

	var content_value: Variant = entry.get("content")
	if not content_value is Dictionary:
		return "entry content must be an object"
	var content: Dictionary = content_value
	var digest: String = str(content.get("sha256", ""))
	if not _is_lower_hex_sha256(digest):
		return "content sha256 must be 64 lowercase hexadecimal characters"
	if str(content.get("hash_algorithm", "")) != HASH_ALGORITHM:
		return "content hash_algorithm must be sha256"
	if str(entry.get("asset_id", "")) != "%s:%s" % [HASH_ALGORITHM, digest]:
		return "asset_id must match the content SHA-256"
	if str(content.get("format", "")) != "fovea":
		return "content format must be fovea"
	if int(content.get("format_version", -1)) != FoveaBinaryFormatScript.VERSION:
		return "content format_version must match the canonical .fovea version"
	if int(content.get("bytes", 0)) <= 0:
		return "content bytes must be greater than zero"

	var mmo_value: Variant = entry.get("mmo")
	if not mmo_value is Dictionary:
		return "entry mmo metadata must be an object"
	var metadata_result: Dictionary = _normalize_mmo_metadata(mmo_value)
	if not bool(metadata_result.get("ok", false)):
		return str(metadata_result.get("error", "invalid MMO metadata"))
	return ""


## Returns an empty string for a valid registry, otherwise a fail-closed reason.
static func validate_registry(registry: Dictionary) -> String:
	if str(registry.get("schema_version", "")) != SCHEMA_VERSION:
		return "unsupported registry schema_version"
	if str(registry.get("kind", "")) != REGISTRY_KIND:
		return "registry kind must be %s" % REGISTRY_KIND

	var assets_value: Variant = registry.get("assets")
	if not assets_value is Array:
		return "registry assets must be an array"
	var seen_ids: Dictionary = {}
	for entry_value: Variant in assets_value:
		if not entry_value is Dictionary:
			return "registry assets must contain objects"
		var entry: Dictionary = entry_value
		var entry_error: String = validate_entry(entry)
		if not entry_error.is_empty():
			return entry_error
		var asset_id: String = str(entry.get("asset_id", ""))
		if seen_ids.has(asset_id):
			return "duplicate asset_id: %s" % asset_id
		seen_ids[asset_id] = true
	return ""


## Validates and saves a deterministic JSON representation of the registry.
static func save_registry(path: String, registry: Dictionary) -> Error:
	var validation_error: String = validate_registry(registry)
	if not validation_error.is_empty():
		push_error("FoveaAssetRegistry: %s" % validation_error)
		return ERR_INVALID_DATA
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(registry, "\t", true, true))
	file.close()
	return OK


## Loads and validates JSON without trusting its schema or entry contents.
static func load_registry(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("registry file does not exist: %s" % path, "registry")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure(
			"registry file could not be opened: %s" % error_string(FileAccess.get_open_error()),
			"registry"
		)
	var source: String = file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_error: Error = parser.parse(source)
	if parse_error != OK:
		return _failure(
			"invalid registry JSON at line %d: %s" % [
				parser.get_error_line(), parser.get_error_message(),
			],
			"registry"
		)
	if not parser.data is Dictionary:
		return _failure("registry JSON root must be an object", "registry")
	var registry: Dictionary = parser.data
	var validation_error: String = validate_registry(registry)
	if not validation_error.is_empty():
		return _failure(validation_error, "registry")
	return {"ok": true, "error": "", "registry": registry}


## Verifies downloaded bytes before a client or server accepts the asset.
static func verify_asset_file(entry: Dictionary, path: String) -> String:
	var entry_error: String = validate_entry(entry)
	if not entry_error.is_empty():
		return entry_error
	if not FileAccess.file_exists(path):
		return "asset file does not exist: %s" % path

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "asset file could not be opened: %s" % error_string(FileAccess.get_open_error())
	var observed_size: int = file.get_length()
	file.close()
	var content: Dictionary = entry["content"]
	var expected_size: int = int(content["bytes"])
	if observed_size != expected_size:
		return "byte-size mismatch: expected %d, observed %d" % [expected_size, observed_size]

	var observed_digest: String = FileAccess.get_sha256(path).to_lower()
	var expected_digest: String = str(content["sha256"])
	if observed_digest != expected_digest:
		return "SHA-256 mismatch: expected %s, observed %s" % [
			expected_digest, observed_digest,
		]
	return ""


## Reads and validates the canonical v2 header before the registry attests an
## asset. An extension and a digest alone must never turn arbitrary bytes into
## a trusted `.fovea` record.
static func _inspect_fovea_file(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"error": "file could not be opened: %s" % error_string(FileAccess.get_open_error()),
			"bytes": 0,
		}
	var file_size: int = file.get_length()
	if file_size < FoveaBinaryFormatScript.HEADER_SIZE:
		file.close()
		return {"ok": false, "error": "file is shorter than the canonical header", "bytes": 0}

	var magic: String = file.get_buffer(8).get_string_from_ascii()
	if magic != FoveaBinaryFormatScript.MAGIC:
		file.close()
		return {"ok": false, "error": "invalid magic", "bytes": 0}

	var version: int = file.get_32()
	var splat_count: int = file.get_32()
	var color_count: int = file.get_32()
	var covariance_count: int = file.get_32()
	var aabb_min := Vector3(file.get_float(), file.get_float(), file.get_float())
	var aabb_max := Vector3(file.get_float(), file.get_float(), file.get_float())
	var optional_sections: Array[Dictionary] = [
		{"name": "style", "offset": file.get_32(), "size": file.get_32()},
		{"name": "mesh", "offset": file.get_32(), "size": file.get_32()},
		{"name": "metadata", "offset": file.get_32(), "size": file.get_32()},
	]
	file.close()

	var layout_error: String = FoveaBinaryFormatScript.validate_layout(
		file_size,
		version,
		splat_count,
		color_count,
		covariance_count,
		aabb_min,
		aabb_max,
		optional_sections
	)
	if not layout_error.is_empty():
		return {"ok": false, "error": layout_error, "bytes": 0}
	return {"ok": true, "error": "", "bytes": file_size}


static func _normalize_mmo_metadata(metadata: Dictionary) -> Dictionary:
	var owner_id: String = str(metadata.get("owner_id", "")).strip_edges()
	if owner_id.is_empty():
		return _metadata_failure("owner_id is required")
	var biome_id: String = str(metadata.get("biome_id", "")).strip_edges()
	if biome_id.is_empty():
		return _metadata_failure("biome_id is required")
	var physics_profile: String = str(metadata.get("physics_profile", ""))
	if not PHYSICS_PROFILES.has(physics_profile):
		return _metadata_failure("unknown physics_profile: %s" % physics_profile)
	var authority_model: String = str(metadata.get("authority_model", AUTHORITY_MODEL))
	if authority_model != AUTHORITY_MODEL:
		return _metadata_failure("authority_model must be %s" % AUTHORITY_MODEL)

	var permissions_value: Variant = metadata.get("permissions")
	if not permissions_value is Array:
		return _metadata_failure("permissions must be an array")
	var normalized_permissions: Array[String] = []
	for permission_value: Variant in permissions_value:
		if not permission_value is String:
			return _metadata_failure("permissions must contain strings")
		var permission: String = permission_value
		if not PERMISSIONS.has(permission):
			return _metadata_failure("unknown permission: %s" % permission)
		if not normalized_permissions.has(permission):
			normalized_permissions.append(permission)
	if normalized_permissions.is_empty():
		return _metadata_failure("permissions must not be empty")
	normalized_permissions.sort()

	return {
		"ok": true,
		"error": "",
		"metadata": {
			"owner_id": owner_id,
			"biome_id": biome_id,
			"physics_profile": physics_profile,
			"permissions": normalized_permissions,
			"authority_model": AUTHORITY_MODEL,
		},
	}


static func _is_lower_hex_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var character: String = value.substr(index, 1)
		if not "0123456789abcdef".contains(character):
			return false
	return true


static func _metadata_failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "metadata": {}}


static func _failure(message: String, payload_key: String) -> Dictionary:
	return {"ok": false, "error": message, payload_key: {}}
