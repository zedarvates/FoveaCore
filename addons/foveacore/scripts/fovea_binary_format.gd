extends RefCounted
class_name FoveaBinaryFormat

## Canonical constants and structural validation for the little-endian .fovea v2 format.

const MAGIC: String = "FOVEA_3D"
const VERSION: int = 2
const HEADER_SIZE: int = 72
const COLOR_ENTRY_SIZE: int = 12
const COVARIANCE_ENTRY_SIZE: int = 32
const SPLAT_RECORD_SIZE: int = 16
const MAX_COLOR_CODEBOOK_SIZE: int = 256
const MAX_COVARIANCE_CODEBOOK_SIZE: int = 1024
const MESH_HEADER_SIZE: int = 12


static func fixed_payload_end(splat_count: int, color_count: int, covariance_count: int) -> int:
	return (
		HEADER_SIZE
		+ color_count * COLOR_ENTRY_SIZE
		+ covariance_count * COVARIANCE_ENTRY_SIZE
		+ splat_count * SPLAT_RECORD_SIZE
	)


static func is_valid_aabb(aabb_min: Vector3, aabb_max: Vector3) -> bool:
	return (
		is_finite(aabb_min.x)
		and is_finite(aabb_min.y)
		and is_finite(aabb_min.z)
		and is_finite(aabb_max.x)
		and is_finite(aabb_max.y)
		and is_finite(aabb_max.z)
		and aabb_min.x <= aabb_max.x
		and aabb_min.y <= aabb_max.y
		and aabb_min.z <= aabb_max.z
	)


static func validate_layout(
	file_size: int,
	version: int,
	splat_count: int,
	color_count: int,
	covariance_count: int,
	aabb_min: Vector3,
	aabb_max: Vector3,
	optional_sections: Array[Dictionary]
) -> String:
	if file_size < HEADER_SIZE:
		return "file is shorter than the 72-byte header"
	if version != VERSION:
		return "unsupported version %d (expected %d)" % [version, VERSION]
	if splat_count <= 0:
		return "splat_count must be greater than zero"
	if color_count <= 0 or color_count > MAX_COLOR_CODEBOOK_SIZE:
		return "color_codebook_size %d is outside 1..%d" % [color_count, MAX_COLOR_CODEBOOK_SIZE]
	if covariance_count <= 0 or covariance_count > MAX_COVARIANCE_CODEBOOK_SIZE:
		return "covar_codebook_size %d is outside 1..%d" % [covariance_count, MAX_COVARIANCE_CODEBOOK_SIZE]
	if not is_valid_aabb(aabb_min, aabb_max):
		return "AABB contains non-finite or inverted bounds"

	var fixed_end: int = fixed_payload_end(splat_count, color_count, covariance_count)
	if fixed_end < HEADER_SIZE or fixed_end > file_size:
		return "fixed payload ends at %d but file size is %d" % [fixed_end, file_size]

	var present_sections: Array[Dictionary] = []
	for section: Dictionary in optional_sections:
		var section_name: String = str(section.get("name", "optional"))
		var offset: int = int(section.get("offset", 0))
		var size: int = int(section.get("size", 0))
		if (offset == 0) != (size == 0):
			return "%s offset and size must both be zero or both be non-zero" % section_name
		if offset == 0:
			continue
		if offset < fixed_end:
			return "%s begins inside the fixed payload" % section_name
		if size < 0 or offset > file_size or size > file_size - offset:
			return "%s range exceeds the file" % section_name
		present_sections.append({"name": section_name, "offset": offset, "size": size})

	present_sections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["offset"]) < int(b["offset"])
	)
	var previous_end: int = fixed_end
	for section: Dictionary in present_sections:
		var offset: int = int(section["offset"])
		var size: int = int(section["size"])
		if offset < previous_end:
			return "%s overlaps a previous section" % str(section["name"])
		previous_end = offset + size

	return ""
