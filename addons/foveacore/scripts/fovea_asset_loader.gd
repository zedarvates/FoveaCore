@tool
extends ResourceFormatLoader
class_name FoveaAssetFormatLoader

const FoveaBinaryFormatScript := preload("res://addons/foveacore/scripts/fovea_binary_format.gd")

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

	var file_size: int = file.get_length()
	if file_size < FoveaBinaryFormatScript.HEADER_SIZE:
		return _corrupt(file, path, "file is shorter than the canonical header")

	# 1. Lecture de l'en-tête canonique (72 octets, little-endian)
	var magic_bytes: PackedByteArray = file.get_buffer(8)
	var magic: String = magic_bytes.get_string_from_utf8()
	if magic != FoveaBinaryFormatScript.MAGIC:
		return _corrupt(file, path, "invalid magic")

	var asset := FoveaAsset.new()

	var version: int = file.get_32()
	asset.splat_count = file.get_32()
	var color_codebook_size: int = file.get_32()
	var covar_codebook_size: int = file.get_32()
	asset.color_codebook_size = color_codebook_size
	asset.covar_codebook_size = covar_codebook_size

	var min_x: float = file.get_float()
	var min_y: float = file.get_float()
	var min_z: float = file.get_float()
	var max_x: float = file.get_float()
	var max_y: float = file.get_float()
	var max_z: float = file.get_float()
	asset.aabb_min = Vector3(min_x, min_y, min_z)
	asset.aabb_max = Vector3(max_x, max_y, max_z)

	var style_offset: int = file.get_32()
	var style_size: int = file.get_32()
	var mesh_offset: int = file.get_32()
	var mesh_size: int = file.get_32()
	var meta_offset: int = file.get_32()
	var meta_size: int = file.get_32()

	var optional_sections: Array[Dictionary] = [
		{"name": "style", "offset": style_offset, "size": style_size},
		{"name": "mesh", "offset": mesh_offset, "size": mesh_size},
		{"name": "metadata", "offset": meta_offset, "size": meta_size},
	]
	var layout_error: String = FoveaBinaryFormatScript.validate_layout(
		file_size,
		version,
		asset.splat_count,
		color_codebook_size,
		covar_codebook_size,
		asset.aabb_min,
		asset.aabb_max,
		optional_sections
	)
	if not layout_error.is_empty():
		return _corrupt(file, path, layout_error)

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
		asset.covariance_codebook = file.get_buffer(
			covar_codebook_size * FoveaBinaryFormatScript.COVARIANCE_ENTRY_SIZE
		)

	# 3. Lecture des Splats compactés
	if asset.splat_count > 0:
		asset.splats_raw_bytes = file.get_buffer(
			asset.splat_count * FoveaBinaryFormatScript.SPLAT_RECORD_SIZE
		)

	# 4. Lecture et Désérialisation du Style (JSON UTF-8)
	if style_offset > 0 and style_size > 0:
		file.seek(style_offset)
		var json_bytes := file.get_buffer(style_size)
		var json_str := json_bytes.get_string_from_utf8()
		asset.style = _deserialize_style_json(json_str)
		if asset.style == null:
			return _corrupt(file, path, "style section is not valid JSON")

	# 5. Lecture et Désérialisation du Maillage Polygonal
	if mesh_offset > 0 and mesh_size > 0:
		file.seek(mesh_offset)
		asset.mesh = _deserialize_mesh(file, mesh_size)
		if asset.mesh == null:
			return _corrupt(file, path, "mesh section is malformed")

	# 6. Lecture et Désérialisation des Métadonnées (JSON UTF-8)
	if meta_offset > 0 and meta_size > 0:
		file.seek(meta_offset)
		var json_bytes := file.get_buffer(meta_size)
		var json_str := json_bytes.get_string_from_utf8()
		var parser := JSON.new()
		if parser.parse(json_str) != OK or not parser.data is Dictionary:
			return _corrupt(file, path, "metadata section is not a JSON object")
		asset.metadata = parser.data

	file.close()
	return asset


