class_name FoveaDeltaData
extends RefCounted

## FoveaEngine : Gestion du format binaire de stockage et de compression des Delta-Splats (Task 243 & 247)

const MAGIC := "FVDL"
const VERSION := 1

# Convertit un float standard (32-bit) en half-precision (16-bit float)
static func float_to_half(f: float) -> int:
	if f == 0.0:
		return 0
	var arr := PackedFloat32Array([f])
	var bytes := arr.to_byte_array()
	var bits := bytes.decode_u32(0)
	
	var s := (bits >> 16) & 0x8000
	var e := ((bits >> 23) & 0xFF) - 127 + 15
	var m := bits & 0x007FFFFF
	
	if e <= 0:
		return s
	elif e >= 31:
		return s | 0x7C00 | (m >> 13)
	else:
		return s | (e << 10) | (m >> 13)

# Convertit une valeur half-precision (16-bit float) en float standard (32-bit)
static func half_to_float(h: int) -> float:
	var s := (h & 0x8000) << 16
	var e := (h & 0x7C00) >> 10
	var m := h & 0x03FF
	
	if e == 0:
		if m == 0:
			var arr := PackedByteArray()
			arr.resize(4)
			arr.encode_u32(0, s)
			return arr.to_float32_array()[0]
		else:
			while (m & 0x0400) == 0:
				m <<= 1
				e -= 1
			e += 1
			m &= ~0x0400
			e = e - 15 + 127
			var arr := PackedByteArray()
			arr.resize(4)
			arr.encode_u32(0, s | (e << 23) | (m << 13))
			return arr.to_float32_array()[0]
	elif e == 31:
		var arr := PackedByteArray()
		arr.resize(4)
		arr.encode_u32(0, s | 0x7F800000 | (m << 13))
		return arr.to_float32_array()[0]
	
	e = e - 15 + 127
	var arr := PackedByteArray()
	arr.resize(4)
	arr.encode_u32(0, s | (e << 23) | (m << 13))
	return arr.to_float32_array()[0]

# Packe deux valeurs float16 dans un seul entier 32 bits
static func pack_half_2x16(f1: float, f2: float) -> int:
	var h1 := float_to_half(f1) & 0xFFFF
	var h2 := float_to_half(f2) & 0xFFFF
	return h1 | (h2 << 16)

# Unpacke deux valeurs float16 à partir d'un entier 32 bits
static func unpack_half_2x16(val: int) -> Vector2:
	var f1 := half_to_float(val & 0xFFFF)
	var f2 := half_to_float((val >> 16) & 0xFFFF)
	return Vector2(f1, f2)

# Sauvegarde un ensemble de dictionnaires de deltas vers un fichier binaire compact
static func save_to_file(path: String, splat_count: int, delta_positions: Dictionary, delta_colors: Dictionary, delta_normals: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
		
	# Écriture du header
	file.store_string(MAGIC)
	file.store_32(VERSION)
	file.store_32(splat_count)
	
	# Trouver tous les indices uniques qui ont un delta
	var indices := {}
	for idx in delta_positions.keys():
		indices[idx] = true
	for idx in delta_colors.keys():
		indices[idx] = true
	for idx in delta_normals.keys():
		indices[idx] = true
		
	var sorted_indices := indices.keys()
	sorted_indices.sort()
	
	file.store_32(sorted_indices.size())
	
	# Écriture de chaque delta d'index
	for idx: int in sorted_indices:
		file.store_32(idx)
		
		# Position Delta (3x FP16) -> Packed as: X_Y (uint32), Z (uint16)
		var pos_offset: Vector3 = delta_positions.get(idx, Vector3.ZERO)
		file.store_32(pack_half_2x16(pos_offset.x, pos_offset.y))
		file.store_16(float_to_half(pos_offset.z))
		
		# Color Delta (4x FP16) -> Packed as: R_G (uint32), B_A (uint32)
		var col_offset: Color = delta_colors.get(idx, Color(0, 0, 0, 0))
		file.store_32(pack_half_2x16(col_offset.r, col_offset.g))
		file.store_32(pack_half_2x16(col_offset.b, col_offset.a))
		
		# Normal Delta (2x FP16) -> Packed as: U_V (uint32)
		var norm_offset: Vector2 = delta_normals.get(idx, Vector2.ZERO)
		file.store_32(pack_half_2x16(norm_offset.x, norm_offset.y))
		
	return OK

# Charge les deltas depuis un fichier binaire compact
static func load_from_file(path: String) -> Dictionary:
	var result := {
		"splat_count": 0,
		"delta_positions": {},
		"delta_colors": {},
		"delta_normals": {}
	}
	
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return result
		
	var magic := file.get_buffer(4).get_string_from_ascii()
	if magic != MAGIC:
		push_error("FoveaDeltaData: Mauvais magic number dans le fichier delta.")
		return result
		
	var version := file.get_32()
	if version != VERSION:
		push_error("FoveaDeltaData: Version de fichier delta non supportée.")
		return result
		
	result.splat_count = file.get_32()
	var num_deltas := file.get_32()
	
	for i in range(num_deltas):
		var idx := file.get_32()
		
		# Position
		var pos_xy_packed := file.get_32()
		var pos_z_packed := file.get_16()
		var pos_xy := unpack_half_2x16(pos_xy_packed)
		var pos_z := half_to_float(pos_z_packed)
		result.delta_positions[idx] = Vector3(pos_xy.x, pos_xy.y, pos_z)
		
		# Color
		var col_rg_packed := file.get_32()
		var col_ba_packed := file.get_32()
		var col_rg := unpack_half_2x16(col_rg_packed)
		var col_ba := unpack_half_2x16(col_ba_packed)
		result.delta_colors[idx] = Color(col_rg.x, col_rg.y, col_ba.x, col_ba.y)
		
		# Normal
		var norm_uv_packed := file.get_32()
		var norm_uv := unpack_half_2x16(norm_uv_packed)
		result.delta_normals[idx] = norm_uv
		
	return result
