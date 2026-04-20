class_name PlyLoader

## PlyLoader — Charge les fichiers .ply au format Gaussian Splatting (3DGS)
## Supporte le format PLY ASCII et Binaire Little-Endian
## Propriétés attendues: x y z, f_dc_0/1/2, opacity, scale_0/1/2, rot_0/1/2/3

signal load_progress(percent: float)
signal load_completed(splats: Array)
signal load_failed(reason: String)

## Résultat d'un chargement
class PlyLoadResult:
	var splats: Array[GaussianSplat] = []
	var point_count: int = 0
	var load_time_ms: float = 0.0
	var format: String = ""
	var success: bool = false
	var error_message: String = ""


## Charger un fichier PLY et retourner les splats (synchrone)
static func load_ply(path: String) -> PlyLoadResult:
	var start_time := Time.get_ticks_usec()
	var result := PlyLoadResult.new()

	if not FileAccess.file_exists(path):
		result.error_message = "Fichier introuvable: " + path
		push_error("PlyLoader: " + result.error_message)
		return result

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.error_message = "Impossible d'ouvrir: " + path
		push_error("PlyLoader: " + result.error_message)
		return result

	# --- Parser le header ---
	var header := _parse_header(file)
	if not header.get("valid", false):
		result.error_message = header.get("error", "Header PLY invalide")
		push_error("PlyLoader: " + result.error_message)
		return result

	result.format = header.get("format", "unknown")
	result.point_count = header.get("vertex_count", 0)

	print("PlyLoader: Chargement de %d points (format: %s) depuis %s" % [result.point_count, result.format, path.get_file()])

	# --- Charger les données ---
	if result.format == "ascii":
		result.splats = _load_ascii(file, header)
	elif result.format in ["binary_little_endian", "binary_big_endian"]:
		result.splats = _load_binary(file, header)
	else:
		result.error_message = "Format PLY non supporté: " + result.format
		push_error("PlyLoader: " + result.error_message)
		return result

	file.close()

	result.load_time_ms = (Time.get_ticks_usec() - start_time) / 1000.0
	result.success = true

	print("PlyLoader: %d splats chargés en %.1f ms" % [result.splats.size(), result.load_time_ms])
	return result


## Parser le header PLY
## Retourne un Dictionary avec: valid, format, vertex_count, properties, data_start
static func _parse_header(file: FileAccess) -> Dictionary:
	var header := {
		"valid": false,
		"format": "",
		"vertex_count": 0,
		"properties": [],  # Array de {name, type}
		"data_start": 0,
		"error": ""
	}

	# Vérifier magic word
	var first_line := file.get_line().strip_edges()
	if first_line != "ply":
		header["error"] = "Magic 'ply' manquant (trouvé: '%s')" % first_line
		return header

	var in_vertex_element := false

	while not file.eof_reached():
		var line := file.get_line().strip_edges()

		if line.begins_with("format "):
			var parts := line.split(" ")
			if parts.size() >= 2:
				header["format"] = parts[1]  # ascii / binary_little_endian / binary_big_endian

		elif line.begins_with("element vertex"):
			var parts := line.split(" ")
			if parts.size() >= 3:
				header["vertex_count"] = int(parts[2])
			in_vertex_element = true

		elif line.begins_with("element ") and not line.begins_with("element vertex"):
			# Fin des propriétés vertex
			in_vertex_element = false

		elif line.begins_with("property ") and in_vertex_element:
			var parts := line.split(" ")
			if parts.size() >= 3:
				var prop := {
					"type": parts[1],   # float, uchar, int, double, etc.
					"name": parts[2]    # x, y, z, f_dc_0, opacity, etc.
				}
				header["properties"].append(prop)

		elif line == "end_header":
			header["data_start"] = file.get_position()
			header["valid"] = true
			break

	return header


## Charger les données en format ASCII
static func _load_ascii(file: FileAccess, header: Dictionary) -> Array[GaussianSplat]:
	var splats: Array[GaussianSplat] = []
	var properties: Array = header["properties"]
	var vertex_count: int = header["vertex_count"]

	# Construire un index nom→index pour lookup rapide
	var prop_index := {}
	for i in range(properties.size()):
		prop_index[properties[i]["name"]] = i

	var i := 0
	while not file.eof_reached() and i < vertex_count:
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue

		var values := line.split(" ")
		if values.size() < properties.size():
			continue

		var splat := _build_splat_from_values(values, prop_index)
		if splat:
			splats.append(splat)

		i += 1

	return splats


