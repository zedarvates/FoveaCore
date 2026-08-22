extends RefCounted
class_name FoveaClientGpuResidency

## Owns real RenderingDevice buffers for client-side splat delta payloads.
##
## CPU admission is delegated to FoveaClientVramBudget. This controller owns
## every RID it creates and frees evicted, replaced, explicitly released, and
## cleanup buffers without transferring rendering ownership outside Godot.

const RendererBridgeScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_splat_renderer_bridge.gd"
)

var rd: RenderingDevice = null
var _residents: Dictionary = {}


func configure(rendering_device: RenderingDevice) -> String:
	if rendering_device == null:
		return "RenderingDevice is required"
	if not _residents.is_empty():
		return "release GPU residents before replacing the RenderingDevice"
	rd = rendering_device
	return ""


func upload(
	client_state: RefCounted,
	vram_budget: RefCounted,
	priority: int = 50
) -> Dictionary:
	if rd == null:
		return _failure("RenderingDevice is not configured")
	var bridge_result: Dictionary = RendererBridgeScript.build_budgeted_renderer_payload(
		client_state,
		vram_budget,
		priority
	)
	if not bool(bridge_result.get("ok", false)):
		return _failure(str(bridge_result.get("error", "renderer payload admission failed")))

	var payload: Dictionary = bridge_result.get("payload", {})
	var asset_id: String = str(payload.get("asset_id", ""))
	var buffer_bytes: PackedByteArray = payload.get("buffer_bytes", PackedByteArray())
	var buffer_rid: RID = rd.storage_buffer_create(buffer_bytes.size(), buffer_bytes)
	if not buffer_rid.is_valid():
		vram_budget.call("release", asset_id)
		return _failure("RenderingDevice storage buffer creation failed")

	var evicted_ids: Array = bridge_result.get("evicted", [])
	for evicted_value: Variant in evicted_ids:
		_free_owned_rid(str(evicted_value))
	if _residents.has(asset_id):
		_free_owned_rid(asset_id)
	_residents[asset_id] = {
		"buffer_rid": buffer_rid,
		"bytes": buffer_bytes.size(),
		"revision": int(payload.get("revision", 0)),
		"priority": priority,
	}
	return {
		"ok": true,
		"error": "",
		"asset_id": asset_id,
		"buffer_rid": buffer_rid,
		"bytes": buffer_bytes.size(),
		"revision": int(payload.get("revision", 0)),
		"evicted": evicted_ids,
	}


func release(asset_id: String, vram_budget: RefCounted) -> bool:
	if not _residents.has(asset_id):
		return false
	_free_owned_rid(asset_id)
	if vram_budget != null and vram_budget.has_method("release"):
		vram_budget.call("release", asset_id)
	return true


func cleanup(vram_budget: RefCounted) -> void:
	var asset_ids: Array = _residents.keys()
	for asset_value: Variant in asset_ids:
		release(str(asset_value), vram_budget)


func snapshot() -> Dictionary:
	return {"residents": _residents.duplicate(true)}


func _free_owned_rid(asset_id: String) -> void:
	if not _residents.has(asset_id):
		return
	var resident: Dictionary = _residents[asset_id]
	var buffer_rid: RID = resident.get("buffer_rid", RID())
	if rd != null and buffer_rid.is_valid():
		rd.free_rid(buffer_rid)
	_residents.erase(asset_id)


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"asset_id": "",
		"buffer_rid": RID(),
		"bytes": 0,
		"revision": -1,
		"evicted": [],
	}
