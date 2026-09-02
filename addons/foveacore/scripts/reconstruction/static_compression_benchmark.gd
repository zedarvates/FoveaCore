extends RefCounted

const FoveaBinaryFormatScript := preload(
	"res://addons/foveacore/scripts/fovea_binary_format.gd"
)
const FoveaAssetWriterScript := preload(
	"res://addons/foveacore/scripts/fovea_asset_writer.gd"
)

# Position (3), rotation (4), scale (3), opacity (1), and RGB color (3).
# Color alpha is not counted twice because `.fovea` stores opacity separately.
const LOGICAL_FLOATS_PER_SPLAT := 14
const FLOAT_BYTES := 4


static func analyze(source_splats: Array, asset: FoveaAsset, encoded_bytes: int) -> Dictionary:
	var validation_error := _validate_inputs(source_splats, asset, encoded_bytes)
	if not validation_error.is_empty():
		return {"ok": false, "error": validation_error, "metrics": {}}

	var ordered_source := _sort_like_writer(source_splats, asset.aabb_min, asset.aabb_max)
	var position_squared_error := 0.0
	var scale_squared_error := 0.0
	var color_squared_error := 0.0
	var opacity_squared_error := 0.0
	var rotation_degrees_sum := 0.0

	for index: int in range(asset.splat_count):
		var source: GaussianSplat = ordered_source[index]
		var record_offset := index * FoveaBinaryFormatScript.SPLAT_RECORD_SIZE
		var decoded_position := _decode_position(asset, record_offset)
		var color_index: int = asset.splats_raw_bytes[record_offset + 8]
		var covariance_index: int = asset.splats_raw_bytes.decode_u16(record_offset + 10)
		var decoded_opacity := float(asset.splats_raw_bytes[record_offset + 12]) / 255.0
		var decoded_color: Color = asset.color_palette.colors[color_index]
		var covariance := _decode_covariance(asset.covariance_codebook, covariance_index)
		var decoded_scale: Vector3 = covariance["scale"]
		var decoded_rotation: Quaternion = covariance["rotation"]

		position_squared_error += source.position.distance_squared_to(decoded_position)
		scale_squared_error += source.scale.distance_squared_to(decoded_scale)
		var dr := source.color.r - decoded_color.r
		var dg := source.color.g - decoded_color.g
		var db := source.color.b - decoded_color.b
		color_squared_error += dr * dr + dg * dg + db * db
		var opacity_error := source.opacity - decoded_opacity
		opacity_squared_error += opacity_error * opacity_error
		var rotation_dot := clampf(absf(source.rotation.normalized().dot(decoded_rotation)), 0.0, 1.0)
		rotation_degrees_sum += rad_to_deg(2.0 * acos(rotation_dot))

	var count := float(asset.splat_count)
	var logical_source_bytes := asset.splat_count * LOGICAL_FLOATS_PER_SPLAT * FLOAT_BYTES
	return {
		"ok": true,
		"error": "",
		"metrics": {
			"splat_count": asset.splat_count,
			"logical_source_bytes": logical_source_bytes,
			"encoded_bytes": encoded_bytes,
			"splat_payload_bytes": asset.splats_raw_bytes.size(),
			"codebook_bytes": (
				asset.color_palette.colors.size() * FoveaBinaryFormatScript.COLOR_ENTRY_SIZE
				+ asset.covariance_codebook.size()
			),
			"bytes_per_splat": float(encoded_bytes) / count,
			"encoded_to_source_ratio": float(encoded_bytes) / float(logical_source_bytes),
			"position_rmse": sqrt(position_squared_error / (count * 3.0)),
			"scale_rmse": sqrt(scale_squared_error / (count * 3.0)),
			"rotation_mean_degrees": rotation_degrees_sum / count,
			"color_rmse": sqrt(color_squared_error / (count * 3.0)),
			"opacity_rmse": sqrt(opacity_squared_error / count),
		},
	}