## Charger les données en format binaire
static func _load_binary(file: FileAccess, header: Dictionary) -> Array[GaussianSplat]:
	var splats: Array[GaussianSplat] = []
	var properties: Array = header["properties"]
	var vertex_count: int = header["vertex_count"]
	var is_little_endian: bool = header["format"] == "binary_little_endian"

	# Calculer la taille d'un vertex en bytes
	var vertex_size := 0
	var prop_offsets := {}  # name → {offset, type}

	for prop in properties:
		prop_offsets[prop["name"]] = {
			"offset": vertex_size,
			"type": prop["type"]
		}
		vertex_size += _sizeof_type(prop["type"])

	if vertex_size == 0:
		push_error("PlyLoader: Taille vertex calculée à 0")
		return splats

	# Construire un index pour lookup
	var prop_index := {}
	for i in range(properties.size()):
		prop_index[properties[i]["name"]] = i

	# Lire les données brutes par blocs
	for _i in range(vertex_count):
		if file.eof_reached():
			break

		var values := []
		for prop in properties:
			var val = _read_typed_value(file, prop["type"], is_little_endian)
			values.append(str(val))

		var splat := _build_splat_from_values(values, prop_index)
		if splat:
			splats.append(splat)

	return splats


## Construire un GaussianSplat depuis les valeurs parsées
static func _build_splat_from_values(values: Array, prop_index: Dictionary) -> GaussianSplat:
	var splat := GaussianSplat.new()

	# Position
	var x := _get_float(values, prop_index, "x", 0.0)
	var y := _get_float(values, prop_index, "y", 0.0)
	var z := _get_float(values, prop_index, "z", 0.0)
	splat.position = Vector3(x, y, z)

	# Couleur depuis les harmoniques sphériques DC (niveau 0)
	# f_dc_0/1/2 = R/G/B en format SH (sigmoide inverse: 0.5 + 0.5*tanh(f_dc))
	var r_sh := _get_float(values, prop_index, "f_dc_0", 0.5)
	var g_sh := _get_float(values, prop_index, "f_dc_1", 0.5)
	var b_sh := _get_float(values, prop_index, "f_dc_2", 0.5)

	# Formulaire inverse: color = sigmoid(SH_DC * C0) où C0 = 0.28209...
	const SH_C0 := 0.28209479177387814
	var r := _sigmoid(r_sh * SH_C0 + 0.5)
	var g := _sigmoid(g_sh * SH_C0 + 0.5)
	var b := _sigmoid(b_sh * SH_C0 + 0.5)
	splat.color = Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(b, 0.0, 1.0))

	# Alt: essayer rouge/vert/bleu directs si f_dc absent
	if not prop_index.has("f_dc_0"):
		var red := _get_float(values, prop_index, "red", -1.0)
		if red >= 0.0:
			splat.color = Color(
				_get_float(values, prop_index, "red", 128.0) / 255.0,
				_get_float(values, prop_index, "green", 128.0) / 255.0,
				_get_float(values, prop_index, "blue", 128.0) / 255.0
			)

	# Opacité (sigmoid inverse du raw opacity)
	var opacity_raw := _get_float(values, prop_index, "opacity", 0.0)
	splat.opacity = _sigmoid(opacity_raw)

	# Scale (exp des log-scales)
	var sx := exp(_get_float(values, prop_index, "scale_0", -2.0))
	var sy := exp(_get_float(values, prop_index, "scale_1", -2.0))
	var sz := exp(_get_float(values, prop_index, "scale_2", -2.0))
	# Rayon = max des 3 échelles
	splat.radius = clampf(maxf(maxf(sx, sy), sz), 0.001, 1.0)

	# Covariance depuis les scales et la rotation (quaternion)
	var avg_scale := (sx + sy + sz) / 3.0
	splat.covariance = Vector2(avg_scale, avg_scale)

	# Rotation quaternion → normale approximative
	var rw := _get_float(values, prop_index, "rot_0", 1.0)
	var rx := _get_float(values, prop_index, "rot_1", 0.0)
	var ry := _get_float(values, prop_index, "rot_2", 0.0)
	var rz := _get_float(values, prop_index, "rot_3", 0.0)
	var q := Quaternion(rx, ry, rz, rw).normalized()
	splat.normal = q * Vector3.UP

	return splat


# --- Helpers ---

static func _get_float(values: Array, prop_index: Dictionary, name: String, default_val: float) -> float:
	if not prop_index.has(name):
		return default_val
	var idx: int = prop_index[name]
	if idx >= values.size():
		return default_val
	return float(values[idx])


static func _sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))


static func _sizeof_type(type_name: String) -> int:
	match type_name:
		"float", "int", "uint": return 4
		"double", "int64", "uint64": return 8
		"short", "ushort": return 2
		"uchar", "char": return 1
		_: return 4


static func _read_typed_value(file: FileAccess, type_name: String, _little_endian: bool) -> float:
	match type_name:
		"float":   return file.get_float()
		"double":  return file.get_double()
		"int":     return float(file.get_32())
		"uint":    return float(file.get_32())
		"short":   return float(file.get_16())
		"ushort":  return float(file.get_16())
		"uchar":   return float(file.get_8())
		"char":    return float(file.get_8())
		_:         return file.get_float()
