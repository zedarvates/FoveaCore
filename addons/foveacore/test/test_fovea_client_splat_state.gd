extends SceneTree

## CPU-only tests for the Godot-owned persistent splat delta state.

const ProtocolScript := preload(
	"res://addons/foveacore/scripts/network/fovea_splat_delta_protocol.gd"
)
const ClientStateScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_splat_state.gd"
)
const ASSET_ID: String = (
	"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
)
const OTHER_ASSET_ID: String = (
	"sha256:cb8379ac2098aa165029e3938a51da0bcecfc008fd6795f401178647f96c5b34"
)

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\nFovea Client Splat State Tests")
	var state: RefCounted = ClientStateScript.new()
	var configure_error: String = state.configure(ASSET_ID, 10, 0)
	_assert("valid immutable asset configures client state", configure_error.is_empty(), configure_error)

	var first_packet: PackedByteArray = _encode_packet(
		ASSET_ID,
		10,
		0,
		1,
		[{
			"index": 2,
			"position": Vector3(0.25, -0.5, 1.0),
			"color": Color(0.1, 0.2, 0.3, 0.0),
		}]
	)
	var first_apply: Dictionary = state.apply_packet(first_packet)
	_assert("matching first revision applies", bool(first_apply.get("ok", false)), str(first_apply))
	_assert("client revision advances to one", state.revision == 1, str(state.revision))
	var first_delta: Dictionary = state.get_splat_delta(2)
	_assert(
		"Godot client owns the applied position delta",
		(first_delta.get("position", Vector3.ZERO) as Vector3).distance_to(
			Vector3(0.25, -0.5, 1.0)
		) < 0.002,
		str(first_delta)
	)
	_assert("first delta contains color", first_delta.has("color"), str(first_delta))
	_assert(
		"client state exposes the stable splat ID",
		first_delta.get("splat_id", "") == "%s/2" % ASSET_ID,
		str(first_delta)
	)

	var second_packet: PackedByteArray = _encode_packet(
		ASSET_ID,
		10,
		1,
		2,
		[{"index": 2, "normal": Vector2(-0.5, 0.75)}]
	)
	var second_apply: Dictionary = state.apply_packet(second_packet)
	_assert("next matching revision applies", bool(second_apply.get("ok", false)), str(second_apply))
	var merged_delta: Dictionary = state.get_splat_delta(2)
	_assert("partial update adds the normal", merged_delta.has("normal"), str(merged_delta))
	_assert("partial update preserves position", merged_delta.has("position"), str(merged_delta))
	_assert("partial update preserves color", merged_delta.has("color"), str(merged_delta))

	var before_replay: Dictionary = merged_delta.duplicate(true)
	var replay_result: Dictionary = state.apply_packet(first_packet)
	_assert("replayed revision is rejected", not bool(replay_result.get("ok", true)), str(replay_result))
	_assert("replayed revision cannot roll client state back", state.revision == 2, str(state.revision))
	_assert(
		"replayed revision leaves sparse deltas unchanged",
		state.get_splat_delta(2) == before_replay,
		str(state.get_splat_delta(2))
	)

	var wrong_asset_packet: PackedByteArray = _encode_packet(
		OTHER_ASSET_ID,
		10,
		2,
		3,
		[{"index": 2, "position": Vector3(9.0, 9.0, 9.0)}]
	)
	var wrong_asset_result: Dictionary = state.apply_packet(wrong_asset_packet)
	_assert("packet for another asset is rejected", not bool(wrong_asset_result.get("ok", true)), str(wrong_asset_result))
	_assert("wrong asset cannot advance revision", state.revision == 2, str(state.revision))

	var wrong_count_packet: PackedByteArray = _encode_packet(
		ASSET_ID,
		11,
		2,
		3,
		[{"index": 2, "position": Vector3(8.0, 8.0, 8.0)}]
	)
	var wrong_count_result: Dictionary = state.apply_packet(wrong_count_packet)
	_assert("packet for another asset layout is rejected", not bool(wrong_count_result.get("ok", true)), str(wrong_count_result))
	_assert("wrong layout leaves revision unchanged", state.revision == 2, str(state.revision))

	var corrupt_packet: PackedByteArray = second_packet.duplicate()
	corrupt_packet[0] = corrupt_packet[0] ^ 0xFF
	var corrupt_result: Dictionary = state.apply_packet(corrupt_packet)
	_assert("corrupt packet is rejected before mutation", not bool(corrupt_result.get("ok", true)), str(corrupt_result))
	_assert("corrupt packet leaves deltas unchanged", state.get_splat_delta(2) == before_replay, str(state.get_splat_delta(2)))

	var reconfigure_error: String = state.configure(OTHER_ASSET_ID, 4, 10)
	_assert("client can switch to another local asset", reconfigure_error.is_empty(), reconfigure_error)
	_assert("switching asset resets sparse deltas", state.get_splat_delta(2).is_empty(), str(state.get_splat_delta(2)))
	_assert("switching asset adopts snapshot revision", state.revision == 10, str(state.revision))

	print("Fovea Client Splat State Tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _encode_packet(
	asset_id: String,
	splat_count: int,
	base_revision: int,
	revision: int,
	changes: Array
) -> PackedByteArray:
	var result: Dictionary = ProtocolScript.encode_batch(
		asset_id,
		splat_count,
		base_revision,
		revision,
		changes
	)
	if not bool(result.get("ok", false)):
		_failed += 1
		print("  FAIL: fixture packet encoding -- %s" % str(result))
	return result.get("packet", PackedByteArray())


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
