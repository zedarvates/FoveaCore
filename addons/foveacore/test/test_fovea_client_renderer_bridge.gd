extends SceneTree

## CPU contract tests for translating Godot-owned sparse state to renderer bytes.

const ProtocolScript := preload(
	"res://addons/foveacore/scripts/network/fovea_splat_delta_protocol.gd"
)
const ClientStateScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_splat_state.gd"
)
const BridgeScript := preload(
	"res://addons/foveacore/scripts/network/fovea_client_splat_renderer_bridge.gd"
)
const DeltaDataScript := preload(
	"res://addons/foveacore/scripts/advanced/fovea_delta_data.gd"
)
const ASSET_ID: String = (
	"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
)

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\nFovea Client Renderer Bridge Tests")
	var state: RefCounted = ClientStateScript.new()
	_assert("client state configures", state.configure(ASSET_ID, 10, 0).is_empty(), "")

	var encoded: Dictionary = ProtocolScript.encode_batch(
		ASSET_ID,
		10,
		0,
		1,
		[{
			"index": 2,
			"position": Vector3(0.25, -0.5, 1.5),
			"color": Color(0.5, 0.25, -0.125, 0.0),
			"normal": Vector2(-0.75, 0.125),
		}]
	)
	var applied: Dictionary = state.apply_packet(encoded.get("packet", PackedByteArray()))
	_assert("client owns one applied delta", bool(applied.get("ok", false)), str(applied))

	var bridge_result: Dictionary = BridgeScript.build_renderer_payload(state)
	_assert("configured client state builds a renderer payload", bool(bridge_result.get("ok", false)), str(bridge_result))
	var payload: Dictionary = bridge_result.get("payload", {})
	_assert("payload preserves asset identity", payload.get("asset_id", "") == ASSET_ID, str(payload))
	_assert("payload preserves client revision", int(payload.get("revision", -1)) == 1, str(payload))
	_assert("payload contains ten 24-byte renderer records", payload.get("buffer_bytes", PackedByteArray()).size() == 240, str(payload))

	var bytes: PackedByteArray = payload.get("buffer_bytes", PackedByteArray())
	var missing_xy: Vector2 = DeltaDataScript.unpack_half_2x16(bytes.decode_u32(0))
	_assert("untouched splat remains zero-filled", missing_xy == Vector2.ZERO, str(missing_xy))

	var offset: int = 2 * 24
	var position_xy: Vector2 = DeltaDataScript.unpack_half_2x16(bytes.decode_u32(offset))
	var position_z: float = DeltaDataScript.half_to_float(bytes.decode_u32(offset + 4) & 0xFFFF)
	_assert(
		"renderer position payload matches client state",
		Vector3(position_xy.x, position_xy.y, position_z).distance_to(
			Vector3(0.25, -0.5, 1.5)
		) < 0.002,
		str([position_xy, position_z])
	)
	var color_rg: Vector2 = DeltaDataScript.unpack_half_2x16(bytes.decode_u32(offset + 8))
	var color_ba: Vector2 = DeltaDataScript.unpack_half_2x16(bytes.decode_u32(offset + 12))
	_assert(
		"renderer color payload matches client state",
		Color(color_rg.x, color_rg.y, color_ba.x, color_ba.y).is_equal_approx(
			Color(0.5, 0.25, -0.125, 0.0)
		),
		str([color_rg, color_ba])
	)
	var normal: Vector2 = DeltaDataScript.unpack_half_2x16(bytes.decode_u32(offset + 16))
	_assert("renderer normal payload matches client state", normal.distance_to(Vector2(-0.75, 0.125)) < 0.002, str(normal))

	var positions: Dictionary = payload.get("delta_positions", {})
	positions[2] = Vector3(99.0, 99.0, 99.0)
	_assert(
		"mutating renderer payload cannot mutate client state",
		(state.get_splat_delta(2).get("position", Vector3.ZERO) as Vector3).distance_to(
			Vector3(0.25, -0.5, 1.5)
		) < 0.002,
		str(state.get_splat_delta(2))
	)

	var unconfigured: RefCounted = ClientStateScript.new()
	var invalid_result: Dictionary = BridgeScript.build_renderer_payload(unconfigured)
	_assert("unconfigured client state fails closed", not bool(invalid_result.get("ok", true)), str(invalid_result))

	print("Fovea Client Renderer Bridge Tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
