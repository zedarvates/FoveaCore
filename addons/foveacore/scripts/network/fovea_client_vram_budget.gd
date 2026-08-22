extends RefCounted
class_name FoveaClientVramBudget

## CPU-side VRAM admission model for client-owned splat renderer buffers.
##
## Reservations are tracked by immutable asset ID. Admission evicts lower or
## equal-priority residents by least-recent use, and a rejected request leaves
## the complete residency map unchanged.

const ProtocolScript := preload(
	"res://addons/foveacore/scripts/network/fovea_splat_delta_protocol.gd"
)

var capacity_bytes: int = 0
var resident_bytes: int = 0

var _clock: int = 0
var _residents: Dictionary = {}


func configure(new_capacity_bytes: int) -> String:
	if new_capacity_bytes <= 0:
		return "capacity_bytes must be greater than zero"
	capacity_bytes = new_capacity_bytes
	resident_bytes = 0
	_clock = 0
	_residents.clear()
	return ""


func reserve(asset_id: String, byte_size: int, priority: int = 50) -> Dictionary:
	if capacity_bytes <= 0:
		return _failure("VRAM budget is not configured")
	var identity: Dictionary = ProtocolScript.make_splat_id(asset_id, 0, 1)
	if not bool(identity.get("ok", false)):
		return _failure(str(identity.get("error", "invalid asset identity")))
	if byte_size <= 0:
		return _failure("reservation byte_size must be greater than zero")
	if byte_size > capacity_bytes:
		return _failure("reservation exceeds total VRAM budget")
	if priority < 0 or priority > 100:
		return _failure("priority is outside 0..100")

	var existing_bytes: int = 0
	if _residents.has(asset_id):
		existing_bytes = int((_residents[asset_id] as Dictionary).get("bytes", 0))
	var projected_bytes: int = resident_bytes - existing_bytes + byte_size
	var candidates: Array[Dictionary] = []
	for candidate_id: Variant in _residents.keys():
		if str(candidate_id) == asset_id:
			continue
		var resident: Dictionary = _residents[candidate_id]
		if int(resident.get("priority", 0)) <= priority:
			candidates.append({
				"asset_id": str(candidate_id),
				"bytes": int(resident.get("bytes", 0)),
				"priority": int(resident.get("priority", 0)),
				"last_used": int(resident.get("last_used", 0)),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) < int(b["priority"])
		if int(a["last_used"]) != int(b["last_used"]):
			return int(a["last_used"]) < int(b["last_used"])
		return str(a["asset_id"]) < str(b["asset_id"])
	)

	var planned_evictions: Array[String] = []
	var freed_bytes: int = 0
	for candidate: Dictionary in candidates:
		if projected_bytes - freed_bytes <= capacity_bytes:
			break
		planned_evictions.append(str(candidate["asset_id"]))
		freed_bytes += int(candidate["bytes"])
	if projected_bytes - freed_bytes > capacity_bytes:
		return _failure("higher-priority residency prevents admission")

	for evicted_id: String in planned_evictions:
		var evicted: Dictionary = _residents[evicted_id]
		resident_bytes -= int(evicted.get("bytes", 0))
		_residents.erase(evicted_id)
	if _residents.has(asset_id):
		resident_bytes -= existing_bytes
	_clock += 1
	_residents[asset_id] = {
		"bytes": byte_size,
		"priority": priority,
		"last_used": _clock,
	}
	resident_bytes += byte_size
	return {
		"ok": true,
		"error": "",
		"evicted": planned_evictions,
		"resident_bytes": resident_bytes,
		"capacity_bytes": capacity_bytes,
	}


func touch(asset_id: String) -> bool:
	if not _residents.has(asset_id):
		return false
	_clock += 1
	(_residents[asset_id] as Dictionary)["last_used"] = _clock
	return true


func release(asset_id: String) -> bool:
	if not _residents.has(asset_id):
		return false
	var resident: Dictionary = _residents[asset_id]
	resident_bytes -= int(resident.get("bytes", 0))
	_residents.erase(asset_id)
	return true


func set_capacity(new_capacity_bytes: int) -> Dictionary:
	if new_capacity_bytes <= 0:
		return _failure("capacity_bytes must be greater than zero")
	var candidates: Array[Dictionary] = []
	for asset_id: Variant in _residents.keys():
		var resident: Dictionary = _residents[asset_id]
		candidates.append({
			"asset_id": str(asset_id),
			"bytes": int(resident.get("bytes", 0)),
			"priority": int(resident.get("priority", 0)),
			"last_used": int(resident.get("last_used", 0)),
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) < int(b["priority"])
		if int(a["last_used"]) != int(b["last_used"]):
			return int(a["last_used"]) < int(b["last_used"])
		return str(a["asset_id"]) < str(b["asset_id"])
	)

	var evicted_ids: Array[String] = []
	for candidate: Dictionary in candidates:
		if resident_bytes <= new_capacity_bytes:
			break
		var asset_id: String = str(candidate["asset_id"])
		evicted_ids.append(asset_id)
		resident_bytes -= int(candidate["bytes"])
		_residents.erase(asset_id)
	capacity_bytes = new_capacity_bytes
	return {
		"ok": true,
		"error": "",
		"evicted": evicted_ids,
		"resident_bytes": resident_bytes,
		"capacity_bytes": capacity_bytes,
	}


func snapshot() -> Dictionary:
	return {
		"capacity_bytes": capacity_bytes,
		"resident_bytes": resident_bytes,
		"residents": _residents.duplicate(true),
	}


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
		"evicted": [],
		"resident_bytes": -1,
		"capacity_bytes": -1,
	}
