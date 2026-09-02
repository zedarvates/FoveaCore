class_name Fovea4DLoader
extends RefCounted

const FormatScript := preload("res://addons/foveacore/scripts/fovea_4d_format.gd")
const MotionFieldScript := preload("res://addons/foveacore/scripts/fovea_4d_motion_field.gd")


static func load_sidecar(sidecar_path: String, base_fovea_path: String) -> Dictionary:
	if not _is_local_path(sidecar_path):
		return _failure("sidecar path must be project-local or cache-local")
	if sidecar_path.get_extension().to_lower() != "fovea4d":
		return _failure("sidecar path must use .fovea4d")
	if not _is_local_path(base_fovea_path):
		return _failure("base path must be project-local or cache-local")
	if base_fovea_path.get_extension().to_lower() != "fovea":
		return _failure("base asset must use .fovea")
	if not FileAccess.file_exists(sidecar_path):
		return _failure("sidecar file does not exist: %s" % sidecar_path)
	if not FileAccess.file_exists(base_fovea_path):
		return _failure("base asset does not exist: %s" % base_fovea_path)

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(sidecar_path)
	var parsed: Dictionary = FormatScript.parse_bytes(bytes)
	if not bool(parsed.get("ok", false)):
		return _failure(str(parsed.get("error", "invalid sidecar")))
	var observed_digest: String = FileAccess.get_sha256(base_fovea_path).to_lower()
	if observed_digest.length() != 64:
		return _failure("base asset SHA-256 could not be computed")
	var header: Dictionary = parsed.get("header", {})
	if str(header.get("base_sha256", "")) != observed_digest:
		return _failure("base .fovea SHA-256 mismatch")

	var field := MotionFieldScript.new()
	var configure_error: String = field.configure(
		header, parsed.get("payload", PackedByteArray()) as PackedByteArray
	)
	if not configure_error.is_empty():
		return _failure(configure_error)
	return {"ok": true, "error": "", "field": field}


static func _is_local_path(path: String) -> bool:
	return path.begins_with("res://") or path.begins_with("user://")


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "field": null}
