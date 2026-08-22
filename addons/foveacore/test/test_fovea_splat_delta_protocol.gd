extends SceneTree

## CPU-only contract tests for authoritative per-splat delta batches.

const ProtocolScript := preload(
	"res://addons/foveacore/scripts/network/fovea_splat_delta_protocol.gd"
)
const ASSET_ID: String = (
	"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
)

var _passed: int = 0
var _failed: int = 0


func _init() -> void:
	print("\nFovea Splat Delta Network Protocol Tests")
	_test_stable_splat_id()
	_test_round_trip()
	_test_validation_boundaries()
	_test_compression_and_corruption()
	print("Fovea Splat Delta Network Protocol Tests: %d passed, %d failed" % [
		_passed, _failed,
	])
	quit(1 if _failed > 0 else 0)


func _test_stable_splat_id() -> void:
	var first: Dictionary = ProtocolScript.make_splat_id(ASSET_ID, 42, 100)
	var second: Dictionary = ProtocolScript.make_splat_id(ASSET_ID, 42, 100)
	_assert("valid asset and index produce a splat ID", bool(first.get("ok", false)), str(first))
	_assert(
		"same immutable asset and index produce the same ID",
		first.get("splat_id", "") == second.get("splat_id", ""),
		str([first, second])
	)
	_assert(
		"splat ID preserves the collision-free asset/index tuple",
		str(first.get("splat_id", "")) == "%s/42" % ASSET_ID,
		str(first)
	)


func _test_round_trip() -> void:
	var changes: Array[Dictionary] = [
		{
			"index": 2,
			"position": Vector3(0.125, -0.25, 1.5),
			"color": Color(0.5, -0.125, 0.25, 0.0),
		},
		{
			"index": 9,
			"normal": Vector2(-0.5, 0.75),
		},
	]
	var encoded: Dictionary = ProtocolScript.encode_batch(ASSET_ID, 10, 7, 8, changes)
	_assert("valid authoritative delta batch encodes", bool(encoded.get("ok", false)), str(encoded))
	var packet: PackedByteArray = encoded.get("packet", PackedByteArray())
	var decoded: Dictionary = ProtocolScript.decode_batch(packet)
	_assert("encoded batch decodes", bool(decoded.get("ok", false)), str(decoded))

	var batch: Dictionary = decoded.get("batch", {})
	_assert("asset identity survives round-trip", batch.get("asset_id", "") == ASSET_ID, str(batch))
	_assert("base revision survives round-trip", int(batch.get("base_revision", -1)) == 7, str(batch))
	_assert("next revision survives round-trip", int(batch.get("revision", -1)) == 8, str(batch))
	_assert("splat count survives round-trip", int(batch.get("splat_count", -1)) == 10, str(batch))
	var decoded_changes: Array = batch.get("changes", [])
	_assert("sparse batch preserves its two changes", decoded_changes.size() == 2, str(decoded_changes))
	if decoded_changes.size() != 2:
		return
	_assert(
		"decoded change receives its stable splat ID",
		decoded_changes[0].get("splat_id", "") == "%s/2" % ASSET_ID,
		str(decoded_changes[0])
	)
	_assert(
		"FP16 position delta remains within tolerance",
		(decoded_changes[0].get("position", Vector3.ZERO) as Vector3).distance_to(
			Vector3(0.125, -0.25, 1.5)
		) < 0.002,
		str(decoded_changes[0])
	)
	_assert(
		"field mask does not invent a normal delta",
		not decoded_changes[0].has("normal"),
		str(decoded_changes[0])
	)
	_assert(
		"normal-only change does not invent position or color",
		decoded_changes[1].has("normal")
			and not decoded_changes[1].has("position")
			and not decoded_changes[1].has("color"),
		str(decoded_changes[1])
	)


func _test_validation_boundaries() -> void:
	var change: Dictionary = {"index": 1, "position": Vector3.ONE}
	var invalid_asset: Dictionary = ProtocolScript.encode_batch(
		"sha256:not-a-digest", 10, 0, 1, [change]
	)
	_assert("malformed asset IDs fail closed", not bool(invalid_asset.get("ok", true)), str(invalid_asset))

	var stale_revision: Dictionary = ProtocolScript.encode_batch(ASSET_ID, 10, 4, 4, [change])
	_assert("non-increasing revisions fail closed", not bool(stale_revision.get("ok", true)), str(stale_revision))

	var duplicate_index: Dictionary = ProtocolScript.encode_batch(
		ASSET_ID, 10, 4, 5, [change, change.duplicate(true)]
	)
	_assert("duplicate splat indices fail closed", not bool(duplicate_index.get("ok", true)), str(duplicate_index))

	var outside_asset: Dictionary = ProtocolScript.encode_batch(
		ASSET_ID, 10, 4, 5, [{"index": 10, "normal": Vector2.ONE}]
	)
	_assert("indices outside the immutable asset fail closed", not bool(outside_asset.get("ok", true)), str(outside_asset))

	var non_finite: Dictionary = ProtocolScript.encode_batch(
		ASSET_ID, 10, 4, 5, [{"index": 1, "position": Vector3(INF, 0.0, 0.0)}]
	)
	_assert("non-finite deltas fail closed", not bool(non_finite.get("ok", true)), str(non_finite))

	var empty_change: Dictionary = ProtocolScript.encode_batch(
		ASSET_ID, 10, 4, 5, [{"index": 1}]
	)
	_assert("changes without a supported field fail closed", not bool(empty_change.get("ok", true)), str(empty_change))


func _test_compression_and_corruption() -> void:
	var repeated_changes: Array[Dictionary] = []
	for index: int in range(256):
		repeated_changes.append({"index": index, "position": Vector3.ZERO})
	var encoded: Dictionary = ProtocolScript.encode_batch(
		ASSET_ID, 256, 100, 101, repeated_changes
	)
	var packet: PackedByteArray = encoded.get("packet", PackedByteArray())
	_assert("repetitive sparse deltas encode", bool(encoded.get("ok", false)), str(encoded))
	_assert(
		"ZSTD packet is smaller than the 7232-byte raw batch",
		packet.size() < 7232,
		"packet bytes=%d" % packet.size()
	)

	var corrupted: PackedByteArray = packet.duplicate()
	if not corrupted.is_empty():
		corrupted[0] = corrupted[0] ^ 0xFF
	var decoded: Dictionary = ProtocolScript.decode_batch(corrupted)
	_assert("corrupted outer framing fails closed", not bool(decoded.get("ok", true)), str(decoded))


func _assert(test_name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % test_name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [test_name, detail])
