extends SceneTree

## CPU-only tests for client VRAM admission, priority, and LRU residency.

const ClientStateScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_splat_state.gd"
)
const RendererBridgeScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_splat_renderer_bridge.gd"
)
const BudgetScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_vram_budget.gd"
)

const ASSET_A: String = "sha256:1111111111111111111111111111111111111111111111111111111111111111"
const ASSET_B: String = "sha256:2222222222222222222222222222222222222222222222222222222222222222"
const ASSET_C: String = "sha256:3333333333333333333333333333333333333333333333333333333333333333"
const ASSET_D: String = "sha256:4444444444444444444444444444444444444444444444444444444444444444"

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\nFovea Client VRAM Budget Tests")
	var budget: RefCounted = BudgetScript.new()
	_assert("480-byte client budget configures", budget.configure(480).is_empty(), "")

	var state_a: RefCounted = _configured_state(ASSET_A, 10)
	var state_b: RefCounted = _configured_state(ASSET_B, 10)
	var state_c: RefCounted = _configured_state(ASSET_C, 10)
	var state_d: RefCounted = _configured_state(ASSET_D, 10)

	var admit_a: Dictionary = RendererBridgeScript.build_budgeted_renderer_payload(
		state_a, budget, 10
	)
	_assert("first 240-byte renderer payload is admitted", bool(admit_a.get("ok", false)), str(admit_a))
	_assert("first admission allocates exactly 240 CPU bytes", admit_a.get("payload", {}).get("buffer_bytes", PackedByteArray()).size() == 240, str(admit_a))

	var admit_b: Dictionary = RendererBridgeScript.build_budgeted_renderer_payload(
		state_b, budget, 10
	)
	_assert("second payload fills the 480-byte budget", bool(admit_b.get("ok", false)), str(admit_b))
	_assert("touching first asset updates its LRU age", budget.touch(ASSET_A), "")

	var admit_c: Dictionary = RendererBridgeScript.build_budgeted_renderer_payload(
		state_c, budget, 10
	)
	_assert("equal-priority payload can evict one resident", bool(admit_c.get("ok", false)), str(admit_c))
	_assert("least-recently-used asset B is evicted", admit_c.get("evicted", []) == [ASSET_B], str(admit_c))
	var after_lru: Dictionary = budget.snapshot()
	_assert("recent asset A remains resident", after_lru.get("residents", {}).has(ASSET_A), str(after_lru))
	_assert("new asset C becomes resident", after_lru.get("residents", {}).has(ASSET_C), str(after_lru))

	var promote_a: Dictionary = budget.reserve(ASSET_A, 240, 100)
	_assert("resident asset priority can be promoted", bool(promote_a.get("ok", false)), str(promote_a))
	var before_denial: Dictionary = budget.snapshot()
	var denied_d: Dictionary = RendererBridgeScript.build_budgeted_renderer_payload(
		state_d, budget, 5
	)
	_assert("low-priority request cannot evict higher-priority residents", not bool(denied_d.get("ok", true)), str(denied_d))
	_assert("denied request leaves residency unchanged", budget.snapshot() == before_denial, str(budget.snapshot()))

	var oversized_state: RefCounted = _configured_state("sha256:" + "5".repeat(64), 21)
	var oversized: Dictionary = RendererBridgeScript.build_budgeted_renderer_payload(
		oversized_state, budget, 100
	)
	_assert("504-byte payload is rejected before dense allocation", not bool(oversized.get("ok", true)), str(oversized))
	_assert("oversized request leaves residency unchanged", budget.snapshot() == before_denial, str(budget.snapshot()))

	var shrink: Dictionary = budget.set_capacity(240)
	_assert("budget can shrink dynamically", bool(shrink.get("ok", false)), str(shrink))
	_assert("shrinking evicts lower-priority asset C", shrink.get("evicted", []) == [ASSET_C], str(shrink))
	var after_shrink: Dictionary = budget.snapshot()
	_assert("high-priority asset A survives shrink", after_shrink.get("residents", {}).has(ASSET_A), str(after_shrink))
	_assert("resident bytes respect shrunken capacity", int(after_shrink.get("resident_bytes", -1)) == 240, str(after_shrink))

	_assert("explicit release removes local residency", budget.release(ASSET_A), "")
	_assert("release returns budget usage to zero", int(budget.snapshot().get("resident_bytes", -1)) == 0, str(budget.snapshot()))

	print("Fovea Client VRAM Budget Tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _configured_state(asset_id: String, splat_count: int) -> RefCounted:
	var state: RefCounted = ClientStateScript.new()
	var error: String = state.configure(asset_id, splat_count, 0)
	if not error.is_empty():
		_failed += 1
		print("  FAIL: state fixture configuration -- %s" % error)
	return state


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
