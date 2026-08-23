extends RefCounted
class_name FoveaClientSplatState

## Godot-owned sparse splat state with atomic revision-checked packet apply.
##
## This class has no transport, server, RPC, or GPU dependency. The player
## client owns the decoded state and can later feed snapshots into its local
## renderer or delta manager.

const ProtocolScript := preload(
	"res://addons/foveacore/scripts/network/fovea_splat_delta_protocol.gd"
)

var asset_id: String = ""
var splat_count: int = 0
var revision: int = 0

var _position_deltas: Dictionary = {}
var _color_deltas: Dictionary = {}
var _normal_deltas: Dictionary = {}


## Selects the immutable local asset and resets all sparse client-side deltas.
## A non-zero initial revision represents a locally loaded snapshot.
func configure(new_asset_id: String, new_splat_count: int, initial_revision: int = 0) -> String:
	if initial_revision < 0:
		return "initial_revision must not be negative"
	var identity_result: Dictionary = ProtocolScript.make_splat_id(
		new_asset_id,
		0,
		new_splat_count
	)
	if not bool(identity_result.get("ok", false)):
		return str(identity_result.get("error", "invalid asset identity"))

	asset_id = new_asset_id
	splat_count = new_splat_count
	revision = initial_revision
	_position_deltas.clear()
	_color_deltas.clear()
	_normal_deltas.clear()
	return ""


## Validates and applies a complete batch atomically to the local Godot state.
func apply_packet(packet: PackedByteArray) -> Dictionary:
	if asset_id.is_empty() or splat_count <= 0:
		return _failure("client splat state is not configured")

	var decoded: Dictionary = ProtocolScript.decode_batch(packet)
	if not bool(decoded.get("ok", false)):
		return _failure(str(decoded.get("error", "invalid delta packet")))
	var batch: Dictionary = decoded.get("batch", {})
	if str(batch.get("asset_id", "")) != asset_id:
		return _failure("delta packet targets another immutable asset")
	if int(batch.get("splat_count", 0)) != splat_count:
		return _failure("delta packet targets another asset layout")
	if int(batch.get("base_revision", -1)) != revision:
		return _failure("delta packet base_revision does not match local revision")

	var next_positions: Dictionary = _position_deltas.duplicate(true)
	var next_colors: Dictionary = _color_deltas.duplicate(true)
	var next_normals: Dictionary = _normal_deltas.duplicate(true)
	var changes: Array = batch.get("changes", [])
	for change_value: Variant in changes:
		var change: Dictionary = change_value
		var splat_index: int = int(change["index"])
		if change.has("position"):
			next_positions[splat_index] = change["position"]
		if change.has("color"):
			next_colors[splat_index] = change["color"]
		if change.has("normal"):
			next_normals[splat_index] = change["normal"]

	_position_deltas = next_positions
	_color_deltas = next_colors
	_normal_deltas = next_normals
	revision = int(batch["revision"])
	return {
		"ok": true,
		"error": "",
		"revision": revision,
		"applied_changes": changes.size(),
	}


## Returns a defensive copy of the fields currently owned by this client.
func get_splat_delta(splat_index: int) -> Dictionary:
	if splat_index < 0 or splat_index >= splat_count:
		return {}
	var result: Dictionary = {}
	if _position_deltas.has(splat_index):
		result["position"] = _position_deltas[splat_index]
	if _color_deltas.has(splat_index):
		result["color"] = _color_deltas[splat_index]
	if _normal_deltas.has(splat_index):
		result["normal"] = _normal_deltas[splat_index]
	if result.is_empty():
		return result
	result["index"] = splat_index
	result["splat_id"] = "%s/%d" % [asset_id, splat_index]
	return result


## Exports defensive sparse dictionaries for local renderer preparation.
func export_sparse_snapshot() -> Dictionary:
	if asset_id.is_empty() or splat_count <= 0:
		return {
			"ok": false,
			"error": "client splat state is not configured",
			"snapshot": {},
		}
	return {
		"ok": true,
		"error": "",
		"snapshot": {
			"asset_id": asset_id,
			"splat_count": splat_count,
			"revision": revision,
			"delta_positions": _position_deltas.duplicate(true),
			"delta_colors": _color_deltas.duplicate(true),
			"delta_normals": _normal_deltas.duplicate(true),
		},
	}


