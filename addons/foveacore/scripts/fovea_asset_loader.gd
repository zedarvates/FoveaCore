@tool
extends ResourceFormatLoader
class_name FoveaAssetFormatLoader

## FoveaAssetFormatLoader - Chargeur de format d'asset personnalisé pour .fovea dans Godot 4
## Désérialise de manière performante le fichier binaire pour instancier une ressource FoveaAsset.

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["fovea"])

func _handles_type(type: StringName) -> bool:
	return type == &"Resource" or type == &"FoveaAsset"

func _get_resource_type(path: String) -> String:
	var ext := path.get_extension().to_lower()
	if ext == "fovea":
		return "FoveaAsset"
	return ""

func _load(path: String, original_path: String, use_sub_threads: bool, cache_mode: int) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("FoveaAssetFormatLoader: Impossible d'ouvrir l'asset en lecture: %s (Code: %d)" % [path, FileAccess.get_open_error()])
		return FileAccess.get_open_error()

	# 1. Lecture de l'en-tête (72 octets)
	var magic_bytes := file.get_buffer(8)
	var magic := magic_bytes.get_string_from_utf8()
	if magic != "FOVEA_3D":
		push_error("FoveaAssetFormatLoader: Magic bytes invalides dans l'asset: %s" % path)
		return ERR_FILE_CORRUPT

	var asset := FoveaAsset.new()

	var version := file.get_32()
	asset.splat_count = file.get_32()
	var color_codebook_size := file.get_32()
	var covar_codebook_size := file.get_32()
	asset.color_codebook_size = color_codebook_size
	asset.covar_codebook_size = covar_codebook_size

	var min_x := file.get_float()
	var min_y := file.get_float()
	var min_z := file.get_float()
	var max_x := file.get_float()
	var max_y := file.get_float()
	var max_z := file.get_float()
	asset.aabb_min = Vector3(min_x, min_y, min_z)
	asset.aabb_max = Vector3(max_x, max_y, max_z)

	var style_offset := file.get_32()
	var style_size := file.get_32()
	var mesh_offset := file.get_32()
	var mesh_size := file.get_32()
	var meta_offset := file.get_32()
	var meta_size := file.get_32()

	# 2. Lecture des Palettes et du Codebook
	if color_codebook_size > 0:
		var palette := FoveaColorPalette.new()
		palette.palette_name = "Loaded Palette"
		palette.palette_size = color_codebook_size
		palette.colors.resize(color_codebook_size)
		for i in range(color_codebook_size):
			var r := file.get_float()
			var g := file.get_float()
			var b := file.get_float()
			palette.colors[i] = Color(r, g, b)
		asset.color_palette = palette

	if covar_codebook_size > 0:
		asset.covariance_codebook = file.get_buffer(covar_codebook_size * 32)

	# 3. Lecture des Splats compactés
	if asset.splat_count > 0:
		asset.splats_raw_bytes = file.get_buffer(asset.splat_count * 16)

	# 4. Lecture et Désérialisation du Style (JSON UTF-8)
	if style_offset > 0 and style_size > 0:
		file.seek(style_offset)
		var json_bytes := file.get_buffer(style_size)
		var json_str := json_bytes.get_string_from_utf8()
		asset.style = _deserialize_style_json(json_str)

	# 5. Lecture et Désérialisation du Maillage Polygonal
	if mesh_offset > 0 and mesh_size > 0:
		file.seek(mesh_offset)
		asset.mesh = _deserialize_mesh(file)

	# 6. Lecture et Désérialisation des Métadonnées (JSON UTF-8)
	if meta_offset > 0 and meta_size > 0:
		file.seek(meta_offset)
		var json_bytes := file.get_buffer(meta_size)
		var json_str := json_bytes.get_string_from_utf8()
		var parser := JSON.new()
		if parser.parse(json_str) == OK:
			if parser.data is Dictionary:
				asset.metadata = parser.data

	file.close()
	return asset

