extends SceneTree

## Real GPU lifecycle test for client-owned splat delta buffers.

const REQUIRES_GPU := true

const ProtocolScript := preload(
	"res://addons/foveacore/scripts/network/fovea_splat_delta_protocol.gd"
)
const ClientStateScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_splat_state.gd"
)
const BudgetScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_vram_budget.gd"
)
const ResidencyScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_gpu_residency.gd"
)
const DeltaDataScript := preload(
	"res://addons/foveacore/scripts/advanced/fovea_delta_data.gd"
)

const ASSET_A: String = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const ASSET_B: String = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const ASSET_C: String = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\nFovea Client GPU Residency Tests")
	var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
	_assert("local RenderingDevice is available", rd != null, "")
	if rd == null:
		_finish(null)
		return

	var budget: RefCounted = BudgetScript.new()
	_assert("480-byte VRAM budget configures", budget.configure(480).is_empty(), "")
	var residency: RefCounted = ResidencyScript.new()
	_assert("GPU residency accepts the local device", residency.configure(rd).is_empty(), "")

	var state_a: RefCounted = _configured_state(ASSET_A, Vector3(0.25, 0.5, 1.0))
	var state_b: RefCounted = _configured_state(ASSET_B, Vector3(2.0, 3.0, 4.0))
	var state_c: RefCounted = _configured_state(ASSET_C, Vector3(-0.5, 0.75, 1.5))

	var upload_a: Dictionary = residency.upload(state_a, budget, 10)
	var rid_a: RID = upload_a.get("buffer_rid", RID())
	_assert("asset A allocates a real GPU RID", bool(upload_a.get("ok", false)) and rid_a.is_valid(), str(upload_a))
	var upload_b: Dictionary = residency.upload(state_b, budget, 10)
	var rid_b: RID = upload_b.get("buffer_rid", RID())
	_assert("asset B allocates a second GPU RID", bool(upload_b.get("ok", false)) and rid_b.is_valid(), str(upload_b))

	_assert("touch keeps asset A most recent", budget.touch(ASSET_A), "")
	var upload_c: Dictionary = residency.upload(state_c, budget, 10)
	var rid_c: RID = upload_c.get("buffer_rid", RID())
	_assert("asset C allocates after LRU eviction", bool(upload_c.get("ok", false)) and rid_c.is_valid(), str(upload_c))
	_assert("asset B is reported evicted", upload_c.get("evicted", []) == [ASSET_B], str(upload_c))
	var gpu_snapshot: Dictionary = residency.snapshot()
	_assert("asset A remains GPU-resident", gpu_snapshot.get("residents", {}).has(ASSET_A), str(gpu_snapshot))
	_assert("asset B RID ownership is removed", not gpu_snapshot.get("residents", {}).has(ASSET_B), str(gpu_snapshot))
	_assert("asset C becomes GPU-resident", gpu_snapshot.get("residents", {}).has(ASSET_C), str(gpu_snapshot))

	var bytes_c: PackedByteArray = rd.buffer_get_data(rid_c)
	_assert("GPU readback contains the 240-byte dense payload", bytes_c.size() == 240, str(bytes_c.size()))
	var offset: int = 2 * 24
	var position_xy: Vector2 = DeltaDataScript.unpack_half_2x16(bytes_c.decode_u32(offset))
	var position_z: float = DeltaDataScript.half_to_float(bytes_c.decode_u32(offset + 4) & 0xFFFF)
	_assert(
		"GPU readback preserves client splat delta",
		Vector3(position_xy.x, position_xy.y, position_z).distance_to(
			Vector3(-0.5, 0.75, 1.5)
		) < 0.002,
		str([position_xy, position_z])
	)

	_assert("explicit release frees asset A ownership", residency.release(ASSET_A, budget), "")
	_assert("asset A disappears from GPU residency", not residency.snapshot().get("residents", {}).has(ASSET_A), str(residency.snapshot()))
	residency.cleanup(budget)
	_assert("cleanup removes every GPU resident", residency.snapshot().get("residents", {}).is_empty(), str(residency.snapshot()))
	_assert("cleanup returns budget usage to zero", int(budget.snapshot().get("resident_bytes", -1)) == 0, str(budget.snapshot()))
	_finish(rd)


func _configured_state(asset_id: String, position: Vector3) -> RefCounted:
	var state: RefCounted = ClientStateScript.new()
	var configure_error: String = state.configure(asset_id, 10, 0)
	if not configure_error.is_empty():
		_failed += 1
		print("  FAIL: state fixture configuration -- %s" % configure_error)
		return state
	var encoded: Dictionary = ProtocolScript.encode_batch(
		asset_id,
		10,
		0,
		1,
		[{"index": 2, "position": position}]
	)
	var applied: Dictionary = state.apply_packet(encoded.get("packet", PackedByteArray()))
	if not bool(applied.get("ok", false)):
		_failed += 1
		print("  FAIL: state fixture delta apply -- %s" % str(applied))
	return state


func _finish(rd: RenderingDevice) -> void:
	if rd != null:
		rd.free()
	print("Fovea Client GPU Residency Tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