## Restores a defensive local checkpoint for the currently configured asset.
## Checkpoints from another immutable asset or containing malformed fields are
## rejected before any live state is changed.
func restore_checkpoint(checkpoint: Dictionary) -> Dictionary:
	if asset_id.is_empty() or splat_count <= 0:
		return _failure("client splat state is not configured")
	if str(checkpoint.get("asset_id", "")) != asset_id:
		return _failure("checkpoint targets another immutable asset")
	if int(checkpoint.get("splat_count", 0)) != splat_count:
		return _failure("checkpoint targets another asset layout")
	var checkpoint_revision: int = int(checkpoint.get("revision", -1))
	if checkpoint_revision < 0:
		return _failure("checkpoint revision must not be negative")
	for required_field: String in ["delta_positions", "delta_colors", "delta_normals"]:
		if not checkpoint.has(required_field):
			return _failure("checkpoint is missing required field: %s" % required_field)

	var positions_result: Dictionary = _validated_checkpoint_field(
		checkpoint.get("delta_positions", {}),
		"position"
	)
	if not bool(positions_result.get("ok", false)):
		return _failure(str(positions_result.get("error", "invalid checkpoint positions")))
	var colors_result: Dictionary = _validated_checkpoint_field(
		checkpoint.get("delta_colors", {}),
		"color"
	)
	if not bool(colors_result.get("ok", false)):
		return _failure(str(colors_result.get("error", "invalid checkpoint colors")))
	var normals_result: Dictionary = _validated_checkpoint_field(
		checkpoint.get("delta_normals", {}),
		"normal"
	)
	if not bool(normals_result.get("ok", false)):
		return _failure(str(normals_result.get("error", "invalid checkpoint normals")))

	_position_deltas = (positions_result.get("values", {}) as Dictionary).duplicate(true)
	_color_deltas = (colors_result.get("values", {}) as Dictionary).duplicate(true)
	_normal_deltas = (normals_result.get("values", {}) as Dictionary).duplicate(true)
	revision = checkpoint_revision
	return {
		"ok": true,
		"error": "",
		"revision": revision,
		"applied_changes": 0,
	}


## Replays a packet sequence as one client-local transaction. If any packet is
## corrupt or does not continue the revision chain, the complete pre-replay
## checkpoint is restored before returning the error.
func replay_packets_atomically(packets: Array) -> Dictionary:
	if asset_id.is_empty() or splat_count <= 0:
		return _failure("client splat state is not configured")
	var original_snapshot: Dictionary = export_sparse_snapshot().get("snapshot", {})
	var total_changes: int = 0
	for packet_value: Variant in packets:
		if not packet_value is PackedByteArray:
			restore_checkpoint(original_snapshot)
			return _failure("replay entries must be packed delta packets")
		var apply_result: Dictionary = apply_packet(packet_value as PackedByteArray)
		if not bool(apply_result.get("ok", false)):
			restore_checkpoint(original_snapshot)
			return _failure(str(apply_result.get("error", "delta replay failed")))
		total_changes += int(apply_result.get("applied_changes", 0))
	return {
		"ok": true,
		"error": "",
		"revision": revision,
		"applied_changes": total_changes,
		"replayed_packets": packets.size(),
	}


func _validated_checkpoint_field(source: Variant, field_name: String) -> Dictionary:
	if not source is Dictionary:
		return {"ok": false, "error": "checkpoint %s deltas must be a dictionary" % field_name}
	var values: Dictionary = source
	var validated: Dictionary = {}
	for index_value: Variant in values.keys():
		if not index_value is int:
			return {"ok": false, "error": "checkpoint splat indices must be integers"}
		var splat_index: int = int(index_value)
		if splat_index < 0 or splat_index >= splat_count:
			return {"ok": false, "error": "checkpoint splat index is outside the immutable asset"}
		var value: Variant = values[index_value]
		if field_name == "position":
			if not value is Vector3 or not _is_finite_vector3(value as Vector3):
				return {"ok": false, "error": "checkpoint position delta is invalid"}
		elif field_name == "color":
			if not value is Color or not _is_finite_color(value as Color):
				return {"ok": false, "error": "checkpoint color delta is invalid"}
		elif field_name == "normal":
			if not value is Vector2 or not _is_finite_vector2(value as Vector2):
				return {"ok": false, "error": "checkpoint normal delta is invalid"}
		validated[splat_index] = value
	return {"ok": true, "error": "", "values": validated}


static func _is_finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _is_finite_vector2(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _is_finite_color(value: Color) -> bool:
	return (
		is_finite(value.r)
		and is_finite(value.g)
		and is_finite(value.b)
		and is_finite(value.a)
	)


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"revision": -1,
		"applied_changes": 0,
	}