## Désérialise l'objet FoveaStyle depuis sa chaîne JSON
static func _deserialize_style_json(json_str: String) -> FoveaStyle:
	var style := FoveaStyle.new()
	var parser := JSON.new()
	if parser.parse(json_str) != OK:
		push_error("FoveaAssetFormatLoader: Erreur de parsing JSON du Style.")
		return style
	
	var data: Variant = parser.data
	if not data is Dictionary:
		return style
		
	style.mode = data.get("mode", "procedural")
	style.detail = data.get("detail", 1.0)
	style.grain = data.get("grain", 0.5)
	style.light_coherence = data.get("light_coherence", 0.8)
	style.color_saturation = data.get("color_saturation", 0.7)
	style.micro_shadow = data.get("micro_shadow", 0.5)
	style.lora_path = data.get("lora_path", "")
	style.neural_strength = data.get("neural_strength", 0.0)
	style.temporal_coherence = data.get("temporal_coherence", true)
	
	if data.has("stone_params") and data["stone_params"] is Dictionary:
		style.stone_params = _deserialize_material(data["stone_params"] as Dictionary)
	if data.has("wood_params") and data["wood_params"] is Dictionary:
		style.wood_params = _deserialize_material(data["wood_params"] as Dictionary)
	if data.has("metal_params") and data["metal_params"] is Dictionary:
		style.metal_params = _deserialize_material(data["metal_params"] as Dictionary)
	if data.has("skin_params") and data["skin_params"] is Dictionary:
		style.skin_params = _deserialize_material(data["skin_params"] as Dictionary)
		
	return style

static func _deserialize_material(data: Dictionary) -> FoveaMaterial:
	var mat := FoveaMaterial.new()
	mat.material_type = data.get("material_type", 0) as FoveaMaterial.MaterialType
	
	var col_arr: Variant = data.get("base_color", [0.5, 0.5, 0.5, 1.0])
	mat.base_color = Color(col_arr[0], col_arr[1], col_arr[2], col_arr[3])
	
	mat.roughness = data.get("roughness", 0.8)
	mat.metallic = data.get("metallic", 0.0)
	mat.bump_strength = data.get("bump_strength", 0.5)
	mat.specular_strength = data.get("specular_strength", 0.3)
	mat.noise_scale = data.get("noise_scale", 10.0)
	mat.noise_octaves = data.get("noise_octaves", 4)
	mat.noise_lacunarity = data.get("noise_lacunarity", 2.0)
	mat.noise_gain = data.get("noise_gain", 0.5)
	return mat

## Désérialise le maillage 3D polygonal depuis le flux binaire
static func _deserialize_mesh(file: FileAccess) -> ArrayMesh:
	var vertex_count := file.get_32()
	var index_count := file.get_32()
	var has_normals := file.get_8() == 1
	var has_uvs := file.get_8() == 1
	file.get_16() # Sauter le padding d'alignement

	var mesh := ArrayMesh.new()
	if vertex_count == 0 or index_count == 0:
		return mesh

	var vertices := PackedVector3Array()
	vertices.resize(vertex_count)
	for i in range(vertex_count):
		var x := file.get_float()
		var y := file.get_float()
		var z := file.get_float()
		vertices[i] = Vector3(x, y, z)

	var indices := PackedInt32Array()
	indices.resize(index_count)
	for i in range(index_count):
		indices[i] = file.get_32()

	var normals := PackedVector3Array()
	if has_normals:
		normals.resize(vertex_count)
		for i in range(vertex_count):
			var x := file.get_float()
			var y := file.get_float()
			var z := file.get_float()
			normals[i] = Vector3(x, y, z)

	var uvs := PackedVector2Array()
	if has_uvs:
		uvs.resize(vertex_count)
		for i in range(vertex_count):
			var u := file.get_float()
			var v := file.get_float()
			uvs[i] = Vector2(u, v)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	if has_normals:
		arrays[Mesh.ARRAY_NORMAL] = normals
	if has_uvs:
		arrays[Mesh.ARRAY_TEX_UV] = uvs

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