func _corrupt(file: FileAccess, path: String, reason: String) -> Error:
	file.close()
	push_error("FoveaAssetFormatLoader: Asset corrompu '%s': %s" % [path, reason])
	return ERR_FILE_CORRUPT

## Désérialise l'objet FoveaStyle depuis sa chaîne JSON
static func _deserialize_style_json(json_str: String) -> FoveaStyle:
	var parser := JSON.new()
	if parser.parse(json_str) != OK:
		return null
	
	var data: Variant = parser.data
	if not data is Dictionary:
		return null

	var style := FoveaStyle.new()
		
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
	if col_arr is Array and col_arr.size() >= 4:
		mat.base_color = Color(col_arr[0], col_arr[1], col_arr[2], col_arr[3])
	else:
		mat.base_color = Color(0.5, 0.5, 0.5, 1.0)
	
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
static func _deserialize_mesh(file: FileAccess, section_size: int) -> ArrayMesh:
	if section_size < FoveaBinaryFormatScript.MESH_HEADER_SIZE:
		return null
	var vertex_count: int = file.get_32()
	var index_count: int = file.get_32()
	var has_normals_raw: int = file.get_8()
	var has_uvs_raw: int = file.get_8()
	file.get_16() # Sauter le padding d'alignement
	if has_normals_raw > 1 or has_uvs_raw > 1:
		return null
	var has_normals: bool = has_normals_raw == 1
	var has_uvs: bool = has_uvs_raw == 1
	var required_size: int = (
		FoveaBinaryFormatScript.MESH_HEADER_SIZE
		+ vertex_count * 12
		+ index_count * 4
		+ (vertex_count * 12 if has_normals else 0)
		+ (vertex_count * 8 if has_uvs else 0)
	)
	if required_size > section_size:
		return null

	var mesh := ArrayMesh.new()
	if vertex_count == 0 and index_count == 0:
		return mesh
	if vertex_count == 0 or index_count == 0:
		return null

	var vertices := PackedVector3Array()
	vertices.resize(vertex_count)
	for i in range(vertex_count):
		var x := file.get_float()
		var y := file.get_float()
		var z := file.get_float()
		var vertex := Vector3(x, y, z)
		if not FoveaBinaryFormatScript.is_valid_aabb(vertex, vertex):
			return null
		vertices[i] = vertex

	var indices := PackedInt32Array()
	indices.resize(index_count)
	for i in range(index_count):
		var index: int = file.get_32()
		if index < 0 or index >= vertex_count:
			return null
		indices[i] = index

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


## Imports a folder containing sequential native .fovea frames as a flipbook sequence.
## Populates metadata on each FoveaAsset with flipbook_frame index and total flipbook_frame_count.
static func load_flipbook_folder(folder_path: String) -> Array[FoveaAsset]:
	var assets: Array[FoveaAsset] = []
	var dir := DirAccess.open(folder_path)
	if dir == null:
		push_error("FoveaAssetFormatLoader: Cannot open flipbook folder: %s" % folder_path)
		return assets

	var files: Array[String] = []
	dir.list_dir_begin()
	var f_name := dir.get_next()
	while f_name != "":
		if not dir.current_is_dir() and f_name.ends_with(".fovea"):
			files.append(folder_path.path_join(f_name))
		f_name = dir.get_next()
	dir.list_dir_end()

	files.sort()
	var frame_count := files.size()
	var format_loader := FoveaAssetFormatLoader.new()
	for i in range(frame_count):
		var file_path := files[i]
		var res: Variant = format_loader._load(
			file_path, file_path, false, ResourceLoader.CACHE_MODE_IGNORE)
		if res is FoveaAsset:
			var asset := res as FoveaAsset
			asset.flipbook_frame = i
			asset.flipbook_frame_count = frame_count
			assets.append(asset)

	return assets
