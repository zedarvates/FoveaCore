extends RefCounted
class_name FoveaClientSplatRendererBridge

## CPU bridge from Godot-owned sparse splat state to the local renderer layout.
##
## It performs no GPU allocation. The returned 24-byte-per-splat buffer matches
## FoveaDeltaManager.register_instance and can be uploaded later by the local
## renderer when a RenderingDevice and VRAM budget are available.

const DeltaDataScript := preload(
	"res://addons/foveacore/scripts/advanced/fovea_delta_data.gd"
)


static func build_renderer_payload(client_state: RefCounted) -> Dictionary:
	if client_state == null or not client_state.has_method("export_sparse_snapshot"):
		return _failure("client state does not expose a sparse snapshot")
	var export_result: Dictionary = client_state.call("export_sparse_snapshot")
	if not bool(export_result.get("ok", false)):
		return _failure(str(export_result.get("error", "invalid client state")))

	var snapshot: Dictionary = export_result.get("snapshot", {})
	var splat_count: int = int(snapshot.get("splat_count", 0))
	if splat_count <= 0:
		return _failure("snapshot splat_count must be greater than zero")
	var positions: Dictionary = snapshot.get("delta_positions", {})
	var colors: Dictionary = snapshot.get("delta_colors", {})
	var normals: Dictionary = snapshot.get("delta_normals", {})
	var buffer_bytes := PackedByteArray()
	buffer_bytes.resize(splat_count * 24)
	for splat_index: int in range(splat_count):
		var offset: int = splat_index * 24
		var position: Vector3 = positions.get(splat_index, Vector3.ZERO)
		buffer_bytes.encode_u32(
			offset,
			DeltaDataScript.pack_half_2x16(position.x, position.y)
		)
		buffer_bytes.encode_u32(
			offset + 4,
			DeltaDataScript.float_to_half(position.z) & 0xFFFF
		)
		var color: Color = colors.get(splat_index, Color(0.0, 0.0, 0.0, 0.0))
		buffer_bytes.encode_u32(offset + 8, DeltaDataScript.pack_half_2x16(color.r, color.g))
		buffer_bytes.encode_u32(offset + 12, DeltaDataScript.pack_half_2x16(color.b, color.a))
		var normal: Vector2 = normals.get(splat_index, Vector2.ZERO)
		buffer_bytes.encode_u32(offset + 16, DeltaDataScript.pack_half_2x16(normal.x, normal.y))
		buffer_bytes.encode_u32(offset + 20, 0)

	return {
		"ok": true,
		"error": "",
		"payload": {
			"asset_id": str(snapshot.get("asset_id", "")),
			"splat_count": splat_count,
			"revision": int(snapshot.get("revision", 0)),
			"delta_positions": positions,
			"delta_colors": colors,
			"delta_normals": normals,
			"buffer_bytes": buffer_bytes,
		},
	}


## Reserves client VRAM before constructing the dense renderer payload.
static func build_budgeted_renderer_payload(
	client_state: RefCounted,
	vram_budget: RefCounted,
	priority: int = 50
) -> Dictionary:
	if vram_budget == null or not vram_budget.has_method("reserve"):
		return _failure("VRAM budget does not expose reservation")
	if client_state == null or not client_state.has_method("export_sparse_snapshot"):
		return _failure("client state does not expose a sparse snapshot")
	var export_result: Dictionary = client_state.call("export_sparse_snapshot")
	if not bool(export_result.get("ok", false)):
		return _failure(str(export_result.get("error", "invalid client state")))
	var snapshot: Dictionary = export_result.get("snapshot", {})
	var asset_id: String = str(snapshot.get("asset_id", ""))
	var splat_count: int = int(snapshot.get("splat_count", 0))
	var required_bytes: int = splat_count * 24
	var reservation: Dictionary = vram_budget.call(
		"reserve",
		asset_id,
		required_bytes,
		priority
	)
	if not bool(reservation.get("ok", false)):
		return {
			"ok": false,
			"error": str(reservation.get("error", "VRAM admission failed")),
			"payload": {},
			"evicted": [],
		}

	var result: Dictionary = build_renderer_payload(client_state)
	if not bool(result.get("ok", false)):
		vram_budget.call("release", asset_id)
		return result
	result["evicted"] = reservation.get("evicted", [])
	result["resident_bytes"] = int(reservation.get("resident_bytes", 0))
	result["capacity_bytes"] = int(reservation.get("capacity_bytes", 0))
	return result


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "payload": {}}
