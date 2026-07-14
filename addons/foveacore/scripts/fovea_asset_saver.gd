@tool
extends ResourceFormatSaver
class_name FoveaAssetFormatSaver

## FoveaAssetFormatSaver - Sauvegarde de format d'asset personnalisé pour .fovea dans Godot 4

func _get_recognized_extensions(resource: Resource) -> PackedStringArray:
	return PackedStringArray(["fovea"])

func _recognize(resource: Resource) -> bool:
	return resource is FoveaAsset

func _save(resource: Resource, path: String, flags: int) -> Error:
	if not (resource is FoveaAsset):
		return ERR_INVALID_PARAMETER

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("FoveaAssetFormatSaver: Impossible d'ouvrir le fichier en écriture: %s" % path)
		return FileAccess.get_open_error()

	var asset := resource as FoveaAsset

	# 1. Écriture temporaire de l'en-tête (72 octets)
	for i in range(72):
		file.store_8(0)

	# 2. Écriture de la Palette de Couleurs (RGB32F)
	if asset.color_palette != null and not asset.color_palette.colors.is_empty():
		for c in asset.color_palette.colors:
			file.store_float(c.r)
			file.store_float(c.g)
			file.store_float(c.b)

	# 3. Écriture du Codebook de Covariance (32 octets par cluster std140)
	if asset.covariance_codebook.size() > 0:
		file.store_buffer(asset.covariance_codebook)

	# 4. Écriture des Splats Compactés (16 octets/splat)
	if asset.splats_raw_bytes.size() > 0:
		file.store_buffer(asset.splats_raw_bytes)

	# Sections optionnelles
	var style_offset := 0
	var style_size := 0
	if asset.style != null:
		style_offset = int(file.get_position())
		var style_dict := _serialize_style(asset.style)
		var style_json := JSON.stringify(style_dict)
		var json_bytes := style_json.to_utf8_buffer()
		file.store_buffer(json_bytes)
		style_size = json_bytes.size()

	var mesh_offset := 0
	var mesh_size := 0
	if asset.mesh != null:
		mesh_offset = int(file.get_position())
		mesh_size = _serialize_mesh(file, asset.mesh)

	var meta_offset := 0
	var meta_size := 0
	if not asset.metadata.is_empty():
		meta_offset = int(file.get_position())
		var meta_json := JSON.stringify(asset.metadata)
		var json_bytes := meta_json.to_utf8_buffer()
		file.store_buffer(json_bytes)
		meta_size = json_bytes.size()

	# 5. Réécriture de l'en-tête finalisé au début du fichier
	var color_codebook_size: int = asset.color_palette.colors.size() if asset.color_palette != null else 0
	var covar_codebook_size: int = asset.covariance_codebook.size() / 32

	file.seek(0)
	file.store_buffer("FOVEA_3D".to_utf8_buffer()) # 8 bytes
	file.store_32(2) # version
	file.store_32(asset.splat_count)
	file.store_32(color_codebook_size)
	file.store_32(covar_codebook_size)
	
	# Bounding box AABB
	file.store_float(asset.aabb_min.x)
	file.store_float(asset.aabb_min.y)
	file.store_float(asset.aabb_min.z)
	file.store_float(asset.aabb_max.x)
	file.store_float(asset.aabb_max.y)
	file.store_float(asset.aabb_max.z)
	
	file.store_32(style_offset)
	file.store_32(style_size)
	file.store_32(mesh_offset)
	file.store_32(mesh_size)
	file.store_32(meta_offset)
	file.store_32(meta_size)

	file.close()
	return OK

# Helper methods for serialization (exactly matching FoveaAssetWriter)
func _serialize_style(style: FoveaStyle) -> Dictionary:
	var dict := {
		"mode": style.mode,
		"detail": style.detail,
		"grain": style.grain,
		"light_coherence": style.light_coherence,
		"color_saturation": style.color_saturation,
		"micro_shadow": style.micro_shadow,
		"lora_path": style.lora_path,
		"neural_strength": style.neural_strength,
		"temporal_coherence": style.temporal_coherence,
	}
	if style.stone_params != null:
		dict["stone_params"] = _serialize_material(style.stone_params)
	if style.wood_params != null:
		dict["wood_params"] = _serialize_material(style.wood_params)
	if style.metal_params != null:
		dict["metal_params"] = _serialize_material(style.metal_params)
	if style.skin_params != null:
		dict["skin_params"] = _serialize_material(style.skin_params)
	return dict

func _serialize_material(mat: FoveaMaterial) -> Dictionary:
	return {
		"material_type": int(mat.material_type),
		"base_color": [mat.base_color.r, mat.base_color.g, mat.base_color.b, mat.base_color.a],
		"roughness": mat.roughness,
		"metallic": mat.metallic,
		"bump_strength": mat.bump_strength,
		"specular_strength": mat.specular_strength,
		"noise_scale": mat.noise_scale,
		"noise_octaves": mat.noise_octaves,
		"noise_lacunarity": mat.noise_lacunarity,
		"noise_gain": mat.noise_gain
	}

func _serialize_mesh(file: FileAccess, mesh: ArrayMesh) -> int:
	var start_pos := file.get_position()
	if mesh.get_surface_count() == 0:
		file.store_32(0) # vertex_count
		file.store_32(0) # index_count
		file.store_8(0)  # has_normals
		file.store_8(0)  # has_uvs
		file.store_16(0) # padding
		return int(file.get_position() - start_pos)
		
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	
	var has_normals := 1 if arrays[Mesh.ARRAY_NORMAL] != null else 0
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if has_normals == 1 else PackedVector3Array()
	
	var has_uvs := 1 if arrays[Mesh.ARRAY_TEX_UV] != null else 0
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if has_uvs == 1 else PackedVector2Array()
	
	file.store_32(vertices.size())
	file.store_32(indices.size())
	file.store_8(has_normals)
	file.store_8(has_uvs)
	file.store_16(0) # padding
	
	for v in vertices:
		file.store_float(v.x)
		file.store_float(v.y)
		file.store_float(v.z)
		
	for idx in indices:
		file.store_32(idx)
		
	if has_normals == 1:
		for n in normals:
			file.store_float(n.x)
			file.store_float(n.y)
			file.store_float(n.z)
			
	if has_uvs == 1:
		for uv in uvs:
			file.store_float(uv.x)
			file.store_float(uv.y)
			
	return int(file.get_position() - start_pos)
