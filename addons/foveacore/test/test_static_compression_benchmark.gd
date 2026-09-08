extends SceneTree

const GaussianSplatScript := preload(
	"res://addons/foveacore/scripts/reconstruction/gaussian_splat.gd"
)
const ANALYZER_PATH := (
	"res://addons/foveacore/scripts/reconstruction/static_compression_benchmark.gd"
)

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_exact_two_splat_report()
	_test_rejects_truncated_splat_payload()
	print("Static compression benchmark: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_exact_two_splat_report() -> void:
	var analyzer_script: Variant = load(ANALYZER_PATH)
	if analyzer_script == null:
		_assert_true("analyzer is available", false, ANALYZER_PATH)
		return

	var first: GaussianSplat = GaussianSplatScript.new(Vector3.ZERO)
	first.scale = Vector3.ONE
	first.rotation = Quaternion.IDENTITY
	first.color = Color.RED
	first.opacity = 0.5

	var second: GaussianSplat = GaussianSplatScript.new(Vector3(10.0, 10.0, 10.0))
	second.scale = Vector3(2.0, 2.0, 2.0)
	second.rotation = Quaternion(Vector3.UP, PI * 0.5)
	second.color = Color.BLUE
	second.opacity = 1.0

	var asset := FoveaAsset.new()
	asset.splat_count = 2
	asset.aabb_min = Vector3.ZERO
	asset.aabb_max = Vector3(10.0, 10.0, 10.0)
	asset.color_palette = FoveaColorPalette.new()
	asset.color_palette.colors = [Color.RED, Color.BLUE]
	asset.color_codebook_size = 2
	asset.covariance_codebook = _covariance_bytes([
		{"scale": first.scale, "rotation": first.rotation},
		{"scale": second.scale, "rotation": second.rotation},
	])
	asset.covar_codebook_size = 2
	asset.splats_raw_bytes = _two_splat_payload()

	# 72-byte header + 24-byte palette + 64-byte covariance codebook + 32-byte payload.
	var result: Dictionary = analyzer_script.analyze([first, second], asset, 192)
	_assert_true("exact report succeeds", bool(result.get("ok", false)), str(result))
	if not bool(result.get("ok", false)):
		return
	var metrics: Dictionary = result["metrics"]
	_assert_equal("logical source bytes", int(metrics["logical_source_bytes"]), 112)
	_assert_equal("fixed splat payload bytes", int(metrics["splat_payload_bytes"]), 32)
	_assert_near(
		"encoded/source ratio",
		float(metrics["encoded_to_source_ratio"]),
		192.0 / 112.0,
		0.000001
	)
	_assert_near("position RMSE", float(metrics["position_rmse"]), 0.0, 0.000001)
	_assert_near("scale RMSE", float(metrics["scale_rmse"]), 0.0, 0.000001)
	_assert_near("rotation mean degrees", float(metrics["rotation_mean_degrees"]), 0.0, 0.0001)
	_assert_near("RGB RMSE", float(metrics["color_rmse"]), 0.0, 0.000001)
	var expected_opacity_rmse := sqrt(pow(128.0 / 255.0 - 0.5, 2.0) / 2.0)
	_assert_near(
		"opacity RMSE",
		float(metrics["opacity_rmse"]),
		expected_opacity_rmse,
		0.000001
	)


func _test_rejects_truncated_splat_payload() -> void:
	var analyzer_script: Variant = load(ANALYZER_PATH)
	if analyzer_script == null:
		return
	var source: GaussianSplat = GaussianSplatScript.new(Vector3.ZERO)
	var asset := FoveaAsset.new()
	asset.splat_count = 1
	asset.aabb_min = Vector3.ZERO
	asset.aabb_max = Vector3.ONE
	asset.color_palette = FoveaColorPalette.new()
	asset.color_palette.colors = [Color.WHITE]
	asset.color_codebook_size = 1
	asset.covariance_codebook = _covariance_bytes([
		{"scale": Vector3.ONE, "rotation": Quaternion.IDENTITY},
	])
	asset.covar_codebook_size = 1
	asset.splats_raw_bytes = PackedByteArray([0, 1, 2])
	var result: Dictionary = analyzer_script.analyze([source], asset, 128)
	_assert_true("truncated payload is rejected", not bool(result.get("ok", true)), str(result))


func _covariance_bytes(entries: Array[Dictionary]) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(entries.size() * 32)
	for index: int in range(entries.size()):
		var offset := index * 32
		var scale: Vector3 = entries[index]["scale"]
		var rotation: Quaternion = entries[index]["rotation"]
		bytes.encode_float(offset, scale.x)
		bytes.encode_float(offset + 4, scale.y)
		bytes.encode_float(offset + 8, scale.z)
		bytes.encode_float(offset + 12, rotation.w)
		bytes.encode_float(offset + 16, rotation.x)
		bytes.encode_float(offset + 20, rotation.y)
		bytes.encode_float(offset + 24, rotation.z)
		bytes.encode_float(offset + 28, 0.0)
	return bytes


func _two_splat_payload() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(32)
	# First record: origin, palette 0, covariance 0, opacity 128.
	bytes.encode_u16(0, 0)
	bytes.encode_u16(2, 0)
	bytes.encode_u16(4, 0)
	bytes[8] = 0
	bytes.encode_u16(10, 0)
	bytes[12] = 128
	bytes[15] = GaussianSplat.BrushType.GAUSSIAN
	# Second record: AABB maximum, palette 1, covariance 1, opacity 255.
	bytes.encode_u16(16, 65535)
	bytes.encode_u16(18, 65535)
	bytes.encode_u16(20, 65535)
	bytes[24] = 1
	bytes.encode_u16(26, 1)
	bytes[28] = 255
	bytes[31] = GaussianSplat.BrushType.GAUSSIAN
	return bytes


func _assert_true(name: String, condition: bool, detail: String) -> void:
	if condition:
		_passed += 1
		print("  PASS: %s" % name)
	else:
		_failed += 1
		print("  FAIL: %s -- %s" % [name, detail])


func _assert_equal(name: String, actual: int, expected: int) -> void:
	_assert_true(name, actual == expected, "%d != %d" % [actual, expected])


func _assert_near(name: String, actual: float, expected: float, tolerance: float) -> void:
	_assert_true(name, absf(actual - expected) <= tolerance, "%f != %f" % [actual, expected])
