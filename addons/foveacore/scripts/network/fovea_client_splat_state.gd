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


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"revision": -1,
		"applied_changes": 0,
	}