static func _validate_inputs(source_splats: Array, asset: FoveaAsset, encoded_bytes: int) -> String:
	if asset == null:
		return "asset is null"
	if encoded_bytes <= 0:
		return "encoded_bytes must be greater than zero"
	if asset.splat_count <= 0 or source_splats.size() != asset.splat_count:
		return "source and asset splat counts must match and be greater than zero"
	var expected_splat_bytes := asset.splat_count * FoveaBinaryFormatScript.SPLAT_RECORD_SIZE
	if asset.splats_raw_bytes.size() != expected_splat_bytes:
		return "splat payload size does not match splat_count"
	if asset.color_palette == null or asset.color_palette.colors.is_empty():
		return "color palette is empty"
	if asset.covariance_codebook.is_empty() \
			or asset.covariance_codebook.size() % FoveaBinaryFormatScript.COVARIANCE_ENTRY_SIZE != 0:
		return "covariance codebook is empty or misaligned"
	if not FoveaBinaryFormatScript.is_valid_aabb(asset.aabb_min, asset.aabb_max):
		return "asset AABB is invalid"

	var covariance_count := asset.covariance_codebook.size() / FoveaBinaryFormatScript.COVARIANCE_ENTRY_SIZE
	for index: int in range(asset.splat_count):
		if not source_splats[index] is GaussianSplat:
			return "source contains a non-GaussianSplat value"
		var offset := index * FoveaBinaryFormatScript.SPLAT_RECORD_SIZE
		if asset.splats_raw_bytes[offset + 8] >= asset.color_palette.colors.size():
			return "splat color index is outside the palette"
		if asset.splats_raw_bytes.decode_u16(offset + 10) >= covariance_count:
			return "splat covariance index is outside the codebook"
	return ""


static func _sort_like_writer(source_splats: Array, aabb_min: Vector3, aabb_max: Vector3) -> Array:
	var range_vector := aabb_max - aabb_min
	var indices := range(source_splats.size())
	var morton_keys := PackedInt64Array()
	morton_keys.resize(source_splats.size())
	for index: int in range(source_splats.size()):
		var splat: GaussianSplat = source_splats[index]
		var qx := _quantize_position_component(splat.position.x, aabb_min.x, range_vector.x)
		var qy := _quantize_position_component(splat.position.y, aabb_min.y, range_vector.y)
		var qz := _quantize_position_component(splat.position.z, aabb_min.z, range_vector.z)
		morton_keys[index] = FoveaAssetWriterScript.morton_encode_3d(qx >> 6, qy >> 6, qz >> 6)
	indices.sort_custom(func(a: int, b: int) -> bool:
		return morton_keys[a] < morton_keys[b]
	)
	var ordered: Array = []
	for index: int in indices:
		ordered.append(source_splats[index])
	return ordered


static func _decode_position(asset: FoveaAsset, offset: int) -> Vector3:
	var range_vector := asset.aabb_max - asset.aabb_min
	return Vector3(
		asset.aabb_min.x + float(asset.splats_raw_bytes.decode_u16(offset)) / 65535.0 * range_vector.x,
		asset.aabb_min.y + float(asset.splats_raw_bytes.decode_u16(offset + 2)) / 65535.0 * range_vector.y,
		asset.aabb_min.z + float(asset.splats_raw_bytes.decode_u16(offset + 4)) / 65535.0 * range_vector.z
	)


static func _decode_covariance(bytes: PackedByteArray, index: int) -> Dictionary:
	var offset := index * FoveaBinaryFormatScript.COVARIANCE_ENTRY_SIZE
	var rotation := Quaternion(
		bytes.decode_float(offset + 16),
		bytes.decode_float(offset + 20),
		bytes.decode_float(offset + 24),
		bytes.decode_float(offset + 12)
	).normalized()
	return {
		"scale": Vector3(
			bytes.decode_float(offset),
			bytes.decode_float(offset + 4),
			bytes.decode_float(offset + 8)
		),
		"rotation": rotation,
	}


static func _quantize_position_component(value: float, minimum: float, extent: float) -> int:
	var safe_extent := maxf(extent, 0.001)
	return int(clampf((value - minimum) / safe_extent * 65535.0, 0.0, 65535.0))
